import SwiftUI

@main
struct GistApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var transcriptionEngine = TranscriptionEngine()
    @StateObject private var diarizationManager = DiarizationManager()
    @StateObject private var summarizationEngine = SummarizationEngine()
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
                    .task {
                        // Convert any recovered WAV files to M4A in the background
                        let conversions = sessionStore.pendingRecoveryConversions
                        if !conversions.isEmpty {
                            await CrashRecovery.convertPendingRecoveries(conversions)
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
        .defaultSize(width: 700, height: 500)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(sessionStore)
                .environmentObject(recordingManager)
                .environmentObject(transcriptionEngine)
                .environmentObject(diarizationManager)
                .environmentObject(summarizationEngine)
        } label: {
            if recordingManager.isRecording {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Image("MenuBarIcon")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(transcriptionEngine)
                .environmentObject(diarizationManager)
                .environmentObject(summarizationEngine)
        }
    }
}
