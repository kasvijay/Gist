import Foundation
import AVFoundation
import UserNotifications
import WhisperKit
import os

@MainActor
final class RecordingManager: ObservableObject {
    // MARK: - Pipeline State

    enum PipelineStep: Equatable {
        case transcribing, diarizing, summarizing, converting
    }

    @Published var isRecording = false
    @Published var isStarting = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var error: String?
    @Published private(set) var systemAudioActive = false
    @Published var audioDeviceWarning: String?
    @Published var isPaused = false
    @Published var isMicMuted = false
    @Published var micDeviceName: String = "Unknown Microphone"
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0
    @Published var showConsentAlert = false
    @Published var pipelineStep: PipelineStep? = nil
    @Published var processingSessionID: String? = nil
    @Published var activeSessionID: String? = nil

    var isPipelineRunning: Bool { pipelineStep != nil }

    private let pipeline = RecordingPipeline()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "RecordingManager")

    private var timer: Timer?
    private var recordingStart: Date?
    private(set) var lastSession: Session?
    private var pipelineTask: Task<Void, Never>?
    private var pauseStart: Date?
    private var totalPausedDuration: TimeInterval = 0

    // Stashed parameters for consent flow
    private weak var pendingSessionStore: SessionStore?
    private weak var pendingTranscriptionEngine: TranscriptionEngine?
    private weak var pendingDiarizationManager: DiarizationManager?

    // MARK: - Consent Flow

    func startRecording(sessionStore: SessionStore, transcriptionEngine: TranscriptionEngine, diarizationManager: DiarizationManager) {
        guard !isRecording, !isStarting else { return }
        pendingSessionStore = sessionStore
        pendingTranscriptionEngine = transcriptionEngine
        pendingDiarizationManager = diarizationManager
        showConsentAlert = true
    }

    func confirmAndStartRecording() {
        guard let sessionStore = pendingSessionStore,
              let transcriptionEngine = pendingTranscriptionEngine,
              let diarizationManager = pendingDiarizationManager else { return }
        pendingSessionStore = nil
        pendingTranscriptionEngine = nil
        pendingDiarizationManager = nil
        performStartRecording(sessionStore: sessionStore, transcriptionEngine: transcriptionEngine, diarizationManager: diarizationManager)
    }

    func cancelRecording() {
        showConsentAlert = false
        pendingSessionStore = nil
        pendingTranscriptionEngine = nil
        pendingDiarizationManager = nil
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseStart = Date()
        pipeline.setPaused(true)
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        if let start = pauseStart {
            totalPausedDuration += Date().timeIntervalSince(start)
        }
        pauseStart = nil
        isPaused = false
        pipeline.setPaused(false)
    }

    // MARK: - Mic Mute

    func toggleMicMute() {
        isMicMuted.toggle()
        pipeline.setMicMuted(isMicMuted)
    }

    // MARK: - Start Recording (internal)

    private func performStartRecording(sessionStore: SessionStore, transcriptionEngine: TranscriptionEngine, diarizationManager: DiarizationManager) {
        guard !isRecording, !isStarting else { return }
        isStarting = true

        // Check mic permission before attempting to record
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied {
            isStarting = false
            self.error = "Microphone access denied. Grant permission in System Settings → Privacy & Security → Microphone."
            return
        }
        if permission == .undetermined {
            isStarting = false
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.performStartRecording(sessionStore: sessionStore, transcriptionEngine: transcriptionEngine, diarizationManager: diarizationManager)
                    } else {
                        self?.error = "Microphone access is required to record. Grant permission in System Settings → Privacy & Security → Microphone."
                    }
                }
            }
            return
        }

        let session = sessionStore.startSession()
        let audioURL = sessionStore.recordingAudioFileURL(for: session)

        // Pipeline start can block for 1-2s (Core Audio XPC setup) — run off main thread
        let capturedPipeline = pipeline
        Task {
            do {
                try await Task.detached {
                    try capturedPipeline.start(
                        audioURL: audioURL,
                        streamer: nil,
                        onSegmentsUpdated: { _, _ in }
                    )
                }.value

                self.pipeline.onDeviceChanged = { [weak self] recovered in
                    Task { @MainActor in
                        if recovered {
                            self?.audioDeviceWarning = "Audio device changed — mic recovered automatically."
                            try? await Task.sleep(for: .seconds(3))
                            if self?.audioDeviceWarning?.contains("recovered") == true {
                                self?.audioDeviceWarning = nil
                            }
                        } else {
                            self?.audioDeviceWarning = "Microphone disconnected — still capturing system audio. Reconnect the mic, or stop when done."
                        }
                    }
                }

                self.pipeline.onAudioLevels = { [weak self] micRMS, systemRMS in
                    Task { @MainActor in
                        self?.micLevel = micRMS
                        self?.systemLevel = systemRMS
                    }
                }

                self.systemAudioActive = self.pipeline.systemAudioActive
                let captureInfo = self.pipeline.micCaptureInfo
                self.micDeviceName = captureInfo?.deviceName ?? self.pipeline.micDeviceName ?? "Unknown Microphone"
                self.isRecording = true
                self.isStarting = false
                self.recordingStart = Date()
                self.lastSession = session
                self.activeSessionID = session.id
                self.error = nil
                self.audioDeviceWarning = nil
                self.startTimer()
                Self.scheduleRecordingReminders()

                // Persist the device actually used, and warn if the mic is a Bluetooth
                // device (AirPods etc.), which records at reduced call-mode quality.
                if let captureInfo {
                    sessionStore.updateRecordingDevices(Session.Devices(
                        microphone: captureInfo.deviceName,
                        systemAudio: captureInfo.systemOutputName,
                        microphoneTransport: captureInfo.transport,
                        microphoneSampleRate: captureInfo.sampleRate,
                        bluetoothInput: captureInfo.bluetoothInputName
                    ))
                    if let bluetoothName = captureInfo.bluetoothInputName {
                        self.audioDeviceWarning = "\(bluetoothName) records at reduced quality (Bluetooth call mode). For best audio, use the built-in mic or wired headphones."
                    }
                }

                self.logger.info("Recording started: \(session.id), systemAudio: \(self.systemAudioActive)")

            } catch {
                self.isStarting = false
                capturedPipeline.stop()
                self.error = error.localizedDescription
                self.logger.error("Failed to start recording: \(error)")
                // Pipeline never reached writer.start, so no audio is on disk.
                // Discard the metadata-only session folder so CrashRecovery
                // doesn't surface an audio-less ghost on next launch.
                sessionStore.discardEmptySession(session)
            }
        }
    }

    func stopRecording(sessionStore: SessionStore, transcriptionEngine: TranscriptionEngine, diarizationManager: DiarizationManager, summarizationEngine: SummarizationEngine? = nil) -> (session: Session, duration: TimeInterval)? {
        guard isRecording, let session = lastSession else { return nil }

        // Finalize pause if active
        if isPaused { resumeRecording() }

        pipeline.stop()
        stopTimer()
        cancelRecordingReminders()

        let duration = elapsedTime
        isRecording = false
        sessionStore.finishSession(duration: duration)

        logger.info("Recording stopped, duration: \(duration)s")

        // Reset recording state
        elapsedTime = 0
        recordingStart = nil
        systemAudioActive = false
        audioDeviceWarning = nil
        isPaused = false
        isMicMuted = false
        pauseStart = nil
        totalPausedDuration = 0
        micDeviceName = "Unknown Microphone"
        micLevel = 0
        systemLevel = 0
        activeSessionID = nil

        // Launch background pipeline: transcribe → diarize → summarize → convert
        if let summarizationEngine {
            launchPipeline(
                session: session,
                duration: duration,
                sessionStore: sessionStore,
                transcriptionEngine: transcriptionEngine,
                diarizationManager: diarizationManager,
                summarizationEngine: summarizationEngine
            )
        }

        return (session, duration)
    }

    // MARK: - Post-Recording Pipeline

    private func launchPipeline(
        session: Session,
        duration: TimeInterval,
        sessionStore: SessionStore,
        transcriptionEngine: TranscriptionEngine,
        diarizationManager: DiarizationManager,
        summarizationEngine: SummarizationEngine
    ) {
        let sessionID = session.id
        let wavURL = sessionStore.recordingAudioFileURL(for: session)
        let m4aURL = sessionStore.audioFileURL(for: session)
        let registry = ProviderRegistry.shared

        // Capture any in-flight pipeline so we can queue behind it
        let previousTask = pipelineTask

        pipelineTask = Task {
            // Wait for any previously running pipeline to complete
            await previousTask?.value

            processingSessionID = sessionID
            pipelineStep = .transcribing

            let (transProviderID, transModelID) = registry.activeTranscriptionProviderID()

            var transcript: Transcript

            if transProviderID == .localWhisper {
                // Local path — use existing TranscriptionEngine with model switching
                let originalModel = transcriptionEngine.modelName
                let useFullModel = originalModel == "large-v3_turbo"
                if useFullModel {
                    transcriptionEngine.modelName = "large-v3"
                }
                if !transcriptionEngine.isModelLoaded {
                    await transcriptionEngine.loadModel()
                }
                guard let result = await transcriptionEngine.transcribe(
                    audioPath: wavURL.path,
                    duration: duration
                ) else {
                    pipelineStep = nil
                    processingSessionID = nil
                    return
                }
                transcript = result
                transcriptionEngine.unloadModel()
                transcriptionEngine.state = .ready
                if useFullModel {
                    transcriptionEngine.modelName = originalModel
                }
            } else {
                // Cloud path — use provider
                let provider = self.makeTranscriptionProvider(transProviderID, transcriptionEngine: transcriptionEngine)
                do {
                    transcript = try await provider.transcribe(
                        audioURL: wavURL,
                        modelID: transModelID,
                        duration: duration,
                        progress: { _ in }
                    )
                } catch {
                    // Fallback to local if enabled
                    if registry.defaults.fallbackToLocalOnCloudFailure {
                        logger.warning("Cloud transcription failed, falling back to local: \(error.localizedDescription)")
                        if !transcriptionEngine.isModelLoaded {
                            await transcriptionEngine.loadModel()
                        }
                        guard let result = await transcriptionEngine.transcribe(
                            audioPath: wavURL.path,
                            duration: duration
                        ) else {
                            pipelineStep = nil
                            processingSessionID = nil
                            return
                        }
                        transcript = result
                        transcriptionEngine.unloadModel()
                        transcriptionEngine.state = .ready
                    } else {
                        logger.error("Cloud transcription failed: \(error.localizedDescription)")
                        pipelineStep = nil
                        processingSessionID = nil
                        return
                    }
                }
            }

            // Step 3: Speaker identification — skip if provider already includes diarization
            let providerInfo = ProviderCatalog.provider(for: transProviderID)
            if providerInfo?.supportsBuiltInDiarization != true {
                pipelineStep = .diarizing
                if diarizationManager.method == .vbx {
                    await diarizationManager.applySpeakerLabelsAsync(to: &transcript, audioFileURL: wavURL)
                } else {
                    await diarizationManager.applySpeakerLabels(to: &transcript, audioFileURL: wavURL)
                }
            }

            // Step 4: Save transcript
            sessionStore.saveTranscript(transcript, for: session)

            // Step 5: Summarize
            pipelineStep = .summarizing
            let (sumProviderID, sumModelID) = registry.activeSummarizationProviderID()

            if sumProviderID == .localMLX {
                if let summary = await summarizationEngine.summarize(
                    transcript: transcript,
                    transcriptionEngine: transcriptionEngine
                ) {
                    sessionStore.saveSummary(summary, for: sessionID)
                }
                summarizationEngine.unloadModel()
            } else {
                let sumProvider = self.makeSummarizationProvider(sumProviderID, summarizationEngine: summarizationEngine)
                do {
                    let userPrompt = SummaryPromptBuilder.buildUserPrompt(transcript: transcript)
                    let summary = try await sumProvider.summarize(
                        transcript: transcript,
                        modelID: sumModelID,
                        systemPrompt: SummaryPromptBuilder.systemPrompt,
                        userPrompt: userPrompt,
                        stream: { text in
                            Task { @MainActor in
                                summarizationEngine.streamingText = text
                            }
                        }
                    )
                    sessionStore.saveSummary(summary, for: sessionID)
                } catch {
                    logger.error("Cloud summarization failed: \(error.localizedDescription)")
                    // Fallback to local
                    if registry.defaults.fallbackToLocalOnCloudFailure {
                        if let summary = await summarizationEngine.summarize(
                            transcript: transcript,
                            transcriptionEngine: transcriptionEngine
                        ) {
                            sessionStore.saveSummary(summary, for: sessionID)
                        }
                        summarizationEngine.unloadModel()
                    }
                }
            }

            // Step 6: Convert WAV → M4A (verify before deleting WAV)
            pipelineStep = .converting
            await Self.convertAndCleanup(wavURL: wavURL, m4aURL: m4aURL)

            // Done
            pipelineStep = nil
            processingSessionID = nil
        }
    }

    // MARK: - Provider Factory

    private func makeTranscriptionProvider(_ id: ProviderID, transcriptionEngine: TranscriptionEngine) -> any TranscriptionProvider {
        switch id {
        case .localWhisper: return LocalWhisperProvider(engine: transcriptionEngine)
        case .localParakeet: return LocalParakeetProvider()
        case .openAIWhisper: return OpenAIWhisperProvider()
        case .deepgram: return DeepgramProvider()
        case .assemblyAI: return AssemblyAIProvider()
        case .groqTranscription: return GroqTranscriptionProvider()
        case .googleTranscription: return GoogleTranscriptionProvider()
        default: return LocalWhisperProvider(engine: transcriptionEngine)
        }
    }

    private func makeSummarizationProvider(_ id: ProviderID, summarizationEngine: SummarizationEngine) -> any SummarizationProvider {
        switch id {
        case .localMLX: return LocalMLXProvider(engine: summarizationEngine)
        case .anthropic: return AnthropicProvider()
        case .openAISummarization: return OpenAISummarizationProvider()
        case .googleGemini: return GoogleGeminiProvider()
        case .mistral: return MistralProvider()
        case .ollama: return OllamaProvider()
        case .groqSummarization: return GroqSummarizationProvider()
        default: return LocalMLXProvider(engine: summarizationEngine)
        }
    }

    // MARK: - Run Pipeline for Existing Session

    /// Run the full post-recording pipeline (transcribe → diarize → summarize → convert)
    /// for an existing session. Used by "Transcribe Now", "Re-transcribe", and auto-recovery on launch.
    func runPipeline(
        for entry: SessionIndex.SessionEntry,
        sessionStore: SessionStore,
        transcriptionEngine: TranscriptionEngine,
        diarizationManager: DiarizationManager,
        summarizationEngine: SummarizationEngine
    ) {
        guard !isPipelineRunning else { return }

        let sessionID = entry.id
        guard let audioPath = sessionStore.audioPath(for: sessionID) else { return }
        let audioURL = URL(fileURLWithPath: audioPath)
        let registry = ProviderRegistry.shared

        let session = Session(
            id: entry.id, name: entry.name,
            startedAt: entry.startedAt, endedAt: entry.endedAt,
            durationSeconds: entry.durationSeconds, status: .complete
        )

        let wavURL = sessionStore.recordingAudioFileURL(for: session)
        let m4aURL = sessionStore.audioFileURL(for: session)

        processingSessionID = sessionID
        pipelineStep = .transcribing

        let (transProviderID, transModelID) = registry.activeTranscriptionProviderID()

        pipelineTask = Task {
            var transcript: Transcript

            if transProviderID == .localWhisper {
                let originalModel = transcriptionEngine.modelName
                let useFullModel = originalModel == "large-v3_turbo"
                if useFullModel {
                    transcriptionEngine.modelName = "large-v3"
                }
                if !transcriptionEngine.isModelLoaded {
                    await transcriptionEngine.loadModel()
                }
                guard let result = await transcriptionEngine.transcribe(
                    audioPath: audioPath,
                    duration: entry.durationSeconds ?? 0
                ) else {
                    pipelineStep = nil
                    processingSessionID = nil
                    if useFullModel { transcriptionEngine.modelName = originalModel }
                    return
                }
                transcript = result
                transcriptionEngine.unloadModel()
                transcriptionEngine.state = .ready
                if useFullModel {
                    transcriptionEngine.modelName = originalModel
                }
            } else {
                let provider = self.makeTranscriptionProvider(transProviderID, transcriptionEngine: transcriptionEngine)
                do {
                    transcript = try await provider.transcribe(
                        audioURL: audioURL,
                        modelID: transModelID,
                        duration: entry.durationSeconds ?? 0,
                        progress: { _ in }
                    )
                } catch {
                    if registry.defaults.fallbackToLocalOnCloudFailure {
                        logger.warning("Cloud transcription failed, falling back to local: \(error.localizedDescription)")
                        if !transcriptionEngine.isModelLoaded {
                            await transcriptionEngine.loadModel()
                        }
                        guard let result = await transcriptionEngine.transcribe(
                            audioPath: audioPath,
                            duration: entry.durationSeconds ?? 0
                        ) else {
                            pipelineStep = nil
                            processingSessionID = nil
                            return
                        }
                        transcript = result
                        transcriptionEngine.unloadModel()
                        transcriptionEngine.state = .ready
                    } else {
                        logger.error("Cloud transcription failed: \(error.localizedDescription)")
                        pipelineStep = nil
                        processingSessionID = nil
                        return
                    }
                }
            }

            // Speaker identification — skip if provider includes diarization
            let providerInfo = ProviderCatalog.provider(for: transProviderID)
            if providerInfo?.supportsBuiltInDiarization != true {
                pipelineStep = .diarizing
                if diarizationManager.method == .vbx {
                    await diarizationManager.applySpeakerLabelsAsync(to: &transcript, audioFileURL: audioURL)
                } else {
                    await diarizationManager.applySpeakerLabels(to: &transcript, audioFileURL: audioURL)
                }
            }

            sessionStore.saveTranscript(transcript, for: session)

            // Summarize
            pipelineStep = .summarizing
            let (sumProviderID, sumModelID) = registry.activeSummarizationProviderID()

            if sumProviderID == .localMLX {
                if let summary = await summarizationEngine.summarize(
                    transcript: transcript,
                    transcriptionEngine: transcriptionEngine
                ) {
                    sessionStore.saveSummary(summary, for: sessionID)
                }
                summarizationEngine.unloadModel()
            } else {
                let sumProvider = self.makeSummarizationProvider(sumProviderID, summarizationEngine: summarizationEngine)
                do {
                    let userPrompt = SummaryPromptBuilder.buildUserPrompt(transcript: transcript)
                    let summary = try await sumProvider.summarize(
                        transcript: transcript,
                        modelID: sumModelID,
                        systemPrompt: SummaryPromptBuilder.systemPrompt,
                        userPrompt: userPrompt,
                        stream: { text in
                            Task { @MainActor in
                                summarizationEngine.streamingText = text
                            }
                        }
                    )
                    sessionStore.saveSummary(summary, for: sessionID)
                } catch {
                    logger.error("Cloud summarization failed: \(error.localizedDescription)")
                    if registry.defaults.fallbackToLocalOnCloudFailure {
                        if let summary = await summarizationEngine.summarize(
                            transcript: transcript,
                            transcriptionEngine: transcriptionEngine
                        ) {
                            sessionStore.saveSummary(summary, for: sessionID)
                        }
                        summarizationEngine.unloadModel()
                    }
                }
            }

            // Convert WAV → M4A if WAV still exists
            if FileManager.default.fileExists(atPath: wavURL.path) {
                pipelineStep = .converting
                await Self.convertAndCleanup(wavURL: wavURL, m4aURL: m4aURL)
            }

            pipelineStep = nil
            processingSessionID = nil
        }
    }

    /// Wait for the current pipeline to finish. Used to sequence multiple pipelines.
    func waitForPipeline() async {
        await pipelineTask?.value
    }

    // MARK: - WAV to M4A Conversion

    private static let conversionLogger = Logger(subsystem: "com.vijaykas.gist", category: "AudioConversion")

    private static func convertAndCleanup(wavURL: URL, m4aURL: URL) async {
        do {
            _ = try await AudioFileWriter.convertToAAC(wavURL: wavURL, m4aURL: m4aURL)
            // Verify M4A is playable before deleting the WAV source
            guard let m4aDuration = await AudioFileWriter.verifyM4A(url: m4aURL), m4aDuration > 0 else {
                conversionLogger.error("M4A verification failed after conversion, keeping WAV: \(wavURL.lastPathComponent)")
                return
            }
            try? FileManager.default.removeItem(at: wavURL)
            conversionLogger.info("Converted \(wavURL.lastPathComponent) → \(m4aURL.lastPathComponent) (\(String(format: "%.1f", m4aDuration))s)")
        } catch {
            conversionLogger.error("WAV→M4A conversion failed, keeping WAV: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStart else { return }
                let currentPause = self.isPaused ? Date().timeIntervalSince(self.pauseStart ?? Date()) : 0
                self.elapsedTime = Date().timeIntervalSince(start) - self.totalPausedDuration - currentPause
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Recording Reminder Notifications

    // First reminder at 30 min, then every 15 min thereafter (30, 45, 60, …).
    // Pre-scheduled as one-shot triggers because UNTimeIntervalNotificationTrigger
    // only supports a single fixed cadence when repeating. Capped at 6 hours
    // (23 notifications) to stay well under the 64-pending system limit.
    nonisolated private static let reminderIDPrefix = "com.vijaykas.gist.recording-reminder."
    nonisolated private static let reminderFirstMinute = 30
    nonisolated private static let reminderStepMinute = 15
    nonisolated private static let reminderMaxMinute = 360

    nonisolated private static var reminderMinuteMarks: [Int] {
        Array(stride(from: reminderFirstMinute, through: reminderMaxMinute, by: reminderStepMinute))
    }

    /// `nonisolated static` on purpose: `UNUserNotificationCenter` invokes its
    /// `requestAuthorization` / `add` completion handlers on a background queue. If
    /// this were a @MainActor instance method, those closures would inherit
    /// @MainActor isolation and the Swift 6 runtime (macOS 15+/26) would *trap*
    /// when they run off the main actor — crashing the app the instant recording
    /// starts. Keeping it nonisolated and touching no @MainActor state avoids that.
    nonisolated private static func scheduleRecordingReminders() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let logger = Logger(subsystem: "com.vijaykas.gist", category: "RecordingManager")
            for minute in reminderMinuteMarks {
                let content = UNMutableNotificationContent()
                content.title = "Recording Still Active"
                content.body = "Gist has been recording for \(minute) minutes. Open the app to stop when you're done."
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(minute * 60),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "\(reminderIDPrefix)\(minute)",
                    content: content,
                    trigger: trigger
                )
                center.add(request) { error in
                    if let error {
                        logger.error("Failed to schedule \(minute)-min reminder: \(error)")
                    }
                }
            }
        }
    }

    private func cancelRecordingReminders() {
        let ids = Self.reminderMinuteMarks.map { "\(Self.reminderIDPrefix)\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
