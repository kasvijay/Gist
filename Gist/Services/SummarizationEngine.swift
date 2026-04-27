import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers
import os

// MARK: - HuggingFace Downloader

struct HFDownloader: Downloader {
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent("models--\(id.replacingOccurrences(of: "/", with: "--"))")

        let snapshotDir = cacheDir.appendingPathComponent("snapshot")
        if !useLatest, FileManager.default.fileExists(atPath: snapshotDir.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(at: snapshotDir, includingPropertiesForKeys: nil),
               let first = contents.first,
               Self.isSnapshotComplete(first) {
                return first
            }
        }

        let rev = revision ?? "main"
        let apiURL = URL(string: "https://huggingface.co/api/models/\(id)/tree/\(rev)")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)

        struct FileEntry: Decodable {
            let path: String
            let type: String
            let size: Int64?
        }
        let entries = (try? JSONDecoder().decode([FileEntry].self, from: data)) ?? []

        let fileEntries = entries.filter { $0.type == "file" }.filter { entry in
            patterns.isEmpty || patterns.contains(where: { matchGlob(pattern: $0, string: entry.path) })
        }

        // Build a size lookup for validating existing files
        var expectedSizes: [String: Int64] = [:]
        for entry in fileEntries {
            if let size = entry.size {
                expectedSizes[entry.path] = size
            }
        }

        let downloadDir = cacheDir.appendingPathComponent("snapshot/\(rev)")
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let progress = Progress(totalUnitCount: Int64(fileEntries.count))

        for entry in fileEntries {
            let destURL = downloadDir.appendingPathComponent(entry.path)

            // Check if file exists AND has the correct size
            if FileManager.default.fileExists(atPath: destURL.path) {
                if let expectedSize = expectedSizes[entry.path] {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
                    let localSize = attrs?[.size] as? Int64 ?? 0
                    if localSize == expectedSize {
                        progress.completedUnitCount += 1
                        progressHandler(progress)
                        continue
                    }
                    // Size mismatch — delete and re-download
                    try? FileManager.default.removeItem(at: destURL)
                } else {
                    // No expected size available — trust existing file
                    progress.completedUnitCount += 1
                    progressHandler(progress)
                    continue
                }
            }

            let parentDir = destURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            let fileURL = URL(string: "https://huggingface.co/\(id)/resolve/\(rev)/\(entry.path)")!
            let (tempURL, _) = try await URLSession.shared.download(from: fileURL)
            try FileManager.default.moveItem(at: tempURL, to: destURL)

            progress.completedUnitCount += 1
            progressHandler(progress)
        }

        return downloadDir
    }

    /// Check if a snapshot directory has both config.json and at least one model weights file.
    static func isSnapshotComplete(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) else { return false }

        // Must have at least one model weights file (.safetensors or .gguf)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return false }
        return files.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "safetensors" || ext == "gguf"
        }
    }

    private func matchGlob(pattern: String, string: String) -> Bool {
        let regex = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
        return string.range(of: "^\(regex)$", options: .regularExpression) != nil
    }
}

// MARK: - Tokenizer Loader

struct TransformersTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let hfTokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerWrapper(inner: hfTokenizer)
    }
}

struct TokenizerWrapper: MLXLMCommon.Tokenizer {
    let inner: Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        inner.encode(text: text)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        inner.decode(tokens: tokenIds)
    }

    func convertTokenToId(_ token: String) -> Int? {
        inner.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        inner.convertIdToToken(id)
    }

    var bosToken: String? { inner.bosToken }
    var eosToken: String? { inner.eosToken }
    var unknownToken: String? { inner.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try inner.applyChatTemplate(messages: messages)
    }
}

// MARK: - Summarization Engine

