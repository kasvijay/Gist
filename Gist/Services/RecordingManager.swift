import Foundation
import AVFoundation
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
        guard !isRecording, !isStarting, !isPipelineRunning else { return }
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
                            self?.audioDeviceWarning = "Audio device changed — reconnecting mic..."
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
                self.micDeviceName = self.pipeline.micDeviceName ?? "Unknown Microphone"
                self.isRecording = true
                self.isStarting = false
                self.recordingStart = Date()
                self.lastSession = session
                self.error = nil
                self.audioDeviceWarning = nil
                self.startTimer()

                self.logger.info("Recording started: \(session.id), systemAudio: \(self.systemAudioActive)")

            } catch {
                self.isStarting = false
                capturedPipeline.stop()
                self.error = error.localizedDescription
                self.logger.error("Failed to start recording: \(error)")
            }
        }
    }

    func stopRecording(sessionStore: SessionStore, transcriptionEngine: TranscriptionEngine, diarizationManager: DiarizationManager, summarizationEngine: SummarizationEngine? = nil) -> (session: Session, duration: TimeInterval)? {
        guard isRecording, let session = lastSession else { return nil }

        // Finalize pause if active
        if isPaused { resumeRecording() }

        pipeline.stop()
        stopTimer()

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

        processingSessionID = sessionID
        pipelineStep = .transcribing

        pipelineTask = Task {
            // Step 1: Full-file transcription
            guard var transcript = await transcriptionEngine.transcribe(
                audioPath: wavURL.path,
                duration: duration
            ) else {
                pipelineStep = nil
                processingSessionID = nil
                return
            }

            // Unload WhisperKit — no longer needed
            transcriptionEngine.unloadModel()

            // Step 2: Speaker identification (VBx)
            pipelineStep = .diarizing
            if diarizationManager.method == .vbx {
                await diarizationManager.applySpeakerLabelsAsync(to: &transcript, audioFileURL: wavURL)
            } else {
                await diarizationManager.applySpeakerLabels(to: &transcript, audioFileURL: wavURL)
            }

            // Step 3: Save transcript
            sessionStore.saveTranscript(transcript, for: session)

            // Step 4: Summarize (downloads model if needed)
            pipelineStep = .summarizing
            if let summary = await summarizationEngine.summarize(
                transcript: transcript,
                transcriptionEngine: transcriptionEngine
            ) {
                sessionStore.saveSummary(summary, for: sessionID)
            }

            // Unload Gemma — no longer needed
            summarizationEngine.unloadModel()

            // Step 5: Convert WAV → M4A (verify before deleting WAV)
            pipelineStep = .converting
            await Self.convertAndCleanup(wavURL: wavURL, m4aURL: m4aURL)

            // Done
            pipelineStep = nil
            processingSessionID = nil
        }
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

}
