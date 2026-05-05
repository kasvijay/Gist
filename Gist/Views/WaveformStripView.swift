import SwiftUI

struct WaveformStripView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerService

    private let barCount = 120
    private let accentBlue = Color(red: 75/255, green: 123/255, blue: 217/255)

    private var barHeights: [CGFloat] {
        (0..<barCount).map { i in
            let fi = CGFloat(i)
            let v = (sin(fi * 0.37) + cos(fi * 0.91) + sin(fi * 0.13)) / 3
            return 0.25 + abs(v) * 0.75
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button {
                audioPlayer.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(accentBlue)
                        .frame(width: 32, height: 32)
                        .shadow(color: accentBlue.opacity(0.35), radius: 3, y: 2)
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: audioPlayer.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)

            // Waveform bars
            GeometryReader { geo in
                Canvas { context, size in
                    let heights = barHeights
                    let totalGap = CGFloat(barCount - 1) * 1.5
                    let barWidth = max((size.width - totalGap) / CGFloat(barCount), 1)
                    let playedIndex = Int(audioPlayer.progress * Double(barCount))

                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barWidth + 1.5)
                        let h = heights[i] * size.height
                        let y = (size.height - h) / 2
                        let rect = CGRect(x: x, y: y, width: barWidth, height: max(h, 2))
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        let color = i < playedIndex ? accentBlue : Color.primary.opacity(0.15)
                        context.fill(path, with: .color(color))
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let fraction = value.location.x / geo.size.width
                            audioPlayer.seek(to: fraction)
                            if !audioPlayer.isPlaying {
                                audioPlayer.togglePlayback()
                            }
                        }
                )
                .contentShape(Rectangle())
            }
            .frame(height: 28)

            // Time label
            HStack(spacing: 0) {
                Text(formatTime(audioPlayer.currentTime))
                    .foregroundStyle(.primary)
                Text(" / \(formatTime(audioPlayer.duration))")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.primary.opacity(0.03), radius: 1, y: 1)
        )
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
