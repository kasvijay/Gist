import SwiftUI
import WhisperKit

struct SessionDetailView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var diarizationManager: DiarizationManager
    @EnvironmentObject var summarizationEngine: SummarizationEngine
    @EnvironmentObject var audioPlayer: AudioPlayerService

    @Binding var selectedSessionID: String?

    enum DetailTab { case transcript, summary }
    @State private var activeTab: DetailTab = .summary
    @State private var showRegenerateConfirm = false
    @State private var showRetranscribeConfirm = false
    @State private var summarizingSessionID: String?
    @State private var copiedAt: Date?
    @State private var exportError: String?
    @State private var pendingJumpTime: TimeInterval?
    @State private var showTrimSheet = false
    @State private var isTrimming = false
    @State private var trimError: String?
    @State private var trimBackupTick: Int = 0

    @StateObject private var find = FindController()
    @FocusState private var findFieldFocused: Bool
    @State private var findDebounce: DispatchWorkItem?

    var onStop: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Compact recording bar — shown when recording AND viewing a different session
            if recordingManager.isRecording,
               selectedSessionID != recordingManager.activeSessionID {
                CompactRecordingBar(
                    onStop: { onStop?() },
                    onTapBar: { selectedSessionID = recordingManager.activeSessionID }
                )
                Divider()
            }

            // Main content
            if recordingManager.isRecording,
               selectedSessionID == nil || selectedSessionID == recordingManager.activeSessionID {
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
            audioPlayer.stop()
            find.close()
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab != .transcript {
                audioPlayer.pause()
            }
        }
    }

    // MARK: - Find (Cmd+F)

    /// Hidden zero-size button that gives the detail view a Cmd+F shortcut to open
    /// and focus the find bar. Scoped to `savedSessionView` so it's only live when a
    /// transcript/summary is on screen.
    private var findShortcutButton: some View {
        Button("") {
            find.open()
            findFieldFocused = true
        }
        .keyboardShortcut("f", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Recompute matches for the screen currently shown.
    private func recomputeFind(transcript: Transcript, summary: Summary?) {
        let elements: [FindElement]
        switch activeTab {
        case .transcript:
            elements = FindIndexBuilder.elements(forTranscript: transcript)
        case .summary:
            elements = summary.map { FindIndexBuilder.elements(forSummary: $0) } ?? []
        }
        find.recompute(elements: elements)
    }

    /// Debounced recompute used while the user is typing (~150 ms).
    private func scheduleFindRecompute(transcript: Transcript, summary: Summary?) {
        findDebounce?.cancel()
        let work = DispatchWorkItem { recomputeFind(transcript: transcript, summary: summary) }
        findDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
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

                    if activeTab == .summary {
                        exportMenu(summary: loadedSummary, entry: entry, transcript: transcript)
                    }

                    let isImported = transcript.source == .imported
                    let canTrim = activeTab == .transcript && !isImported && audioURL(for: sessionID) != nil
                    if canTrim {
                        Button {
                            showTrimSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "scissors")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Trim")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color(.controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain).pointerHand()
                        .disabled(summarizationEngine.isWorking || recordingManager.isPipelineRunning || recordingManager.isRecording || isTrimming)
                        .opacity(summarizationEngine.isWorking || recordingManager.isPipelineRunning || recordingManager.isRecording || isTrimming ? 0.5 : 1)
                    }

                    if !(activeTab == .transcript && isImported) {
                    Button {
                        if activeTab == .transcript {
                            showRetranscribeConfirm = true
                        } else {
                            showRegenerateConfirm = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: activeTab == .transcript ? "waveform" : "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text(activeTab == .transcript ? "Re-transcribe" : "Regenerate")
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
                    .buttonStyle(.plain).pointerHand()
                    .disabled(summarizationEngine.isWorking || recordingManager.isPipelineRunning || recordingManager.isRecording)
                    .opacity(summarizationEngine.isWorking || recordingManager.isPipelineRunning || recordingManager.isRecording ? 0.5 : 1)
                    } // end Re-transcribe gate
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                Divider()

                // Content — scroll area spans full width, content centered inside
                ZStack(alignment: .top) {
                    switch activeTab {
                    case .transcript:
                        TranscriptView(
                            transcript: transcript,
                            entry: entry,
                            loadedSummary: loadedSummary,
                            audioURL: audioURL(for: sessionID),
                            hasOriginalAudio: { _ = trimBackupTick; return sessionStore.hasOriginalAudio(for: sessionID) }(),
                            onDeleteOriginalAudio: {
                                sessionStore.deleteOriginalAudio(for: sessionID)
                                trimBackupTick &+= 1
                            },
                            jumpToTime: $pendingJumpTime,
                            onEdit: { updated in
                                sessionStore.saveEditedTranscript(updated, forSessionID: sessionID)
                            },
                            find: find
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .summary:
                        SummaryView(
                            summary: loadedSummary,
                            streamingText: summarizingSessionID == sessionID ? summarizationEngine.streamingText : "",
                            isLoading: summarizingSessionID == sessionID && summarizationEngine.isWorking,
                            statusMessage: summarizationEngine.statusMessage,
                            entry: entry,
                            transcript: transcript,
                            onRegenerate: nil,
                            onCancel: {
                                summarizationEngine.cancel()
                            },
                            onJumpToTime: { time in
                                activeTab = .transcript
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    pendingJumpTime = time
                                }
                            },
                            onRegenerateAfterEdit: {
                                showRegenerateConfirm = true
                            },
                            find: find
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if find.isActive {
                        FindBar(
                            find: find,
                            focused: $findFieldFocused,
                            onNext: { find.next() },
                            onPrevious: { find.previous() },
                            onClose: {
                                find.close()
                                findFieldFocused = false
                            }
                        )
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .background(findShortcutButton)
                .onChange(of: find.query) {
                    scheduleFindRecompute(transcript: transcript, summary: loadedSummary)
                }
                .onChange(of: activeTab) {
                    recomputeFind(transcript: transcript, summary: loadedSummary)
                }
                .onChange(of: find.isActive) {
                    if find.isActive {
                        recomputeFind(transcript: transcript, summary: loadedSummary)
                    }
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
                        if sessionStore.audioPath(for: sessionID) != nil,
                           let entry = sessionStore.sessions.first(where: { $0.id == sessionID }) {
                            Button("Transcribe Now") {
                                recordingManager.runPipeline(
                                    for: entry,
                                    sessionStore: sessionStore,
                                    transcriptionEngine: transcriptionEngine,
                                    diarizationManager: diarizationManager,
                                    summarizationEngine: summarizationEngine
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(recordingManager.isPipelineRunning || recordingManager.isRecording)
                        }
                    }
                    Spacer()
                }
            }
        }
        .overlay {
            if showRegenerateConfirm,
               let transcript = sessionStore.loadTranscript(for: sessionID) {
                let registry = ProviderRegistry.shared
                RegenerateConfirmModal(
                    sessionName: sessionStore.sessions.first { $0.id == sessionID }?.name ?? "Session",
                    currentProviderID: registry.defaults.summarizationProviderID,
                    currentModelID: registry.defaults.summarizationModelID,
                    onConfirm: { providerID, modelID, setAsDefault in
                        showRegenerateConfirm = false
                        if setAsDefault {
                            registry.defaults.summarizationProviderID = providerID
                            registry.defaults.summarizationModelID = modelID
                        }
                        if activeTab != .summary { activeTab = .summary }
                        summarizationEngine.currentSummary = nil
                        summarizingSessionID = sessionID

                        if providerID == .localMLX {
                            summarizationEngine.startSummarization(
                                transcript: transcript,
                                transcriptionEngine: transcriptionEngine
                            ) { [self] summary in
                                if let summary {
                                    sessionStore.saveSummary(summary, for: sessionID)
                                }
                                summarizingSessionID = nil
                            }
                        } else {
                            Task {
                                let provider = makeSummarizationProvider(providerID)
                                let userPrompt = SummaryPromptBuilder.buildUserPrompt(transcript: transcript)
                                do {
                                    let summary = try await provider.summarize(
                                        transcript: transcript,
                                        modelID: modelID,
                                        systemPrompt: SummaryPromptBuilder.systemPrompt,
                                        userPrompt: userPrompt,
                                        stream: { text in
                                            Task { @MainActor in
                                                summarizationEngine.streamingText = text
                                            }
                                        }
                                    )
                                    sessionStore.saveSummary(summary, for: sessionID)
                                    summarizationEngine.currentSummary = summary
                                } catch {
                                    summarizationEngine.streamingText = "Error: \(error.localizedDescription)"
                                }
                                summarizingSessionID = nil
                            }
                        }
                    },
                    onClose: { showRegenerateConfirm = false }
                )
            }

            if showTrimSheet,
               let url = audioURL(for: sessionID),
               let entry = sessionStore.sessions.first(where: { $0.id == sessionID }),
               let duration = entry.durationSeconds, duration > 0 {
                TrimSelectionView(
                    sessionName: entry.name,
                    audioURL: url,
                    totalDuration: duration,
                    onConfirm: { startSec, endSec in
                        showTrimSheet = false
                        performTrim(
                            sessionID: sessionID,
                            sourceURL: url,
                            startSeconds: startSec,
                            endSeconds: endSec
                        )
                    },
                    onClose: { showTrimSheet = false }
                )
            }

            if isTrimming {
                ZStack {
                    Color.black.opacity(0.32).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Trimming audio…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(Color(.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                }
            }

            if showRetranscribeConfirm {
                let registry = ProviderRegistry.shared
                RetranscribeConfirmModal(
                    sessionName: sessionStore.sessions.first { $0.id == sessionID }?.name ?? "Session",
                    currentProviderID: registry.defaults.transcriptionProviderID,
                    currentModelID: registry.defaults.transcriptionModelID,
                    onConfirm: { providerID, modelID, setAsDefault in
                        showRetranscribeConfirm = false
                        if setAsDefault {
                            registry.defaults.transcriptionProviderID = providerID
                            registry.defaults.transcriptionModelID = modelID
                        }
                        // Re-run the pipeline for this session
                        if let entry = sessionStore.sessions.first(where: { $0.id == sessionID }) {
                            recordingManager.runPipeline(
                                for: entry,
                                sessionStore: sessionStore,
                                transcriptionEngine: transcriptionEngine,
                                diarizationManager: diarizationManager,
                                summarizationEngine: summarizationEngine
                            )
                        }
                    },
                    onClose: { showRetranscribeConfirm = false }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if copiedAt != nil {
                copiedToast
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: copiedAt)
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedAt = nil
        }
        .alert("Export failed",
               isPresented: Binding(get: { exportError != nil },
                                    set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Trim failed",
               isPresented: Binding(get: { trimError != nil },
                                    set: { if !$0 { trimError = nil } })) {
            Button("OK", role: .cancel) { trimError = nil }
        } message: {
            Text(trimError ?? "")
        }
    }

    // MARK: - Trim

    private func performTrim(sessionID: String, sourceURL: URL, startSeconds: Double, endSeconds: Double) {
        isTrimming = true
        audioPlayer.stop()
        let trimStartedAt = Date()

        Task {
            // 1. Back up the current audio so we can restore if the pipeline fails.
            do {
                try sessionStore.backupAudio(for: sessionID)
            } catch {
                isTrimming = false
                trimError = "Couldn't back up the original audio: \(error.localizedDescription)"
                return
            }

            // 2. Re-encode the trimmed range over audio.m4a.
            do {
                try await AudioTrimmer.trim(
                    sourceURL: sourceURL,
                    destinationURL: sourceURL,
                    startSeconds: startSeconds,
                    endSeconds: endSeconds
                )
            } catch {
                // Restore the backup so the original audio is still intact.
                try? sessionStore.restoreOriginalAudio(for: sessionID)
                isTrimming = false
                trimError = "Couldn't trim the audio: \(error.localizedDescription)"
                return
            }

            // 3. Persist the new duration so the rest of the pipeline sees it.
            let newDuration = max(0, endSeconds - startSeconds)
            sessionStore.updateDuration(newDuration, for: sessionID)

            isTrimming = false

            // 4. Re-run the post-recording pipeline. The pipeline UI takes over.
            guard let entry = sessionStore.sessions.first(where: { $0.id == sessionID }) else { return }
            recordingManager.runPipeline(
                for: entry,
                sessionStore: sessionStore,
                transcriptionEngine: transcriptionEngine,
                diarizationManager: diarizationManager,
                summarizationEngine: summarizationEngine
            )

            // 5. Wait for the pipeline to finish, then verify a fresh transcript
            //    was produced. If not, restore the backup so the user keeps the
            //    pre-trim audio + transcript intact.
            await recordingManager.waitForPipeline()
            if let updated = sessionStore.loadTranscript(for: sessionID),
               updated.created >= trimStartedAt {
                // Success — leave audio.original.m4a in place. The Transcript
                // page surfaces a "Delete original audio" button while it
                // exists.
                trimBackupTick &+= 1
            } else {
                try? sessionStore.restoreOriginalAudio(for: sessionID)
                sessionStore.updateDuration(await AudioTrimmer.duration(of: sourceURL), for: sessionID)
                trimBackupTick &+= 1
                trimError = "Trim finished, but regenerating the transcript failed. The original audio has been restored."
            }
        }
    }

    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Copied to clipboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)
    }

    // MARK: - Export Menu

    @ViewBuilder
    private func exportMenu(summary: Summary?,
                            entry: SessionIndex.SessionEntry?,
                            transcript: Transcript?) -> some View {
        Menu {
            Button {
                guard let summary else { return }
                SummaryExporter.copyToPasteboard(summary: summary, entry: entry, transcript: transcript)
                copiedAt = Date()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                runExport(.doc, summary: summary, entry: entry, transcript: transcript)
            } label: {
                Label("Word Document", systemImage: "doc.richtext")
            }
            Button {
                runExport(.pdf, summary: summary, entry: entry, transcript: transcript)
            } label: {
                Label("PDF", systemImage: "doc.fill")
            }
            Button {
                runExport(.plainText, summary: summary, entry: entry, transcript: transcript)
            } label: {
                Label("Plain Text", systemImage: "doc.plaintext")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(summary == nil)
        .help(summary == nil ? "Generate a summary first" : "Export or copy summary")
    }

    private func runExport(_ format: SummaryExporter.Format,
                           summary: Summary?,
                           entry: SessionIndex.SessionEntry?,
                           transcript: Transcript?) {
        guard let summary else { return }
        do {
            try SummaryExporter.export(summary: summary, entry: entry, transcript: transcript, format: format)
        } catch SummaryExporter.ExportError.cancelled {
            // User dismissed the save panel — silent no-op
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func makeSummarizationProvider(_ id: ProviderID) -> any SummarizationProvider {
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

    // MARK: - Audio URL

    private func audioURL(for sessionID: String) -> URL? {
        guard let path = sessionStore.audioPath(for: sessionID),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
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
