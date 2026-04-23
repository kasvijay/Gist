import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var recordingManager: RecordingManager

    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Recording / Paused badge
            HStack(spacing: 6) {
                Circle()
                    .fill(recordingManager.isPaused ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)
                Text(recordingManager.isPaused ? "PAUSED" : "RECORDING")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(recordingManager.isPaused ? .orange : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (recordingManager.isPaused ? Color.orange : Color.red).opacity(0.1),
                in: Capsule()
            )
            .padding(.bottom, 24)

            // Large timer
            Text(formatTime(recordingManager.elapsedTime))
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.bottom, 16)

            // Waveform
            AudioWaveformView(
                micLevel: recordingManager.micLevel,
                systemLevel: recordingManager.systemLevel,
                isPaused: recordingManager.isPaused
            )
            .frame(width: 250)
            .padding(.bottom, 16)

            // Description text
            if recordingManager.isMicMuted {
                Text("Capturing system audio only. Microphone is muted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Capturing system audio and microphone. Gist will transcribe and summarize when you stop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Control buttons
            HStack(spacing: 16) {
                Button {
                    onStop()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                        Text("Stop & summarize")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    if recordingManager.isPaused {
                        recordingManager.resumeRecording()
                    } else {
                        recordingManager.pauseRecording()
                    }
                } label: {
                    Text(recordingManager.isPaused ? "Resume" : "Pause")
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 12)

            // Mic mute button
            Button {
                recordingManager.toggleMicMute()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: recordingManager.isMicMuted ? "mic.slash.fill" : "mic.fill")
                    Text(recordingManager.isMicMuted ? "Unmute Mic" : "Mute Mic")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(recordingManager.isMicMuted ? .red : .secondary)
            .padding(.bottom, 20)

            Divider()

            // Device info bar
            HStack(spacing: 0) {
                // Mic info
                VStack(alignment: .leading, spacing: 4) {
                    Text("MIC")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(recordingManager.micDeviceName)
                        .font(.caption)
                        .lineLimit(1)
                    LevelIndicator(level: recordingManager.isMicMuted ? 0 : recordingManager.micLevel, color: .blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 40)

                // System audio info
                VStack(alignment: .leading, spacing: 4) {
                    Text("SYSTEM")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("System Audio")
                        .font(.caption)
                        .lineLimit(1)
                    LevelIndicator(level: recordingManager.systemLevel, color: .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Simple horizontal level meter bar.
struct LevelIndicator: View {
    var level: Float
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * CGFloat(min(level * 6, 1.0))))
            }
        }
        .frame(height: 4)
    }
}
