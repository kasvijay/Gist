import SwiftUI
import WhisperKit

struct SessionDetailView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var diarizationManager: DiarizationManager
    @EnvironmentObject var summarizationEngine: SummarizationEngine

    @Binding var selectedSessionID: String?

    enum DetailTab { case transcript, summary }
    @State private var activeTab: DetailTab = .transcript

    var body: some View {
        VStack(spacing: 0) {
            if recordingManager.isRecording {
                recordingView
            } else if let sessionID = selectedSessionID {
                savedSessionView(sessionID: sessionID)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedSessionID) {
            // Clear stale summary state when switching sessions
            summarizationEngine.currentSummary = nil
            summarizationEngine.streamingText = ""
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 0) {
            // Recording header
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Recording")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer()
                    Text(formatTime(recordingManager.elapsedTime))
                        .font(.title2)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                statusBadge

                if let warning = recordingManager.audioDeviceWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding()

            Divider()

            // Live transcript
            if !transcriptionEngine.liveConfirmedSegments.isEmpty ||
               !transcriptionEngine.liveUnconfirmedSegments.isEmpty {
                LiveTranscriptView(
                    confirmedSegments: transcriptionEngine.liveConfirmedSegments,
                    unconfirmedSegments: transcriptionEngine.liveUnconfirmedSegments
                )
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for speech...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Saved Session

    private func savedSessionView(sessionID: String) -> some View {
        VStack(spacing: 0) {
            if case .transcribing(let progress) = transcriptionEngine.state {
                // Transcription in progress — full-area feedback
                let entry = sessionStore.sessions.first { $0.id == sessionID }
                let duration = entry?.durationSeconds ?? 0
                let processedSeconds = Double(progress) * duration
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView(value: Double(progress))
                        .frame(width: 200)
                    Text("Transcribing… \(Int(progress * 100))%")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if duration > 0 {
                        Text("\(formatTime(processedSeconds)) / \(formatTime(duration))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            } else if let transcript = sessionStore.loadTranscript(for: sessionID) {
                // Model info + Tab bar + Summarize button
                HStack {
                    Text("Model: \(transcript.model)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)

                HStack {
                    Picker("View", selection: $activeTab) {
                        Text("Transcript").tag(DetailTab.transcript)
                        Text("Summary").tag(DetailTab.summary)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Spacer()

                    if activeTab == .transcript {
                        Button {
                            activeTab = .summary
                            summarizationEngine.startSummarization(
                                transcript: transcript,
                                transcriptionEngine: transcriptionEngine
                            ) { summary in
                                if let summary {
                                    sessionStore.saveSummary(summary, for: sessionID)
                                }
                            }
                        } label: {
                            Label("Summarize", systemImage: "sparkles")
                        }
                        .controlSize(.small)
                        .disabled(summarizationEngine.isWorking)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                switch activeTab {
                case .transcript:
                    TranscriptView(transcript: transcript)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .summary:
                    SummaryView(
                        summary: summarizationEngine.currentSummary ?? sessionStore.loadSummary(for: sessionID),
                        streamingText: summarizationEngine.streamingText,
                        isLoading: summarizationEngine.isWorking,
                        statusMessage: summarizationEngine.statusMessage,
                        onRegenerate: {
                            summarizationEngine.currentSummary = nil
                            summarizationEngine.startSummarization(
                                transcript: transcript,
                                transcriptionEngine: transcriptionEngine
                            ) { summary in
                                if let summary {
                                    sessionStore.saveSummary(summary, for: sessionID)
                                }
                            }
                        },
                        onCancel: {
                            summarizationEngine.cancel()
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // No transcript yet
                VStack(spacing: 12) {
                    Spacer()
                    if case .downloading(let m, let progress) = transcriptionEngine.state {
                        ProgressView(value: Double(progress))
                            .frame(width: 200)
                        Text("Downloading model \(m) — \(Int(progress * 100))%")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Transcription will be available once the download completes.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if case .loading(let m) = transcriptionEngine.state {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Loading model \(m)…")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else if case .error(let msg) = transcriptionEngine.state {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("Model Error")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else {
                        Image(systemName: "text.page.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No transcript")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if let audioPath = sessionStore.audioPath(for: sessionID) {
                            Button("Transcribe Now") {
                                let entry = sessionStore.sessions.first { $0.id == sessionID }
                                let audioURL = URL(fileURLWithPath: audioPath)
                                Task.detached {
                                    if var transcript = await transcriptionEngine.transcribe(
                                        audioPath: audioPath,
                                        duration: entry?.durationSeconds ?? 0
                                    ) {
                                        if await diarizationManager.method == .vbx {
                                            await diarizationManager.applySpeakerLabelsAsync(to: &transcript, audioFileURL: audioURL)
                                        } else {
                                            await diarizationManager.applySpeakerLabels(to: &transcript, audioFileURL: audioURL)
                                        }
                                        if let entry {
                                            let s = Session(
                                                id: entry.id, name: entry.name,
                                                startedAt: entry.startedAt, endedAt: entry.endedAt,
                                                durationSeconds: entry.durationSeconds, status: .complete
                                            )
                                            await sessionStore.saveTranscript(transcript, for: s)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Gist")
                .font(.largeTitle)
                .fontWeight(.medium)
            Text("Press record or select a session")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch transcriptionEngine.state {
        case .loading(let model):
            badge("Loading \(model)...", icon: "arrow.down.circle")
        case .streaming:
            badge("Live transcription", icon: "waveform")
        case .transcribing:
            badge("Transcribing...", icon: "text.magnifyingglass")
        case .error(let msg):
            Text(msg).font(.caption).foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
