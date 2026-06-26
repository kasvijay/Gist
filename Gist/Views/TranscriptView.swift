import SwiftUI

struct TranscriptView: View {
    var transcript: Transcript
    var entry: SessionIndex.SessionEntry? = nil
    var loadedSummary: Summary? = nil
    var audioURL: URL? = nil
    var hasOriginalAudio: Bool = false
    var onDeleteOriginalAudio: (() -> Void)? = nil
    @Binding var jumpToTime: TimeInterval?
    var onEdit: ((Transcript) -> Void)? = nil
    @ObservedObject var find: FindController

    init(transcript: Transcript,
         entry: SessionIndex.SessionEntry? = nil,
         loadedSummary: Summary? = nil,
         audioURL: URL? = nil,
         hasOriginalAudio: Bool = false,
         onDeleteOriginalAudio: (() -> Void)? = nil,
         jumpToTime: Binding<TimeInterval?> = .constant(nil),
         onEdit: ((Transcript) -> Void)? = nil,
         find: FindController) {
        self.transcript = transcript
        self.entry = entry
        self.loadedSummary = loadedSummary
        self.audioURL = audioURL
        self.hasOriginalAudio = hasOriginalAudio
        self.onDeleteOriginalAudio = onDeleteOriginalAudio
        self._jumpToTime = jumpToTime
        self.onEdit = onEdit
        self.find = find
    }

    @State private var confirmDeleteOriginal = false

    @EnvironmentObject var audioPlayer: AudioPlayerService
    @State private var draftSegments: [Transcript.Segment] = []
    @State private var hasInitializedDraft = false

