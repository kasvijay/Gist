import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var diarizationManager: DiarizationManager
    @EnvironmentObject var summarizationEngine: SummarizationEngine

    @Binding var selectedSessionID: String?
    @State private var renamingSessionID: String?
    @State private var renameText: String = ""
    @State private var searchText: String = ""
    @FocusState private var renameFieldFocused: Bool

    private var filteredSessions: [SessionIndex.SessionEntry] {
        if searchText.isEmpty {
            return sessionStore.sessions
        }
        return sessionStore.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedSessions: [(String, [SessionIndex.SessionEntry])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        var pinned: [SessionIndex.SessionEntry] = []
        var todaySessions: [SessionIndex.SessionEntry] = []
        var yesterdaySessions: [SessionIndex.SessionEntry] = []
        var earlier: [SessionIndex.SessionEntry] = []

        for session in filteredSessions {
            if session.isPinned == true {
                pinned.append(session)
            } else if calendar.isDate(session.startedAt, inSameDayAs: today) {
                todaySessions.append(session)
            } else if calendar.isDate(session.startedAt, inSameDayAs: yesterday) {
                yesterdaySessions.append(session)
            } else {
                earlier.append(session)
            }
        }

        var groups: [(String, [SessionIndex.SessionEntry])] = []
        if !pinned.isEmpty { groups.append(("PINNED", pinned)) }
        if !todaySessions.isEmpty { groups.append(("TODAY", todaySessions)) }
        if !yesterdaySessions.isEmpty { groups.append(("YESTERDAY", yesterdaySessions)) }
        if !earlier.isEmpty { groups.append(("EARLIER", earlier)) }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            // Recording button — toggles between New recording / Stop recording
            if recordingManager.isRecording {
                Button {
                    _ = recordingManager.stopRecording(
                        sessionStore: sessionStore,
                        transcriptionEngine: transcriptionEngine,
                        diarizationManager: diarizationManager,
                        summarizationEngine: summarizationEngine
                    )
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(width: 10, height: 10)
                        Text("Stop recording")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        // Pulsing timer badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.white)
                                .frame(width: 6, height: 6)
                                .opacity(0.8)
                            Text(formatTime(recordingManager.elapsedTime))
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.22))
                        )
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 220/255, green: 80/255, blue: 60/255),
                                        Color(red: 190/255, green: 60/255, blue: 45/255)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color(red: 220/255, green: 80/255, blue: 60/255).opacity(0.35), radius: 6, y: 4)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            } else {
                Button {
                    recordingManager.startRecording(
                        sessionStore: sessionStore,
                        transcriptionEngine: transcriptionEngine,
                        diarizationManager: diarizationManager
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mic")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(.white.opacity(0.2))
                            )
                        Text("New recording")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\u{2318}R")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(0.18))
                            )
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 88/255, green: 132/255, blue: 210/255),
                                        Color(red: 68/255, green: 110/255, blue: 190/255)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color(red: 88/255, green: 132/255, blue: 210/255).opacity(0.3), radius: 6, y: 4)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(recordingManager.isStarting || recordingManager.isPipelineRunning || transcriptionEngine.state != .ready)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }

            List(selection: $selectedSessionID) {
                // Grouped sessions
                ForEach(groupedSessions, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { session in
                            sessionRow(session)
                                .tag(session.id)
                                .contextMenu { contextMenu(for: session) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search sessions...")
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Import Audio...") {
                        importAudio()
                    }
                    Button("Open Folder in Finder") {
                        NSWorkspace.shared.open(sessionStore.baseURL)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Row

    private func sessionRow(_ session: SessionIndex.SessionEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if renamingSessionID == session.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($renameFieldFocused)
                    .onSubmit {
                        sessionStore.renameSession(id: session.id, newName: renameText)
                        renamingSessionID = nil
                    }
                    .onExitCommand {
                        renamingSessionID = nil
                    }
            } else {
                HStack {
                    Text(session.name)
                        .font(.body)
                        .lineLimit(1)
                    if session.isPinned == true {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 6) {
                if recordingManager.processingSessionID == session.id {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Processing…")
                } else {
                    Text(session.startedAt, format: .dateTime.hour().minute())
                    if let duration = session.durationSeconds {
                        Text("·")
                        Text(formatTime(duration))
                            .monospacedDigit()
                    }
                    if let count = session.segmentCount, count > 0 {
                        Text("·")
                        Image(systemName: "text.alignleft")
                        Text("\(count)")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for session: SessionIndex.SessionEntry) -> some View {
        if session.isPinned == true {
            Button("Unpin") {
                sessionStore.unpinSession(id: session.id)
            }
        } else {
            Button("Pin") {
                sessionStore.pinSession(id: session.id)
            }
        }
        Button("Rename") {
            renameText = session.name
            renamingSessionID = session.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                renameFieldFocused = true
            }
        }
        Button("Re-transcribe") {
            retranscribe(session)
        }
        Divider()
        Button("Open in Finder") {
            let url = sessionStore.baseURL.appendingPathComponent(session.path)
            NSWorkspace.shared.open(url)
        }
        Divider()
        Button("Delete", role: .destructive) {
            sessionStore.deleteSession(id: session.id)
            if selectedSessionID == session.id {
                selectedSessionID = nil
            }
        }
    }

    // MARK: - Actions

    private func retranscribe(_ session: SessionIndex.SessionEntry) {
        guard let audioPath = sessionStore.audioPath(for: session.id) else { return }
        let audioURL = URL(fileURLWithPath: audioPath)
        Task.detached {
            if await !transcriptionEngine.isModelLoaded {
                await transcriptionEngine.loadModel()
            }
            if var transcript = await transcriptionEngine.transcribe(
                audioPath: audioPath,
                duration: session.durationSeconds ?? 0
            ) {
                if await diarizationManager.method == .vbx {
                    await diarizationManager.applySpeakerLabelsAsync(to: &transcript, audioFileURL: audioURL)
                } else {
                    await diarizationManager.applySpeakerLabels(to: &transcript, audioFileURL: audioURL)
                }

                let s = Session(
                    id: session.id,
                    name: session.name,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    durationSeconds: session.durationSeconds,
                    status: .complete
                )
                await sessionStore.saveTranscript(transcript, for: s)
            }
        }
    }

    private func importAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Select an audio file to transcribe"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task.detached {
            if let session = await sessionStore.importAudioFile(from: url) {
                if await !transcriptionEngine.isModelLoaded {
                    await transcriptionEngine.loadModel()
                }
                let audioPath = await sessionStore.audioFileURL(for: session).path
                if var transcript = await transcriptionEngine.transcribe(
                    audioPath: audioPath,
                    duration: session.durationSeconds ?? 0
                ) {
                    let audioURL = await sessionStore.audioFileURL(for: session)
                    if await diarizationManager.method == .vbx {
                        await diarizationManager.applySpeakerLabelsAsync(to: &transcript, audioFileURL: audioURL)
                    } else {
                        await diarizationManager.applySpeakerLabels(to: &transcript, audioFileURL: audioURL)
                    }
                    await sessionStore.saveTranscript(transcript, for: session)

                    if let summary = await summarizationEngine.summarize(transcript: transcript, transcriptionEngine: transcriptionEngine) {
                        await sessionStore.saveSummary(summary, for: session.id)
                    }
                }
                await MainActor.run { selectedSessionID = session.id }
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
