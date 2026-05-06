import Foundation

enum CloudTranscriptionProgress: Sendable {
    case uploading(fraction: Double)
    case processing
    case downloading
    case complete
}

protocol TranscriptionProvider: Sendable {
    var providerID: ProviderID { get }
    var providesDiarization: Bool { get }
    var maxFileSizeBytes: Int64? { get }

    func transcribe(
        audioURL: URL,
        modelID: String,
        duration: Double,
        progress: @escaping @Sendable (CloudTranscriptionProgress) -> Void
    ) async throws -> Transcript
}

protocol SummarizationProvider: Sendable {
    var providerID: ProviderID { get }

    func summarize(
        transcript: Transcript,
        modelID: String,
        systemPrompt: String,
        userPrompt: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> Summary
}

enum ProviderError: LocalizedError {
    case notConfigured(ProviderID)
    case authenticationFailed(String)
    case rateLimited(retryAfter: TimeInterval?)
    case fileTooLarge(maxBytes: Int64)
    case networkError(Error)
    case invalidResponse(String)
    case transcriptionFailed(String)
    case summarizationFailed(String)
    case providerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let id): return "\(id.displayName) is not configured. Add an API key in Settings."
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .rateLimited(let retry): return "Rate limited." + (retry.map { " Retry in \(Int($0))s." } ?? "")
        case .fileTooLarge(let max): return "Audio file too large. Maximum \(max / 1_048_576) MB."
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .summarizationFailed(let msg): return "Summarization failed: \(msg)"
        case .providerUnavailable(let msg): return msg
        }
    }
}
