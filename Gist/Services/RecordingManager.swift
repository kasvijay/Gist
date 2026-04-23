import Foundation
import AVFoundation
import WhisperKit
import os

@MainActor
final class RecordingManager: ObservableObject {
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

    private let pipeline = RecordingPipeline()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "RecordingManager")

    private var timer: Timer?
    private var partialSaveTimer: Timer?
    private var recordingStart: Date?
    private(set) var lastSession: Session?
    private var streamingTranscriber: StreamingTranscriber?
    private var streamingTask: Task<Void, Never>?
    private var pauseStart: Date?
    private var totalPausedDuration: TimeInterval = 0

    // Weak references for partial save timer
    private weak var activeSessionStore: SessionStore?
    private weak var activeTranscriptionEngine: TranscriptionEngine?

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

        let streamer = transcriptionEngine.makeStreamingTranscriber(sampleRate: 16000)
        self.streamingTranscriber = streamer

        // Pipeline start can block for 1-2s (Core Audio XPC setup) — run off main thread
        let capturedPipeline = pipeline
        Task {
            do {
                try await Task.detached {
                    try capturedPipeline.start(
                        audioURL: audioURL,
                        streamer: streamer,
                        onSegmentsUpdated: { [weak transcriptionEngine] confirmed, unconfirmed in
                            Task { @MainActor in
                                transcriptionEngine?.updateLiveSegments(confirmed: confirmed, unconfirmed: unconfirmed)
                            }
                        }
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
                self.activeSessionStore = sessionStore
                self.activeTranscriptionEngine = transcriptionEngine
                self.error = nil
                self.audioDeviceWarning = nil
                self.startTimer()
                self.startPartialSaveTimer()

                transcriptionEngine.startStreaming()
                if let streamer = self.streamingTranscriber {
                    self.streamingTask = Task.detached {
                        await streamer.start()
                    }
                }

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

        streamingTranscriber?.stop()
        streamingTask?.cancel()
        let allSegments = streamingTranscriber?.allSegments() ?? []

        pipeline.stop()
        stopTimer()
        stopPartialSaveTimer()

        let duration = elapsedTime
        isRecording = false
        sessionStore.finishSession(duration: duration)

        if var transcript = transcriptionEngine.finalizeStreaming(allSegments: allSegments, duration: duration) {
            let wavURL = sessionStore.recordingAudioFileURL(for: session)
            let m4aURL = sessionStore.audioFileURL(for: session)
            let sessionID = session.id
            let useVBx = diarizationManager.method == .vbx
            let shouldSummarize = UserDefaults.standard.object(forKey: "autoSummarize") as? Bool ?? false

            // Post-recording work (diarization, summarization, conversion) runs off main thread
            if useVBx {
                let txEngine = transcriptionEngine
                Task.detached {
                    await diarizationManager.applySpeakerLabelsAsync(to: &transcript, audioFileURL: wavURL)
                    await sessionStore.saveTranscript(transcript, for: session)
                    if shouldSummarize, let engine = summarizationEngine {
                        if let summary = await engine.summarize(transcript: transcript, transcriptionEngine: txEngine) {
                            await sessionStore.saveSummary(summary, for: sessionID)
                        }
                    }
                    await Self.convertAndCleanup(wavURL: wavURL, m4aURL: m4aURL)
                }
            } else {
                diarizationManager.applySpeakerLabels(to: &transcript, audioFileURL: wavURL)
                sessionStore.saveTranscript(transcript, for: session)
                let txEngine = transcriptionEngine
                Task.detached {
                    if shouldSummarize, let engine = summarizationEngine {
                        if let summary = await engine.summarize(transcript: transcript, transcriptionEngine: txEngine) {
                            await sessionStore.saveSummary(summary, for: sessionID)
                        }
                    }
                    await Self.convertAndCleanup(wavURL: wavURL, m4aURL: m4aURL)
                }
            }
        }

        logger.info("Recording stopped, duration: \(duration)s, segments: \(allSegments.count)")

        elapsedTime = 0
        recordingStart = nil
        streamingTranscriber = nil
        streamingTask = nil
        activeSessionStore = nil
        activeTranscriptionEngine = nil
        systemAudioActive = false
        audioDeviceWarning = nil
        isPaused = false
        isMicMuted = false
        pauseStart = nil
        totalPausedDuration = 0
        micDeviceName = "Unknown Microphone"
        micLevel = 0
        systemLevel = 0

        return (session, duration)
    }

    // MARK: - WAV to M4A Conversion

    private static let conversionLogger = Logger(subsystem: "com.vijaykas.gist", category: "AudioConversion")

    private static func convertAndCleanup(wavURL: URL, m4aURL: URL) async {
        do {
            _ = try await AudioFileWriter.convertToAAC(wavURL: wavURL, m4aURL: m4aURL)
            try? FileManager.default.removeItem(at: wavURL)
            conversionLogger.info("Converted \(wavURL.lastPathComponent) → \(m4aURL.lastPathComponent)")
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

    // MARK: - Partial Transcript Auto-Save

    private func startPartialSaveTimer() {
        partialSaveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.savePartialTranscript()
            }
        }
    }

    private func stopPartialSaveTimer() {
        partialSaveTimer?.invalidate()
        partialSaveTimer = nil
    }

    private func savePartialTranscript() {
        guard let session = lastSession,
              let streamer = streamingTranscriber,
              let store = activeSessionStore,
              let engine = activeTranscriptionEngine else { return }
        let segments = streamer.allSegments()
        guard !segments.isEmpty else { return }
        let partial = Transcript.from(
            whisperSegments: segments,
            duration: elapsedTime,
            model: engine.modelName,
            language: "en"
        )
        store.savePartialTranscript(partial, for: session)
    }
}
