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
            // New recording button
            Button {
                recordingManager.startRecording(
                    sessionStore: sessionStore,
                    transcriptionEngine: transcriptionEngine,
                    diarizationManager: diarizationManager
                )
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic")
                        .font(.system(size: 11))
                        .padding(5)
                        .background(
                            Circle()
                                .fill(Color(red: 88/255, green: 132/255, blue: 201/255))
                        )
                    Text("New recording")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\u{2318}R")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(red: 88/255, green: 132/255, blue: 201/255))
                        )
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 68/255, green: 120/255, blue: 210/255),
                                    Color(red: 48/255, green: 102/255, blue: 189/255),
                                    Color(red: 36/255, green: 85/255, blue: 168/255)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(recordingManager.isRecording || recordingManager.isStarting || recordingManager.isPipelineRunning || transcriptionEngine.state != .ready)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            List(selection: $selectedSessionID) {
                // Active recording at top
                if recordingManager.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recordingManager.isPaused ? "Paused" : "Recording...")
                                .font(.body)
                                .fontWeight(.medium)
                            Text(formatTime(recordingManager.elapsedTime))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.red.opacity(0.05))
                }

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
