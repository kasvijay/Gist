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
            if recordingManager.processingSessionID == sessionID,
               let step = recordingManager.pipelineStep {
                // Pipeline in progress for this session
                pipelineProgressView(step: step, sessionID: sessionID)
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
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Regenerate")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 88/255, green: 132/255, blue: 210/255),
                                    Color(red: 68/255, green: 110/255, blue: 190/255)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .shadow(color: Color(red: 88/255, green: 132/255, blue: 210/255).opacity(0.3), radius: 3, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(summarizationEngine.isWorking || recordingManager.isPipelineRunning)
                    .opacity(summarizationEngine.isWorking || recordingManager.isPipelineRunning ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                Divider()

                // Content — scroll area spans full width, content centered inside
                switch activeTab {
                case .transcript:
                    TranscriptView(
                        transcript: transcript,
                        entry: entry,
                        loadedSummary: loadedSummary
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .summary:
                    SummaryView(
                        summary: loadedSummary,
                        streamingText: summarizationEngine.streamingText,
                        isLoading: summarizationEngine.isWorking,
                        statusMessage: summarizationEngine.statusMessage,
                        entry: entry,
                        transcript: transcript,
                        onRegenerate: nil,
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
                                    // Load model if not in memory
                                    if await !transcriptionEngine.isModelLoaded {
                                        await transcriptionEngine.loadModel()
                                    }
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
                            .disabled(recordingManager.isPipelineRunning)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Pipeline Progress

    private func pipelineProgressView(step: RecordingManager.PipelineStep, sessionID: String) -> some View {
        let entry = sessionStore.sessions.first { $0.id == sessionID }
        let duration = entry?.durationSeconds ?? 0

        return VStack(spacing: 24) {
            Spacer()

            // Step-specific content
            switch step {
            case .transcribing:
                if case .transcribing(let progress) = transcriptionEngine.state {
                    ProgressView(value: Double(progress))
                        .frame(width: 220)
                    Text("Transcribing… \(Int(progress * 100))%")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if duration > 0 {
                        Text("\(formatTime(Double(progress) * duration)) / \(formatTime(duration))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    Text("This may take a moment for long recordings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if case .downloading(let m, let progress) = transcriptionEngine.state {
                    ProgressView(value: Double(progress))
                        .frame(width: 220)
                    Text("Downloading \(m)… \(Int(progress * 100))%")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("First-time setup — this only happens once.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if case .loading(let m) = transcriptionEngine.state {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading \(m)…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Preparing the transcription model.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Preparing transcription…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

            case .diarizing:
                ProgressView()
                    .controlSize(.regular)
                Text("Identifying speakers…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Analyzing speaker patterns in the recording.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

            case .summarizing:
                switch summarizationEngine.state {
                case .downloading(let progress):
                    ProgressView(value: Double(progress))
                        .frame(width: 220)
                    Text("Downloading summarization model… \(Int(progress * 100))%")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("First-time setup — this only happens once.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                case .loading:
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading summarization model…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Preparing the summary model.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                default:
                    ProgressView()
                        .controlSize(.regular)
                    Text("Generating summary…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Creating an overview of your meeting.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

            case .converting:
                ProgressView()
                    .controlSize(.regular)
                Text("Saving audio…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Compressing recording for storage.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Step indicator
            HStack(spacing: 20) {
                stepIndicator("Transcribe", active: step == .transcribing,
                              done: step == .diarizing || step == .summarizing || step == .converting)
                stepIndicator("Speakers", active: step == .diarizing,
                              done: step == .summarizing || step == .converting)
                stepIndicator("Summary", active: step == .summarizing,
                              done: step == .converting)
                stepIndicator("Save", active: step == .converting, done: false)
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func stepIndicator(_ label: String, active: Bool, done: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : (active ? Color.accentColor : Color.secondary.opacity(0.2)))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else if active {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(active ? .primary : .secondary)
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
