import SwiftUI
import UniformTypeIdentifiers

/// Sheet for importing a transcript from paste, file, or drag-drop. Auto-detects
/// VTT / SRT / plain-text-with-speakers / paragraph and shows a live preview.
struct ImportTranscriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var summarizationEngine: SummarizationEngine
    @EnvironmentObject var transcriptionEngine: TranscriptionEngine

    var initialText: String = ""
    var initialFilename: String = ""
    var onImport: ((String) -> Void)? = nil   // called with the new sessionID

    @State private var text: String = ""
    @State private var title: String = ""
    @State private var preview: TranscriptImporter.PreviewInfo?
    @State private var errorMessage: String?
    @State private var isDropTargeted: Bool = false
    @State private var isImporting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleField
                    pasteArea
                    actions
                    previewSection
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 600)
        .onAppear {
            if !initialText.isEmpty {
                text = initialText
                refreshPreview()
            }
            if title.isEmpty {
                title = defaultTitle()
            }
        }
        .onChange(of: text) { _, _ in refreshPreview() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Import Transcript")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointerHand()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Imported Transcript", text: $title)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var pasteArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDropTargeted ? Color.accentColor : Color.gray.opacity(0.25),
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1,
                                               dash: text.isEmpty ? [6, 4] : []))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDropTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                    )

                if text.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text("Paste transcript here, drop a .vtt / .srt / .txt file, or click \"Open File…\"")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(minHeight: 220)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                openFile()
            } label: {
                Label("Open File…", systemImage: "folder")
            }
            .pointerHand()

            Button {
                paste()
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }
            .pointerHand()

            if !text.isEmpty {
                Button(role: .destructive) {
                    text = ""
                    preview = nil
                    errorMessage = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .pointerHand()
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    pill(label: "Detected", value: preview.format.displayName, color: .accentColor)
                    pill(label: "Segments", value: "\(preview.segmentCount)", color: .green)
                    pill(label: "Speakers", value: "\(preview.speakerCount)", color: .orange)
                    if let d = preview.durationSeconds, d > 0 {
                        pill(label: "Duration", value: formatDuration(d), color: .purple)
                    }
                }
                if !preview.firstLine.isEmpty {
                    Text("\u{201C}\(preview.firstLine)…\u{201D}")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .pointerHand()
            Button {
                runImport()
            } label: {
                if isImporting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Importing…")
                    }
                } else {
                    Text("Import & Summarize")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            .pointerHand()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func pill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
    }

    private func defaultTitle() -> String {
        if !initialFilename.isEmpty {
            return (initialFilename as NSString).deletingPathExtension
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return "Imported · \(f.string(from: Date()))"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private func refreshPreview() {
        errorMessage = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            preview = nil
            return
        }
        if text.count > TranscriptImporter.maxCharacters {
            preview = nil
            errorMessage = "Transcript is \(text.count) characters — exceeds the \(TranscriptImporter.maxCharacters)-character limit."
            return
        }
        preview = TranscriptImporter.preview(text)
    }

    private func paste() {
        if let s = NSPasteboard.general.string(forType: .string) {
            text = s
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a transcript file"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "vtt") ?? .text,
            UTType(filenameExtension: "srt") ?? .text,
            .plainText, .text
        ]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            switch TranscriptImporter.readFile(at: url) {
            case .success(let s):
                text = s
                if title.isEmpty || title.hasPrefix("Imported ·") {
                    title = (url.lastPathComponent as NSString).deletingPathExtension
                }
            case .failure(let e):
                errorMessage = e.localizedDescription
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                switch TranscriptImporter.readFile(at: url) {
                case .success(let s):
                    text = s
                    if title.isEmpty || title.hasPrefix("Imported ·") {
                        title = (url.lastPathComponent as NSString).deletingPathExtension
                    }
                case .failure(let e):
                    errorMessage = e.localizedDescription
                }
            }
        }
        return true
    }

    private func runImport() {
        errorMessage = nil
        isImporting = true
        let raw = text
        let displayTitle = title

        Task { @MainActor in
            switch TranscriptImporter.parse(raw) {
            case .failure(let e):
                errorMessage = e.localizedDescription
                isImporting = false
            case .success(let transcript):
                let entry = sessionStore.createImportedSession(name: displayTitle, transcript: transcript)
                onImport?(entry.id)

                // Kick off summarization with the current default provider.
                let registry = ProviderRegistry.shared
                let providerID = registry.defaults.summarizationProviderID
                let modelID = registry.defaults.summarizationModelID
                let userPrompt = SummaryPromptBuilder.buildUserPrompt(transcript: transcript)

                if providerID == .localMLX {
                    summarizationEngine.startSummarization(
                        transcript: transcript,
                        transcriptionEngine: transcriptionEngine
                    ) { summary in
                        if let summary {
                            sessionStore.saveSummary(summary, for: entry.id)
                        }
                    }
                } else {
                    Task {
                        let provider = makeSummarizationProvider(providerID)
                        do {
                            let summary = try await provider.summarize(
                                transcript: transcript,
                                modelID: modelID,
                                systemPrompt: SummaryPromptBuilder.systemPrompt,
                                userPrompt: userPrompt,
                                stream: { _ in }
                            )
                            await MainActor.run {
                                sessionStore.saveSummary(summary, for: entry.id)
                                summarizationEngine.currentSummary = summary
                            }
                        } catch {
                            await MainActor.run {
                                summarizationEngine.streamingText = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                }

                isImporting = false
                dismiss()
            }
        }
    }

    private func makeSummarizationProvider(_ id: ProviderID) -> any SummarizationProvider {
        switch id {
        case .localMLX: return LocalMLXProvider(engine: summarizationEngine)
        case .anthropic: return AnthropicProvider()
        case .openAISummarization: return OpenAISummarizationProvider()
        case .googleGemini: return GoogleGeminiProvider()
        case .mistral: return MistralProvider()
        case .ollama: return OllamaProvider()
        case .groqSummarization: return GroqSummarizationProvider()
        default: return LocalMLXProvider(engine: summarizationEngine)
        }
    }
}
