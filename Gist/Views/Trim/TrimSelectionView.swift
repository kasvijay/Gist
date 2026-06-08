import SwiftUI

/// Modal sheet that lets the user pick a [start, end] range on the recording's
/// waveform. On confirm, calls `onConfirm` with the chosen seconds.
struct TrimSelectionView: View {
    let sessionName: String
    let audioURL: URL
    let totalDuration: Double
    let onConfirm: (_ startSeconds: Double, _ endSeconds: Double) -> Void
    let onClose: () -> Void

    @State private var samples: [Float] = []
    @State private var loading = true
    @State private var startSeconds: Double = 0
    @State private var endSeconds: Double = 0
    @State private var dragging: Handle? = nil

    private enum Handle { case start, end }

    private let accentBlue = Color(red: 75/255, green: 123/255, blue: 217/255)
    private let trackHeight: CGFloat = 96
    private let handleWidth: CGFloat = 14
    private let minSelectionSeconds: Double = 1.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                header
                Divider()
                content
                Divider()
                footer
            }
            .frame(width: 640)
            .background(Color(.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 32, y: 16)
        }
        .task {
            startSeconds = 0
            endSeconds = totalDuration
            samples = (await WaveformSamples.extract(from: audioURL, bucketCount: 600)) ?? []
            loading = false
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentBlue.opacity(0.12))
                Image(systemName: "scissors")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentBlue)
            }
            .frame(width: 36, height: 36)

            Text("Trim audio")
                .font(.system(size: 22, weight: .semibold))

            Group {
                Text("Drag the handles to crop ") +
                Text(sessionName).fontWeight(.medium) +
                Text(". After trimming, the transcript and summary will regenerate.")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            waveformSelector
            timestampReadout
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") { onClose() }
                .buttonStyle(.bordered)
            Button {
                onConfirm(startSeconds, endSeconds)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Trim & Regenerate")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isSelectionValid || loading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Waveform Selector

    private var waveformSelector: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let startX = position(for: startSeconds, in: width)
            let endX = position(for: endSeconds, in: width)

            ZStack(alignment: .topLeading) {
                // Background fill
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                // Waveform bars (faded outside selection)
                if !samples.isEmpty {
                    waveformBars(width: width, startX: startX, endX: endX)
                } else if loading {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .frame(height: trackHeight)
                }

                // Selected region tint
                Rectangle()
                    .fill(accentBlue.opacity(0.08))
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)

                // Trim handles — z-order puts whichever is currently being
                // dragged on top so the user keeps "owning" it while close
                // to the other handle.
                if dragging == .end {
                    handle(at: startX, kind: .start, totalWidth: width)
                    handle(at: endX, kind: .end, totalWidth: width)
                } else {
                    handle(at: endX, kind: .end, totalWidth: width)
                    handle(at: startX, kind: .start, totalWidth: width)
                }
            }
            .frame(height: trackHeight)
            .coordinateSpace(name: Self.railCoordSpace)
        }
        .frame(height: trackHeight)
    }

    private static let railCoordSpace = "trim.rail"

    private func waveformBars(width: CGFloat, startX: CGFloat, endX: CGFloat) -> some View {
        Canvas { context, size in
            let bucketCount = samples.count
            guard bucketCount > 0 else { return }
            let barWidth: CGFloat = max(1, (size.width - CGFloat(bucketCount - 1) * 1.0) / CGFloat(bucketCount))
            let midY = size.height / 2
            for i in 0..<bucketCount {
                let x = CGFloat(i) * (barWidth + 1.0)
                // Minimum bar so silence is still visible, but tiny.
                let h = max(2, CGFloat(samples[i]) * (size.height * 0.85))
                let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                let inSelection = x + barWidth / 2 >= startX && x + barWidth / 2 <= endX
                let color: Color = inSelection
                    ? accentBlue
                    : Color.primary.opacity(0.18)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .frame(height: trackHeight)
    }

    private func handle(at x: CGFloat, kind: Handle, totalWidth: CGFloat) -> some View {
        // Use a full-width container so the handle's hit area can be expanded
        // around the visible knob without enlarging neighbours. `.position`
        // (not `.offset`) places the knob center at `x` in the rail's
        // coordinate space, which keeps the gesture readout stable while
        // dragging (offset moves the local coordinate space with the view,
        // which produces a feedback loop).
        let isActive = dragging == kind
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(accentBlue)
                .frame(width: handleWidth, height: trackHeight + 12)
                .shadow(color: accentBlue.opacity(isActive ? 0.55 : 0.4), radius: isActive ? 5 : 3, y: 1)
            VStack(spacing: 3) {
                Capsule().fill(Color.white.opacity(0.85)).frame(width: 2, height: 10)
                Capsule().fill(Color.white.opacity(0.85)).frame(width: 2, height: 10)
            }
            // Invisible padded hit target around the knob — 22px to each side
            // is comfortable without the two handles ever competing for the
            // same touch (they're capped from getting closer than minSelectionSeconds).
            Color.clear
                .frame(width: handleWidth + 44, height: trackHeight + 24)
                .contentShape(Rectangle())
        }
        .frame(width: handleWidth + 44, height: trackHeight + 24)
        .position(x: x, y: trackHeight / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.railCoordSpace))
                .onChanged { value in
                    dragging = kind
                    let clampedX = min(max(value.location.x, 0), totalWidth)
                    let proposed = seconds(forX: clampedX, in: totalWidth)
                    switch kind {
                    case .start:
                        startSeconds = max(0, min(proposed, endSeconds - minSelectionSeconds))
                    case .end:
                        endSeconds = min(totalDuration, max(proposed, startSeconds + minSelectionSeconds))
                    }
                }
                .onEnded { _ in dragging = nil }
        )
        .pointerHand()
    }

    // MARK: - Timestamps

    private var timestampReadout: some View {
        HStack(spacing: 24) {
            timeBlock(label: "START", value: startSeconds, accent: dragging == .start)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            timeBlock(label: "END", value: endSeconds, accent: dragging == .end)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("NEW LENGTH")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.08 * 10)
                    .foregroundStyle(.tertiary)
                Text(formatTime(max(0, endSeconds - startSeconds)))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("REMOVED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.08 * 10)
                    .foregroundStyle(.tertiary)
                Text(formatTime(max(0, totalDuration - (endSeconds - startSeconds))))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeBlock(label: String, value: Double, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.08 * 10)
                .foregroundStyle(.tertiary)
            Text(formatTime(value))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(accent ? accentBlue : .primary)
        }
    }

    // MARK: - Helpers

    private var isSelectionValid: Bool {
        totalDuration > 0 &&
        endSeconds - startSeconds >= minSelectionSeconds &&
        (startSeconds > 0.01 || endSeconds < totalDuration - 0.01)
    }

    private func position(for seconds: Double, in width: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(seconds / totalDuration) * width
    }

    private func seconds(forX x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * totalDuration
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

