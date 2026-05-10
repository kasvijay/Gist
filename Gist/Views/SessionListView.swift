import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var diarizationManager: DiarizationManager
    @EnvironmentObject var summarizationEngine: SummarizationEngine

    @Binding var selectedSessionID: String?
    @Binding var showImportSheet: Bool
    @Binding var importInitialText: String
    @Binding var importInitialFilename: String
    @State private var renamingSessionID: String?
    @State private var renameText: String = ""
    @State private var searchText: String = ""
    @State private var collapsedSections: Set<String> = []
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
        // Older sessions grouped by start-of-day date
        var olderByDate: [Date: [SessionIndex.SessionEntry]] = [:]

        for session in filteredSessions {
            if session.isPinned == true {
                pinned.append(session)
            } else if calendar.isDate(session.startedAt, inSameDayAs: today) {
                todaySessions.append(session)
            } else if calendar.isDate(session.startedAt, inSameDayAs: yesterday) {
                yesterdaySessions.append(session)
            } else {
                let dayStart = calendar.startOfDay(for: session.startedAt)
                olderByDate[dayStart, default: []].append(session)
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        var groups: [(String, [SessionIndex.SessionEntry])] = []
        if !pinned.isEmpty { groups.append(("PINNED", pinned)) }
        if !todaySessions.isEmpty { groups.append(("TODAY", todaySessions)) }
        if !yesterdaySessions.isEmpty { groups.append(("YESTERDAY", yesterdaySessions)) }
        for day in olderByDate.keys.sorted(by: >) {
            let title = dateFormatter.string(from: day).uppercased()
            groups.append((title, olderByDate[day]!))
        }
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
                .buttonStyle(.plain).pointerHand()
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
                .buttonStyle(.plain).pointerHand()
                .keyboardShortcut("r", modifiers: .command)
                .disabled(recordingManager.isStarting)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }

            // Secondary action: import a transcript from Teams / Zoom / etc.
            Button {
                importInitialText = ""
                importInitialFilename = ""
                showImportSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                    Text("Import transcript")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerHand()
            .padding(.horizontal, 6)
            .padding(.bottom, 6)

            List(selection: $selectedSessionID) {
                ForEach(groupedSessions, id: \.0) { group in
                    Section(isExpanded: sectionExpanded(group.0)) {
                        ForEach(group.1) { session in
                            sessionRow(session)
                                .tag(session.id)
                                .contextMenu { contextMenu(for: session) }
                        }
                    } header: {
                        sectionHeader(title: group.0, count: group.1.count)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search sessions...")

            DefaultsBarView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Import Audio...") {
                        importAudio()
                    }
                    Button("Import Transcript...") {
                        importInitialText = ""
                        importInitialFilename = ""
                        showImportSheet = true
                    }
                    Divider()
                    Button("Open Folder in Finder") {
                        NSWorkspace.shared.open(sessionStore.baseURL)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionExpanded(_ title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(title) },
            set: { isExpanded in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        collapsedSections.remove(title)
                    } else {
                        collapsedSections.insert(title)
                    }
                }
            }
        )
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.6)
                .foregroundStyle(.primary.opacity(0.55))
            Spacer()
            if collapsedSections.contains(title) {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
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
                if recordingManager.activeSessionID == session.id, recordingManager.isRecording {
                    Circle()
                        .fill(Color(red: 220/255, green: 80/255, blue: 60/255))
                        .frame(width: 6, height: 6)
                    Text("Recording")
                    Text("·")
                    Text(formatTime(recordingManager.elapsedTime))
                        .monospacedDigit()
                } else if recordingManager.processingSessionID == session.id {
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
        recordingManager.runPipeline(
            for: session,
            sessionStore: sessionStore,
            transcriptionEngine: transcriptionEngine,
            diarizationManager: diarizationManager,
            summarizationEngine: summarizationEngine
        )
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
