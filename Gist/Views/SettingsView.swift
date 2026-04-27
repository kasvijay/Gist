import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject var diarizationManager: DiarizationManager
    @EnvironmentObject var summarizationEngine: SummarizationEngine

    @AppStorage("defaultModel") private var defaultModel = "large-v3"
    @AppStorage("customModelPath") private var customModelPath = ""
    @AppStorage("summarizationModel") private var summarizationModel = "mlx-community/gemma-3-4b-it-qat-4bit"
    @AppStorage("diarizationMethod") private var diarizationMethod = "vbx"

    @State private var micPermission: AVAudioApplication.recordPermission = .undetermined
    @State private var systemAudioGranted = false
    @State private var isDownloadingTranscription = false
    @State private var isDownloadingSummarization = false
    @State private var cachedModelList: [(id: String, displayName: String, size: UInt64, isActive: Bool)] = []
    @State private var modelToDelete: String?

    private let availableModels = [
        ("tiny", "Tiny (39MB)", "Quick test — gets the gist, misses details"),
        ("small", "Small (216MB)", "Casual notes — good for clear 1-on-1 audio"),
        ("large-v3_turbo", "Large Turbo (600MB)", "Recommended — handles accents, crosstalk, background noise"),
        ("large-v3", "Large (1.5GB)", "Maximum accuracy — slower, best for difficult audio"),
        ("custom", "Custom Model", "Load your own fine-tuned model from disk"),
    ]

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Default Model", selection: $defaultModel) {
                    ForEach(availableModels, id: \.0) { model in
                        VStack(alignment: .leading) {
                            Text(model.1)
                            Text(model.2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.0)
                    }
                }
                .onChange(of: defaultModel) {
                    if defaultModel != "custom" {
                        transcriptionEngine.modelName = defaultModel
                        transcriptionEngine.customModelFolder = nil
                        Task { await transcriptionEngine.loadModel() }
                    }
                }

                modelStatusRow

                if defaultModel == "custom" {
                    HStack {
                        TextField("Model folder path", text: $customModelPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseForModelFolder()
                        }
                    }
                    .onChange(of: customModelPath) {
                        if !customModelPath.isEmpty {
                            transcriptionEngine.customModelFolder = customModelPath
                            transcriptionEngine.modelName = "custom"
                        }
                    }

                    Text("Point to a folder containing compiled Core ML models (.mlmodelc files). Convert Whisper models with [whisperkittools](https://github.com/argmaxinc/whisperkittools).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Models download from HuggingFace on first use. Cache: ~/.cache/huggingface/hub/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    permissionBadge(granted: micPermission == .granted)
                    Button("Open Settings") {
                        openPrivacySettings("Microphone")
                    }
                    .controlSize(.small)
                }

                HStack {
                    Label("System Audio", systemImage: "speaker.wave.2.fill")
                    Spacer()
                    permissionBadge(granted: systemAudioGranted)
                    Button("Open Settings") {
                        openPrivacySettings("ScreenCapture")
                    }
                    .controlSize(.small)
                }

                Text("Both permissions are requested when you start recording. If denied, grant them in System Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speaker Identification") {
                Picker("Method", selection: $diarizationMethod) {
                    ForEach(DiarizationMethod.allCases, id: \.rawValue) { method in
                        VStack(alignment: .leading) {
                            Text(method.displayName)
                            Text(method.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(method.rawValue)
                    }
                }
                .onChange(of: diarizationMethod) {
                    if let method = DiarizationMethod(rawValue: diarizationMethod) {
                        diarizationManager.method = method
                        if method == .vbx && !diarizationManager.vbxReady {
                            Task { await diarizationManager.loadVBxModel() }
                        }
                    }
                }

                Text("LS-EEND labels speakers during recording (up to 10). VBx labels after recording with better accuracy and unlimited speakers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Summarization") {
                Picker("Model", selection: $summarizationModel) {
                    Text("Gemma 3 4B (3.0GB) — Recommended")
                        .tag("mlx-community/gemma-3-4b-it-qat-4bit")
                    Text("Phi-4 Mini (2.2GB)")
                        .tag("mlx-community/Phi-4-mini-instruct-4bit")
                    Text("Llama 3.2 3B (1.9GB)")
                        .tag("mlx-community/Llama-3.2-3B-Instruct-4bit")
                }
                .onChange(of: summarizationModel) {
                    summarizationEngine.modelName = summarizationModel
                    Task.detached { await summarizationEngine.loadModel() }
                }

                summarizationStatusRow

                Text("Used for generating meeting summaries after each recording. Downloads from HuggingFace on first use, then runs fully offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Downloaded Models") {
                if cachedModelList.isEmpty {
                    Text("No models downloaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cachedModelList, id: \.id) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                    .font(.body)
                                Text(formatBytes(model.size))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.isActive {
                                Text("In use")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Button(role: .destructive) {
                                    modelToDelete = model.id
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Text("Models are cached at ~/.cache/huggingface/hub/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear { cachedModelList = summarizationEngine.cachedModels() }
            .onChange(of: summarizationEngine.state) { cachedModelList = summarizationEngine.cachedModels() }
            .alert("Delete Model?", isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let id = modelToDelete {
                        summarizationEngine.deleteCache(for: id)
                        cachedModelList = summarizationEngine.cachedModels()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete the downloaded model and free disk space. You can re-download it later.")
            }

            Section("Storage") {
                HStack {
                    Text("Recordings folder")
                    Spacer()
                    Text("~/Documents/Gist/")
                        .foregroundStyle(.secondary)
                    Button("Open") {
                        let url = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Documents")
                            .appendingPathComponent("Gist")
                        NSWorkspace.shared.open(url)
                    }
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 500, height: 700)
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            switch transcriptionEngine.state {
            case .downloading(let model, let progress):
                HStack(spacing: 6) {
                    ProgressView(value: Double(progress))
                        .frame(width: 60)
                        .controlSize(.small)
                    Text("Downloading \(model) — \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .loading(let model):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading \(model)…")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .error(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            case .notLoaded:
                Text("Not loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .ready:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            case .streaming, .transcribing:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("In use")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var summarizationStatusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            switch summarizationEngine.state {
            case .downloading(let progress):
                HStack(spacing: 6) {
                    ProgressView(value: Double(progress))
                        .frame(width: 60)
                        .controlSize(.small)
                    Text("Downloading — \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .error(let msg):
                VStack(alignment: .trailing, spacing: 4) {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Button("Re-download") {
                        summarizationEngine.deleteModelCache()
                        Task.detached { await summarizationEngine.loadModel() }
                    }
                    .controlSize(.small)
                }
            case .idle:
                if summarizationEngine.loadedModelReady {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Ready — \(shortModelName(summarizationModel))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Not loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .complete:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready — \(shortModelName(summarizationModel))")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            case .summarizing:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("In use")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func permissionBadge(granted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Text(granted ? "Granted" : "Not Granted")
                .font(.caption)
                .foregroundStyle(granted ? .green : .orange)
        }
    }

    private func refreshPermissions() {
        micPermission = AVAudioApplication.shared.recordPermission
        systemAudioGranted = checkScreenRecordingPermission()
    }

    private func checkScreenRecordingPermission() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windowList.contains { dict in
            guard let pid = dict[kCGWindowOwnerPID as String] as? Int32 else { return false }
            return pid != ownPID
        }
    }

    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func shortModelName(_ id: String) -> String {
        // "mlx-community/gemma-3-4b-it-qat-4bit" → "gemma-3-4b"
        let name = id.components(separatedBy: "/").last ?? id
        return name
            .replacingOccurrences(of: "-Instruct-4bit", with: "")
            .replacingOccurrences(of: "-instruct-4bit", with: "")
            .replacingOccurrences(of: "-it-qat-4bit", with: "")
            .replacingOccurrences(of: "-it-4bit", with: "")
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func browseForModelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing WhisperKit Core ML models"

        if panel.runModal() == .OK, let url = panel.url {
            customModelPath = url.path
        }
    }
}
