import SwiftUI

struct TranscriptView: View {
    let transcript: Transcript
    var entry: SessionIndex.SessionEntry? = nil
    var loadedSummary: Summary? = nil

    private let speakerColorPalette: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .brown, .teal]

    private func colorForSpeaker(_ id: String) -> Color {
        if let idx = Int(id.replacingOccurrences(of: "SPEAKER_", with: "")),
           idx < speakerColorPalette.count {
            return speakerColorPalette[idx]
        }
        return .secondary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Session header (inside scroll area for full-width scrolling)
                if let entry {
                    sessionHeader
                        .padding(.bottom, 12)
                }

                ForEach(transcript.segments) { segment in
                    HStack(alignment: .top, spacing: 12) {
                        Text(formatTimestamp(segment.start))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()

                        VStack(alignment: .leading, spacing: 2) {
                            if let speakerID = segment.speaker,
                               let speaker = transcript.speakers?[speakerID] {
                                Text(speaker.label)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(colorForSpeaker(speakerID))
                            }
                            Text(segment.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
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
