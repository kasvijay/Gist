import SwiftUI

/// Animated audio waveform visualization for the recording view.
/// Bar heights are driven by sine waves modulated by the actual audio level.
struct AudioWaveformView: View {
    var micLevel: Float
    var systemLevel: Float
    var isPaused: Bool

    private let barCount = 40
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                let totalWidth = CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
                let startX = (size.width - totalWidth) / 2
                let maxHeight = size.height * 0.9
                let time = timeline.date.timeIntervalSinceReferenceDate
                let level = CGFloat(max(micLevel, systemLevel))
                let amplitude = max(0.08, min(Double(level) * 8, 1.0))

                for i in 0..<barCount {
                    let phase = Double(i) * 0.3
                    let wave1 = sin(time * 3.0 + phase) * 0.5 + 0.5
                    let wave2 = sin(time * 5.0 + phase * 1.3) * 0.3 + 0.5
                    let combined = (wave1 + wave2) / 2.0
                    let height = max(4, maxHeight * combined * amplitude)

                    let x = startX + CGFloat(i) * (barWidth + barSpacing)
                    let y = (size.height - height) / 2

                    let progress = Double(i) / Double(barCount - 1)
                    let color = Color(
                        red: 0.9 * (1 - progress) + 0.2 * progress,
                        green: 0.15 * (1 - progress) + 0.3 * progress,
                        blue: 0.2 * (1 - progress) + 0.85 * progress
                    )

                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    let path = RoundedRectangle(cornerRadius: barWidth / 2)
                        .path(in: rect)
                    context.fill(path, with: .color(color))
                }
            }
        }
        .frame(height: 60)
    }
}
