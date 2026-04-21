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

    private let pipeline = RecordingPipeline()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "RecordingManager")

    private var timer: Timer?
    private var partialSaveTimer: Timer?
    private var recordingStart: Date?
    private(set) var lastSession: Session?
    private var streamingTranscriber: StreamingTranscriber?
    private var streamingTask: Task<Void, Never>?

    // Weak references for partial save timer
    private weak var activeSessionStore: SessionStore?
    private weak var activeTranscriptionEngine: TranscriptionEngine?

    func startRecording(sessionStore: SessionStore, transcriptionEngine: TranscriptionEngine, diarizationManager: DiarizationManager) {
        guard !isRecording, !isStarting else { return }

        // Check mic permission before attempting to record
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied {
            self.error = "Microphone access denied. Grant permission in System Settings → Privacy & Security → Microphone."
            return
        }
        if permission == .undetermined {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecording(sessionStore: sessionStore, transcriptionEngine: transcriptionEngine, diarizationManager: diarizationManager)
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
        isStarting = true

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

                self.systemAudioActive = self.pipeline.systemAudioActive
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
            let shouldSummarize = UserDefaults.standard.object(forKey: "autoSummarize") as? Bool ?? true

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
                self.elapsedTime = Date().timeIntervalSince(start)
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
