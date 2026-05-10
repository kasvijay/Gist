import FluidAudio
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var diarizationManager: DiarizationManager
    @EnvironmentObject var summarizationEngine: SummarizationEngine
    @State private var selectedSessionID: String?
    @State private var showImportSheet = false
    @State private var importInitialText = ""
    @State private var importInitialFilename = ""

    var body: some View {
        NavigationSplitView {
            SessionListView(
                selectedSessionID: $selectedSessionID,
                showImportSheet: $showImportSheet,
                importInitialText: $importInitialText,
                importInitialFilename: $importInitialFilename
            )
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
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                modelStatusView
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleWindowDrop(providers: providers)
        }
        .sheet(isPresented: $showImportSheet) {
            ImportTranscriptSheet(
                initialText: importInitialText,
                initialFilename: importInitialFilename,
                onImport: { sessionID in
                    selectedSessionID = sessionID
                }
            )
        }
        .task {
            summarizationEngine.transcriptionEngine = transcriptionEngine

            // Set defaults for new users only (don't override existing choice)
            if UserDefaults.standard.string(forKey: "defaultModel") == nil {
                UserDefaults.standard.set("large-v3", forKey: "defaultModel")
            }
            if UserDefaults.standard.string(forKey: "diarizationMethod") == nil {
                UserDefaults.standard.set("vbx", forKey: "diarizationMethod")
            }

            let stored = UserDefaults.standard.string(forKey: "defaultModel") ?? "large-v3"
            transcriptionEngine.modelName = stored

            // Pre-download and compile Parakeet model in background
            if ProviderRegistry.shared.defaults.transcriptionProviderID == .localParakeet {
                Task.detached(priority: .utility) {
                    let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
                    if !AsrModels.modelsExist(at: cacheDir, version: .v3) {
                        _ = try? await AsrModels.downloadAndLoad(version: .v3)
                    }
                }
            }

            // First launch: download WhisperKit model (then unload to free memory)
            // Subsequent launches: skip loading — pipeline loads on demand
            if !transcriptionEngine.isModelCached {
                await transcriptionEngine.loadModel()
                transcriptionEngine.unloadModel()
            }
            // Always mark ready — model is either cached on disk or just downloaded
            transcriptionEngine.state = .ready

            // Same for summarization model
            if !summarizationEngine.isSummarizationModelCached(summarizationEngine.modelName) {
                await summarizationEngine.loadModel()
                summarizationEngine.unloadModel()
            }

            // Load diarization method from settings
            let storedMethod = UserDefaults.standard.string(forKey: "diarizationMethod") ?? "vbx"
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
        .onChange(of: recordingManager.activeSessionID) { _, newValue in
            if let newValue {
                selectedSessionID = newValue
            }
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

    private func handleWindowDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let allowed: Set<String> = ["vtt", "srt", "txt", "text"]
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            guard allowed.contains(url.pathExtension.lowercased()) else { return }
            Task { @MainActor in
                switch TranscriptImporter.readFile(at: url) {
                case .success(let text):
                    importInitialText = text
                    importInitialFilename = url.lastPathComponent
                    showImportSheet = true
                case .failure:
                    // Surfacing an error from a window-level drop without a sheet open
                    // would feel out of context. The sheet's own validation will surface
                    // any parse error if the user opens the sheet manually.
                    break
                }
            }
        }
        return true
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

}

extension TranscriptionEngine.State {
    var isTranscribing: Bool {
        if case .transcribing = self { return true }
        return false
    }
}