@MainActor
final class SummarizationEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(Float)
        case loading
        case summarizing
        case complete
        case error(String)
    }

    @Published var state: State = .idle
    @Published var currentSummary: Summary?
    @Published var streamingText: String = ""

    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "SummarizationEngine")
    private var modelContainer: ModelContainer?
    private var loadedModelID: String?
    private var summarizationTask: Task<Summary?, Never>?

    var modelName: String = "mlx-community/gemma-3-4b-it-qat-4bit"
    weak var transcriptionEngine: TranscriptionEngine?

    /// Maximum tokens for the transcript portion of the prompt.
    /// Conservative limit that keeps total input+output within Metal buffer limits on 8GB Macs.
    private let maxTranscriptTokens = 5000

    var loadedModelReady: Bool {
        modelContainer != nil && loadedModelID == modelName
    }

    var isWorking: Bool {
        switch state {
        case .downloading, .loading, .summarizing: return true
        default: return false
        }
    }

    var statusMessage: String? {
        switch state {
        case .downloading(let progress):
            return "Downloading summarization model — \(Int(progress * 100))%"
        case .loading:
            return "Loading summarization model…"
        case .summarizing:
            return nil // streaming text handles this
        case .error(let msg):
            return msg
        default:
            return nil
        }
    }

    // MARK: - Model Loading

    func loadModel() async {
        let modelID = modelName
        if loadedModelID == modelID, modelContainer != nil { return }

        // Release old model before loading new one to free memory
        modelContainer = nil
        loadedModelID = nil

        // On memory-constrained machines, unload WhisperKit before loading summarization model
        let totalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let shouldUnloadWhisper = totalMemoryGB <= 8 && (transcriptionEngine?.isModelLoaded ?? false)
        if shouldUnloadWhisper {
            transcriptionEngine?.unloadModel()
            logger.info("Unloaded WhisperKit to free memory for summarization model")
        }

        let cached = isSummarizationModelCached(modelID)
        state = cached ? .loading : .downloading(0)
        logger.info("\(cached ? "Loading" : "Downloading") summarization model: \(modelID)")

        do {
            let container = try await loadModelContainer(
                from: HFDownloader(),
                using: TransformersTokenizerLoader(),
                id: modelID
            ) { progress in
                Task { @MainActor in
                    if !cached {
                        self.state = .downloading(Float(progress.fractionCompleted))
                    }
                }
            }
            modelContainer = container
            loadedModelID = modelID
            state = .idle
            logger.info("Summarization model loaded: \(modelID)")
        } catch {
            state = .error("Failed to load model: \(error.localizedDescription)")
            logger.error("Failed to load summarization model: \(error)")
        }

        // Reload WhisperKit after summarization model is loaded
        if shouldUnloadWhisper {
            await transcriptionEngine?.loadModel()
        }
    }

    private func isSummarizationModelCached(_ id: String) -> Bool {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent("models--\(id.replacingOccurrences(of: "/", with: "--"))")
            .appendingPathComponent("snapshot")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil
        ), let first = contents.first else { return false }
        return HFDownloader.isSnapshotComplete(first)
    }

    // MARK: - Summarization

    /// Summarize a transcript. Optionally pass the transcription engine to unload WhisperKit
    /// during summarization to free memory (important on 8GB machines).
    func summarize(transcript: Transcript, transcriptionEngine: TranscriptionEngine? = nil) async -> Summary? {
        // Unload WhisperKit to free memory for the LLM on machines with ≤ 8GB RAM
        let totalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let shouldUnload = totalMemoryGB <= 8 && (transcriptionEngine?.isModelLoaded ?? false)
        if shouldUnload {
            transcriptionEngine?.unloadModel()
        }

        let result: Summary?

        if let container = modelContainer {
            result = await runSummarization(transcript: transcript, container: container)
        } else {
            await loadModel()
            if let container = modelContainer {
                result = await runSummarization(transcript: transcript, container: container)
            } else {
                if case .error = state {} else {
                    state = .error("Failed to load summarization model. Check Settings to download it.")
                }
                result = nil
            }
        }

        // Reload WhisperKit after summarization
        if shouldUnload {
            await transcriptionEngine?.loadModel()
        }

        return result
    }

    func cancel() {
        summarizationTask?.cancel()
        summarizationTask = nil
        state = .idle
        streamingText = ""
    }

    /// Start summarization in a tracked Task that can be cancelled.
    func startSummarization(transcript: Transcript, transcriptionEngine: TranscriptionEngine?, completion: ((Summary?) -> Void)? = nil) {
        summarizationTask?.cancel()
        summarizationTask = Task {
            let summary = await summarize(transcript: transcript, transcriptionEngine: transcriptionEngine)
            completion?(summary)
            return summary
        }
    }

    private func runSummarization(transcript: Transcript, container: ModelContainer) async -> Summary? {
        state = .summarizing
        streamingText = ""

        let prompt = await buildPrompt(transcript: transcript, container: container)

        do {
            let userInput = UserInput(chat: [
                .system("You are a concise meeting summarizer. Output only the requested sections in clean markdown. Do not repeat yourself. Do not add follow-up questions, offers to elaborate, or any text outside the requested sections. Stop immediately after the last bullet point."),
                .user(prompt),
            ])
            let lmInput = try await container.prepare(input: userInput)

            let parameters = GenerateParameters(
                maxTokens: 2048,
                temperature: 0.3,
                topP: 0.9,
                repetitionPenalty: 1.2
            )

            var output = ""
            let stream = try await container.generate(input: lmInput, parameters: parameters)

            for await generation in stream {
                if Task.isCancelled { break }
                if case .chunk(let text) = generation {
                    output += text
                    streamingText = output
                }
            }

            guard !Task.isCancelled else {
                state = .idle
                return nil
            }

            let summary = parseSummary(output: output, model: modelName)
            currentSummary = summary
            state = .complete
            logger.info("Summarization complete: \(output.count) chars")
            return summary

        } catch {
            state = .error("Summarization failed: \(error.localizedDescription)")
            logger.error("Summarization failed: \(error)")
            return nil
        }
    }

    // MARK: - Prompt Building

    private func buildPrompt(transcript: Transcript, container: ModelContainer) async -> String {
        let transcriptText = await formatTranscriptWithinBudget(transcript, container: container)

        return """
        Summarize this meeting transcript using exactly these four sections in this order:

        ## Overview
        A brief paragraph of what was discussed.

        ## Decisions
        Bullet list of decisions made during the meeting. Omit this section entirely if there are no decisions.

        ## Action Items
        Bullet list of action items with the responsible person if mentioned. Omit this section entirely if there are none.

        ## Key Discussion Points
        Bullet list of all key discussion points, topics, outcomes, and notable exchanges. \
        Cover every important point — do not limit the number of bullets.

        Use "- " for each bullet. Do not number the sections. Do not add any text outside these sections.

        \(transcriptText)
        """
    }

    private func formatTranscript(_ transcript: Transcript) -> String {
        transcript.segments.map { segment in
            let speaker = segment.speaker ?? "Unknown"
            return "[\(speaker)] \(segment.text)"
        }.joined(separator: "\n")
    }

    /// Format the transcript, sampling segments evenly across the timeline if needed
    /// to stay within the token budget for the LLM context window.
    private func formatTranscriptWithinBudget(_ transcript: Transcript, container: ModelContainer) async -> String {
        let tokenizer = await container.tokenizer

        // Format all segments
        let allFormatted = transcript.segments.map { segment -> String in
            let speaker = segment.speaker ?? "Unknown"
            return "[\(speaker)] \(segment.text)"
        }

        // Check if full transcript fits
        let fullText = allFormatted.joined(separator: "\n")
        let fullTokenCount = tokenizer.encode(text: fullText, addSpecialTokens: false).count

        if fullTokenCount <= maxTranscriptTokens {
            logger.info("Transcript fits: \(allFormatted.count) segments, \(fullTokenCount) tokens")
            return fullText
        }

        // Over budget — sample evenly across the timeline
        let avgTokensPerSegment = max(1, fullTokenCount / max(1, allFormatted.count))
        var targetCount = maxTranscriptTokens / avgTokensPerSegment
        targetCount = max(1, min(targetCount, allFormatted.count))

        var sampledText = sampleSegmentsEvenly(allFormatted, targetCount: targetCount)
        var sampledTokenCount = tokenizer.encode(text: sampledText, addSpecialTokens: false).count

        // Refine: shrink until within budget
        while sampledTokenCount > maxTranscriptTokens && targetCount > 1 {
            targetCount = max(1, targetCount * 4 / 5)
            sampledText = sampleSegmentsEvenly(allFormatted, targetCount: targetCount)
            sampledTokenCount = tokenizer.encode(text: sampledText, addSpecialTokens: false).count
        }

        let durationMinutes = Int(transcript.durationSeconds / 60)
        logger.info("Transcript condensed: \(allFormatted.count) segments (\(fullTokenCount) tokens) → \(targetCount) segments (\(sampledTokenCount) tokens), \(durationMinutes) min recording")

        let header = "[Note: This transcript (\(durationMinutes) min, \(allFormatted.count) segments) " +
                     "was condensed to \(targetCount) evenly-spaced segments to fit context limits.]\n\n"
        return header + sampledText
    }

    /// Select `targetCount` segments evenly spaced across the array, always including first and last.
    private func sampleSegmentsEvenly(_ segments: [String], targetCount: Int) -> String {
        let count = segments.count
        guard count > 0 else { return "" }
        guard targetCount < count else { return segments.joined(separator: "\n") }
        guard targetCount > 1 else { return segments[0] }

        var indices: [Int] = []
        let step = Double(count - 1) / Double(targetCount - 1)
        for i in 0..<targetCount {
            let idx = min(Int((Double(i) * step).rounded()), count - 1)
            if indices.last != idx {
                indices.append(idx)
            }
        }

        return indices.map { segments[$0] }.joined(separator: "\n")
    }

    // MARK: - Parsing

    private func parseSummary(output: String, model: String) -> Summary {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let overview = extractParagraph(from: trimmed, header: "## Overview")
        let decisions = extractSection(from: trimmed, header: "## Decisions")
        let actionItems = extractSection(from: trimmed, header: "## Action Items")
        let keyPoints = extractSection(from: trimmed, header: "## Key Discussion Points")

        return Summary(
            created: Date(),
            model: model,
            content: trimmed,
            overview: overview,
            decisions: decisions,
            actionItems: actionItems,
            keyPoints: keyPoints
        )
    }

    private func extractParagraph(from text: String, header: String) -> String? {
        guard let headerRange = text.range(of: header) else { return nil }
        let afterHeader = text[headerRange.upperBound...]

        let nextHeader = afterHeader.range(of: "\n## ")
        let sectionEnd = nextHeader?.lowerBound ?? afterHeader.endIndex
        let section = String(afterHeader[..<sectionEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        return section.isEmpty ? nil : section
    }

    private func extractSection(from text: String, header: String) -> [String]? {
        guard let headerRange = text.range(of: header) else { return nil }
        let afterHeader = text[headerRange.upperBound...]

        let nextHeader = afterHeader.range(of: "\n## ")
        let sectionEnd = nextHeader?.lowerBound ?? afterHeader.endIndex
        let section = afterHeader[..<sectionEnd]

        let items = section
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .map { String($0.dropFirst(2)) }

        return items.isEmpty ? nil : items
    }

    // MARK: - Cache Management

    private static var hfCacheDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    /// Delete the cached model for the current modelName, then reset state.
    func deleteModelCache() {
        deleteCache(for: modelName)
        modelContainer = nil
        loadedModelID = nil
        state = .idle
    }

    /// Delete the cache directory for a specific model ID.
    func deleteCache(for modelID: String) {
        let dir = Self.hfCacheDir
            .appendingPathComponent("models--\(modelID.replacingOccurrences(of: "/", with: "--"))")
        try? FileManager.default.removeItem(at: dir)
        logger.info("Deleted cache for \(modelID)")
    }

    /// Return a list of cached summarization models with their disk sizes.
    func cachedModels() -> [(id: String, displayName: String, size: UInt64, isActive: Bool)] {
        let fm = FileManager.default
        let cacheDir = Self.hfCacheDir

        guard let contents = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return contents.compactMap { dir in
            let name = dir.lastPathComponent
            guard name.hasPrefix("models--mlx-community--") else { return nil }

            let modelID = name
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")
            let displayName = modelID.components(separatedBy: "/").last ?? modelID
            let size = Self.directorySize(dir)
            let isActive = modelID == modelName && loadedModelReady

            return (id: modelID, displayName: displayName, size: size, isActive: isActive)
        }.sorted { $0.displayName < $1.displayName }
    }

    private static func directorySize(_ url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }
}