    private let speakerColorPalette: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .brown, .teal]

    private func colorForSpeaker(_ id: String) -> Color {
        if let idx = Int(id.replacingOccurrences(of: "SPEAKER_", with: "")),
           idx < speakerColorPalette.count {
            return speakerColorPalette[idx]
        }
        return .secondary
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Session header (inside scroll area for full-width scrolling)
                if let entry {
                    sessionHeader
                        .padding(.bottom, 12)
                }

                // Waveform player strip — recorded sessions only
                if transcript.source == .recorded, audioURL != nil {
                    WaveformStripView()
                        .padding(.bottom, 14)
                }

                if hasOriginalAudio {
                    originalAudioBanner
                        .padding(.bottom, 14)
                }

                ForEach(currentSegments.indices, id: \.self) { idx in
                    segmentRow(idx)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if let url = audioURL { audioPlayer.load(url: url) }
            ensureDraftInitialized()
        }
        .onChange(of: audioURL) { _, newURL in
            if let url = newURL { audioPlayer.load(url: url) }
        }
        .onChange(of: jumpToTime) { _, newValue in
            guard let target = newValue else { return }
            performJump(to: target, scrollProxy: proxy)
            jumpToTime = nil
        }
        .onChange(of: find.scrollNonce) {
            guard let anchor = find.currentMatch?.anchor, let id = anchor.base as? UUID else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
        }
    }

    /// Seek the audio player to `target`, ensure playback is running, and scroll
    /// the matching transcript segment into view. For imported sessions (no
    /// audio file), only the scroll happens.
    private func performJump(to target: TimeInterval, scrollProxy: ScrollViewProxy) {
        let isImported = transcript.source == .imported || audioURL == nil
        if !isImported {
            audioPlayer.load(url: audioURL!)
            audioPlayer.seek(toTime: target)
            if !audioPlayer.isPlaying { audioPlayer.togglePlayback() }
        }
        if let segment = nearestSegment(to: target) {
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(segment.id, anchor: .center)
            }
        }
    }

    // MARK: - Per-segment rendering

    private var currentSegments: [Transcript.Segment] {
        transcript.source == .imported && hasInitializedDraft ? draftSegments : transcript.segments
    }

    @ViewBuilder
    private func segmentRow(_ idx: Int) -> some View {
        let segment = currentSegments[idx]
        let isImported = transcript.source == .imported

        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(isActiveSegment(segment) ? Color.accentColor : Color.clear)
                .frame(width: 2)
                .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 12) {
                if segment.start > 0 || !isImported {
                    Text(formatTimestamp(segment.start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                        .onTapGesture {
                            if !isImported {
                                audioPlayer.seek(toTime: TimeInterval(segment.start))
                                if !audioPlayer.isPlaying { audioPlayer.togglePlayback() }
                            }
                        }
                        .pointerHand()
                } else {
                    Color.clear.frame(width: 50)
                }

                VStack(alignment: .leading, spacing: 2) {
                    speakerLabelView(for: segment, idx: idx, isImported: isImported)
                    if isImported {
                        TextField("Segment text", text: editableTextBinding(for: idx), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .onSubmit { commitDraft() }
                    } else {
                        Text(FindHighlighter.attributed(
                            segment.text,
                            query: find.query,
                            currentOccurrence: find.currentOccurrence(forAnchor: segment.id)
                        ))
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 8)
        }
        .id(segment.id)
    }

    @ViewBuilder
    private func speakerLabelView(for segment: Transcript.Segment, idx: Int, isImported: Bool) -> some View {
        if isImported {
            TextField("Speaker", text: editableSpeakerBinding(for: idx))
                .textFieldStyle(.plain)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(segment.speaker.flatMap { colorForSpeaker($0) } ?? .secondary)
                .onSubmit { commitDraft() }
        } else if let speakerID = segment.speaker,
                  let speaker = transcript.speakers?[speakerID] {
            Text(speaker.label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(colorForSpeaker(speakerID))
        }
    }

    private func ensureDraftInitialized() {
        guard !hasInitializedDraft, transcript.source == .imported else { return }
        draftSegments = transcript.segments
        hasInitializedDraft = true
    }

    private func editableTextBinding(for idx: Int) -> Binding<String> {
        Binding(
            get: {
                draftSegments.indices.contains(idx) ? draftSegments[idx].text : ""
            },
            set: { newValue in
                if draftSegments.indices.contains(idx), draftSegments[idx].text != newValue {
                    draftSegments[idx].text = newValue
                    scheduleCommit()
                }
            }
        )
    }

    private func editableSpeakerBinding(for idx: Int) -> Binding<String> {
        Binding(
            get: {
                draftSegments.indices.contains(idx) ? (draftSegments[idx].speaker ?? "") : ""
            },
            set: { newValue in
                guard draftSegments.indices.contains(idx) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let next: String? = trimmed.isEmpty ? nil : trimmed
                if draftSegments[idx].speaker != next {
                    draftSegments[idx].speaker = next
                    scheduleCommit()
                }
            }
        )
    }

    @State private var commitWorkItem: DispatchWorkItem?

    private func scheduleCommit() {
        commitWorkItem?.cancel()
        let work = DispatchWorkItem { commitDraft() }
        commitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func commitDraft() {
        guard hasInitializedDraft else { return }
        var updated = transcript
        updated.segments = draftSegments
        updated.editedAt = Date()
        onEdit?(updated)
    }

    private func nearestSegment(to target: TimeInterval) -> Transcript.Segment? {
        let t = Float(target)
        var best: Transcript.Segment?
        for segment in transcript.segments {
            if segment.start <= t {
                best = segment
            } else {
                break
            }
        }
        return best ?? transcript.segments.first
    }

    private func isActiveSegment(_ segment: Transcript.Segment) -> Bool {
        guard audioPlayer.isPlaying || audioPlayer.currentTime > 0 else { return false }
        let time = Float(audioPlayer.currentTime)
        return time >= segment.start && time < segment.end
    }

    @ViewBuilder
    private var sessionHeader: some View {
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

            HStack(spacing: 16) {
                if let duration = entry?.durationSeconds {
                    Label(formatDuration(duration), systemImage: "clock")
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var originalAudioBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pre-trim audio kept as backup")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Delete it once you're sure the new transcript looks right.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                confirmDeleteOriginal = true
            } label: {
                Text("Delete original")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain).pointerHand()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
        .alert("Delete the original audio?",
               isPresented: $confirmDeleteOriginal) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDeleteOriginalAudio?() }
        } message: {
            Text("This permanently removes the pre-trim recording. The trimmed audio and the new transcript stay intact.")
        }
    }

    private func formatTimestamp(_ seconds: Float) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
