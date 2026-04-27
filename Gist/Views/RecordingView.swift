import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var recordingManager: RecordingManager

    var onStop: () -> Void

    private let accentRed = Color(red: 220/255, green: 80/255, blue: 60/255)
    private let accentRedDark = Color(red: 190/255, green: 60/255, blue: 45/255)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()

                // Recording / Paused badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(recordingManager.isPaused ? Color.orange : accentRed)
                        .frame(width: 8, height: 8)
                        .opacity(recordingManager.isPaused ? 1 : 0.8)
                    Text(recordingManager.isPaused ? "PAUSED" : "RECORDING")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundStyle(recordingManager.isPaused ? .orange : accentRed)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((recordingManager.isPaused ? Color.orange : accentRed).opacity(0.1))
                )

                // Large timer
                Text(formatTime(recordingManager.elapsedTime))
                    .font(.system(size: 72, weight: .light, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.top, 28)

                // Waveform
                AudioWaveformView(
                    micLevel: recordingManager.micLevel,
                    systemLevel: recordingManager.systemLevel,
                    isPaused: recordingManager.isPaused
                )
                .frame(width: 320, height: 80)
                .padding(.top, 36)

                // Description text
                Group {
                    if recordingManager.isMicMuted {
                        Text("Capturing system audio only. Microphone is muted.")
                    } else {
                        Text("Capturing system audio and microphone.\nGist will transcribe and summarize when you stop.")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 44)

                // Control buttons
                HStack(spacing: 10) {
                    // Stop & summarize
                    Button {
                        onStop()
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white)
                                .frame(width: 10, height: 10)
                            Text("Stop & summarize")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [accentRed, accentRedDark],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: accentRed.opacity(0.4), radius: 8, y: 6)
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
                        Text(recordingManager.isPaused ? "Resume" : "Pause")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(.separatorColor), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 32)

                // Mic mute button
                Button {
                    recordingManager.toggleMicMute()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: recordingManager.isMicMuted ? "mic.slash.fill" : "mic.fill")
                        Text(recordingManager.isMicMuted ? "Unmute Mic" : "Mute Mic")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(recordingManager.isMicMuted ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                // Input levels card
                HStack(spacing: 0) {
                    // Mic input with mute toggle
                    Button {
                        recordingManager.toggleMicMute()
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MIC")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .tracking(1)
                                Text(recordingManager.isMicMuted ? "Muted" : recordingManager.micDeviceName)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(recordingManager.isMicMuted ? .red : .primary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            LevelIndicator(
                                level: recordingManager.isMicMuted ? 0 : recordingManager.micLevel,
                                color: recordingManager.isMicMuted ? .red : .blue
                            )
                            .frame(width: 80)
                            Image(systemName: recordingManager.isMicMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(recordingManager.isMicMuted ? .red : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 36)
                        .padding(.horizontal, 14)

                    // System audio
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SYSTEM")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(1)
                            Text("System Audio")
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                        }
                        Spacer()
                        LevelIndicator(level: recordingManager.systemLevel, color: .green)
                            .frame(width: 80)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 48)
                .padding(.top, 48)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
