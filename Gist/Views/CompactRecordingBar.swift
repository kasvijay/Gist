import SwiftUI

struct CompactRecordingBar: View {
    @EnvironmentObject var recordingManager: RecordingManager

    var onStop: () -> Void
    var onTapBar: () -> Void

    private let accentRed = Color(red: 220/255, green: 80/255, blue: 60/255)
    private let accentRedDark = Color(red: 190/255, green: 60/255, blue: 45/255)

    var body: some View {
        HStack(spacing: 12) {
            // Recording / Paused badge
            HStack(spacing: 6) {
                Circle()
                    .fill(recordingManager.isPaused ? Color.orange : accentRed)
                    .frame(width: 6, height: 6)
                Text(recordingManager.isPaused ? "PAUSED" : "RECORDING")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
            }
            .foregroundStyle(recordingManager.isPaused ? .orange : accentRed)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((recordingManager.isPaused ? Color.orange : accentRed).opacity(0.1))
            )

            // Timer
            Text(formatTime(recordingManager.elapsedTime))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)

            // Mini waveform
            AudioWaveformView(
                micLevel: recordingManager.micLevel,
                systemLevel: recordingManager.systemLevel,
                isPaused: recordingManager.isPaused
            )
            .frame(width: 100, height: 22)

            Spacer()

            // Mic mute toggle
            Button {
                recordingManager.toggleMicMute()
            } label: {
                Image(systemName: recordingManager.isMicMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(recordingManager.isMicMuted ? .red : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(.separatorColor), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            // Pause / Resume
            Button {
                if recordingManager.isPaused {
                    recordingManager.resumeRecording()
                } else {
                    recordingManager.pauseRecording()
                }
            } label: {
                Image(systemName: recordingManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(.separatorColor), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            // Stop button
            Button {
                onStop()
            } label: {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 8, height: 8)
                    Text("Stop")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [accentRed, accentRedDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(accentRed.opacity(0.05))
        .contentShape(Rectangle())
        .onTapGesture {
            onTapBar()
        }
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
