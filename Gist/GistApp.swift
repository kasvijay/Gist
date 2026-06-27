import SwiftUI

@main
struct GistApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var transcriptionEngine = TranscriptionEngine()
    @StateObject private var diarizationManager = DiarizationManager()
    @StateObject private var summarizationEngine = SummarizationEngine()
    @StateObject private var audioPlayerService = AudioPlayerService()
    @StateObject private var providerRegistry = ProviderRegistry.shared
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedSetup {
                ContentView()
                    .environmentObject(sessionStore)
                    .environmentObject(recordingManager)
                    .environmentObject(transcriptionEngine)
                    .environmentObject(diarizationManager)
                    .environmentObject(summarizationEngine)
                    .environmentObject(audioPlayerService)
                    .environmentObject(providerRegistry)
                    .task {
                        // Convert any recovered WAV files to M4A in the background
                        let conversions = sessionStore.pendingRecoveryConversions
                        if !conversions.isEmpty {
                            await CrashRecovery.convertPendingRecoveries(conversions)
                        }

                        // Auto-process sessions that have audio but no transcript
                        let pending = sessionStore.sessionsNeedingProcessing()
                        for entry in pending {
                            recordingManager.runPipeline(
                                for: entry,
                                sessionStore: sessionStore,
                                transcriptionEngine: transcriptionEngine,
                                diarizationManager: diarizationManager,
                                summarizationEngine: summarizationEngine
                            )
                            await recordingManager.waitForPipeline()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        // Finalize recording on app quit so audio file is never lost
                        if recordingManager.isRecording {
                            _ = recordingManager.stopRecording(
                                sessionStore: sessionStore,
                                transcriptionEngine: transcriptionEngine,
                                diarizationManager: diarizationManager
                            )
                        }
                    }
            } else {
                WelcomeView(hasCompletedSetup: $hasCompletedSetup)
                    .environmentObject(transcriptionEngine)
            }
        }
        .defaultSize(width: 860, height: 720)
        // Size the window to the content's *minimum* size, not its ideal. Without
        // this, the WindowGroup's automatic resizability grows the window toward the
        // `maxHeight: .infinity` ideal of the recording/centered views — stretching
        // it taller than the screen and pushing the Stop button off-screen the moment
        // recording starts. contentMinSize keeps the window at a sane size the user
        // can still resize freely.
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(sessionStore)
                .environmentObject(recordingManager)
                .environmentObject(transcriptionEngine)
                .environmentObject(diarizationManager)
                .environmentObject(summarizationEngine)
                .environmentObject(audioPlayerService)
                .environmentObject(providerRegistry)
        } label: {
            if recordingManager.isRecording {
                Label {
                    Text(formatMenuBarTime(recordingManager.elapsedTime))
                } icon: {
                    Image(systemName: "record.circle.fill")
                }
            } else {
                Image("MenuBarIcon")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(transcriptionEngine)
                .environmentObject(diarizationManager)
                .environmentObject(summarizationEngine)
                .environmentObject(providerRegistry)
        }
    }

    private func formatMenuBarTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
