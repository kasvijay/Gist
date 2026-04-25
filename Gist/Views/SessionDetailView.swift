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
    @State private var activeTab: DetailTab = .summary

    var onStop: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if recordingManager.isRecording {
                RecordingView {
                    onStop?()
                }
            } else if let sessionID = selectedSessionID {
                savedSessionView(sessionID: sessionID)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
        .onChange(of: selectedSessionID) {
            // Clear stale summary state when switching sessions
            summarizationEngine.currentSummary = nil
            summarizationEngine.streamingText = ""
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
                let entry = sessionStore.sessions.first { $0.id == sessionID }
                let loadedSummary = summarizationEngine.currentSummary ?? sessionStore.loadSummary(for: sessionID)

                // Toolbar row: title + date on left, tabs + regenerate on right
                HStack(spacing: 12) {
                    // Session title + abbreviated date
                    Text(entry?.name ?? "Session")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if let date = entry?.startedAt {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(date, format: .dateTime.hour().minute())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("", selection: $activeTab) {
                        Text("Summary").tag(DetailTab.summary)
                        Text("Transcript").tag(DetailTab.transcript)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Button {
                        if activeTab != .summary { activeTab = .summary }
                        summarizationEngine.currentSummary = nil
                        summarizationEngine.startSummarization(
                            transcript: transcript,
                            transcriptionEngine: transcriptionEngine
                        ) { summary in
                            if let summary {
                                sessionStore.saveSummary(summary, for: sessionID)
                            }
                        }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .disabled(summarizationEngine.isWorking)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                Divider()

                // Centered content column
                VStack(spacing: 0) {
                    // Session header
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = entry?.startedAt {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                        }

                        Text(entry?.name ?? "Session")
                            .font(.system(size: 24, weight: .bold))

                        // Metadata row
                        HStack(spacing: 16) {
                            if let duration = entry?.durationSeconds {
                                Label(formatTime(duration), systemImage: "clock")
                            }
                            if let speakers = transcript.speakers, !speakers.isEmpty {
                                Label("\(speakers.count) speakers", systemImage: "person.2")
                            }
                            Label(transcript.model, systemImage: "waveform")
                            if let actions = loadedSummary?.actionItems, !actions.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "checklist")
                                    Text("\u{2022} \(actions.count) open actions")
                                }
                                .foregroundStyle(.green)
                                .fontWeight(.medium)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Content
                    switch activeTab {
                    case .transcript:
                        TranscriptView(transcript: transcript)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .summary:
                        SummaryView(
                            summary: loadedSummary,
                            streamingText: summarizationEngine.streamingText,
                            isLoading: summarizationEngine.isWorking,
                            statusMessage: summarizationEngine.statusMessage,
                            onRegenerate: nil,
                            onCancel: {
                                summarizationEngine.cancel()
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
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
