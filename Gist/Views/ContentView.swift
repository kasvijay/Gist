import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var diarizationManager: DiarizationManager
    @EnvironmentObject var summarizationEngine: SummarizationEngine
    @State private var selectedSessionID: String?

    var body: some View {
        NavigationSplitView {
            SessionListView(selectedSessionID: $selectedSessionID)
        } detail: {
            SessionDetailView(selectedSessionID: $selectedSessionID, onStop: {
                if let result = recordingManager.stopRecording(
                    sessionStore: sessionStore,
                    transcriptionEngine: transcriptionEngine,
                    diarizationManager: diarizationManager,
                    summarizationEngine: summarizationEngine
                ) {
                    selectedSessionID = result.session.id
                }
            })
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                modelStatusView
            }
            ToolbarItemGroup(placement: .primaryAction) {
                recordButton
            }
        }
        .task {
            summarizationEngine.transcriptionEngine = transcriptionEngine

            let stored = UserDefaults.standard.string(forKey: "defaultModel") ?? "large-v3_turbo"
            transcriptionEngine.modelName = stored
            await transcriptionEngine.loadModel()

            // Load diarization method from settings
            let storedMethod = UserDefaults.standard.string(forKey: "diarizationMethod") ?? "lsEend"
            if let method = DiarizationMethod(rawValue: storedMethod) {
                diarizationManager.method = method
            }

            await diarizationManager.loadMLModel()
            if diarizationManager.method == .vbx {
                await diarizationManager.loadVBxModel()
            }
        }
        .alert("Model Downloaded", isPresented: $transcriptionEngine.showDownloadComplete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The transcription model has been downloaded and is ready to use.")
        }
        .alert("Recording Failed", isPresented: Binding(
            get: { recordingManager.error != nil },
            set: { if !$0 { recordingManager.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recordingManager.error ?? "An unknown error occurred.")
        }
        .alert("Recording Consent", isPresented: $recordingManager.showConsentAlert) {
            Button("Yes") {
                recordingManager.confirmAndStartRecording()
            }
            Button("No", role: .cancel) {
                recordingManager.cancelRecording()
            }
        } message: {
            Text("Have you informed all participants that you are recording this conversation?")
        }
    }

    @ViewBuilder
    private var modelStatusView: some View {
        switch transcriptionEngine.state {
        case .downloading(let model, let progress):
            HStack(spacing: 6) {
                ProgressView(value: Double(progress))
                    .frame(width: 80)
                    .controlSize(.small)
                Text("Downloading \(model) — \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loading(let model):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading \(model)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .notLoaded:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Retry") {
                    Task { await transcriptionEngine.loadModel() }
                }
                .controlSize(.small)
            }
        case .ready:
            // Model info bar
            HStack(spacing: 8) {
                modelBadge(transcriptionEngine.modelName, icon: "waveform")
                modelBadge(diarizationManager.method.displayName, icon: "person.2")
            }
        case .streaming, .transcribing:
            // Model info still visible during active use
            HStack(spacing: 8) {
                modelBadge(transcriptionEngine.modelName, icon: "waveform")
                modelBadge(diarizationManager.method.displayName, icon: "person.2")
            }
        }
    }

    private func modelBadge(_ name: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(name)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var recordButton: some View {
        Button {
            if recordingManager.isRecording {
                if let result = recordingManager.stopRecording(
                    sessionStore: sessionStore,
                    transcriptionEngine: transcriptionEngine,
                    diarizationManager: diarizationManager,
                    summarizationEngine: summarizationEngine
                ) {
                    selectedSessionID = result.session.id
                }
            } else {
                recordingManager.startRecording(
                    sessionStore: sessionStore,
                    transcriptionEngine: transcriptionEngine,
                    diarizationManager: diarizationManager
                )
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: recordingManager.isRecording ? "stop.circle.fill" : "record.circle")
                    .foregroundStyle(recordingManager.isRecording ? Color.primary : Color.red)
                if recordingManager.isRecording {
                    Text(formatTime(recordingManager.elapsedTime))
                        .monospacedDigit()
                        .font(.caption)
                }
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(recordingManager.isStarting || (!recordingManager.isRecording && transcriptionEngine.state != .ready))
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension TranscriptionEngine.State {
    var isTranscribing: Bool {
        if case .transcribing = self { return true }
        return false
    }
}
