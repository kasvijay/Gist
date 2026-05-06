import SwiftUI

// MARK: - Provider ID

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    // Transcription
    case localWhisper
    case localParakeet
    case openAIWhisper
    case deepgram
    case assemblyAI
    case groqTranscription
    case googleTranscription

    // Summarization
    case localMLX
    case anthropic
    case openAISummarization
    case googleGemini
    case mistral
    case ollama
    case groqSummarization

    var id: String { rawValue }
}

extension ProviderID {
    var displayName: String {
        switch self {
        case .localWhisper: return "Whisper (Local)"
        case .localParakeet: return "Parakeet (Local)"
        case .openAIWhisper: return "OpenAI Whisper"
        case .deepgram: return "Deepgram"
        case .assemblyAI: return "AssemblyAI"
        case .groqTranscription: return "Groq Whisper"
        case .googleTranscription: return "Google Cloud"
        case .localMLX: return "On-device (MLX)"
        case .anthropic: return "Claude"
        case .openAISummarization: return "OpenAI"
        case .googleGemini: return "Gemini"
        case .mistral: return "Mistral"
        case .ollama: return "Ollama"
        case .groqSummarization: return "Groq"
        }
    }
}

// MARK: - Capability & Privacy

enum ProviderCapability: String, Codable {
    case transcription
    case summarization
}

enum PrivacyLevel: String, Codable {
    case onDevice
    case cloud
}

enum ModelTier: String, Codable {
    case best = "Best"
    case balanced = "Balanced"
    case fast = "Fast"
}

// MARK: - Model Info

struct ModelInfo: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let tier: ModelTier
    let speedDescription: String?
    let costDescription: String?
    let contextWindow: String?
    let sizeGB: String?
    let features: [String]?
}

// MARK: - Provider Info

struct ProviderInfo: Identifiable {
    let id: ProviderID
    let name: String
    let vendor: String
    let capability: ProviderCapability
    let privacy: PrivacyLevel
    let requiresAPIKey: Bool
    let keychainAccount: String?
    let markColor: Color
    let markTextColor: Color
    let markLetter: String
    let docsURL: URL?
    let models: [ModelInfo]
    let supportsBuiltInDiarization: Bool
    let isDefault: Bool
}

// MARK: - Static Catalog

enum ProviderCatalog {

    // MARK: Transcription Providers

    static let transcriptionProviders: [ProviderInfo] = [
        ProviderInfo(
            id: .localWhisper, name: "Whisper (Local)", vendor: "OpenAI \u{00B7} on-device",
            capability: .transcription, privacy: .onDevice,
            requiresAPIKey: false, keychainAccount: nil,
            markColor: Color(red: 0.89, green: 0.96, blue: 0.9),
            markTextColor: Color(red: 0.24, green: 0.47, blue: 0.28),
            markLetter: "W", docsURL: nil,
            models: [
                ModelInfo(id: "large-v3-turbo", displayName: "large-v3-turbo", tier: .best, speedDescription: "8\u{00D7} realtime", costDescription: nil, contextWindow: nil, sizeGB: "1.5 GB", features: nil),
                ModelInfo(id: "large-v3", displayName: "large-v3", tier: .best, speedDescription: "4\u{00D7} realtime", costDescription: nil, contextWindow: nil, sizeGB: "3.1 GB", features: nil),
                ModelInfo(id: "medium", displayName: "medium", tier: .balanced, speedDescription: "4\u{00D7} realtime", costDescription: nil, contextWindow: nil, sizeGB: "770 MB", features: nil),
                ModelInfo(id: "small", displayName: "small", tier: .fast, speedDescription: "12\u{00D7} realtime", costDescription: nil, contextWindow: nil, sizeGB: "244 MB", features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: true
        ),
        ProviderInfo(
            id: .localParakeet, name: "Parakeet (Local)", vendor: "NVIDIA \u{00B7} on-device",
            capability: .transcription, privacy: .onDevice,
            requiresAPIKey: false, keychainAccount: nil,
            markColor: Color(red: 0.46, green: 0.72, blue: 0.0),
            markTextColor: .white,
            markLetter: "P", docsURL: nil,
            models: [
                ModelInfo(id: "parakeet-v3", displayName: "Parakeet TDT v3", tier: .best, speedDescription: "120\u{00D7} realtime", costDescription: nil, contextWindow: nil, sizeGB: "300 MB", features: ["25 languages"]),
                ModelInfo(id: "parakeet-v2", displayName: "Parakeet TDT v2", tier: .balanced, speedDescription: "110\u{00D7} realtime", costDescription: nil, contextWindow: nil, sizeGB: "300 MB", features: ["English"]),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .openAIWhisper, name: "OpenAI Whisper", vendor: "OpenAI",
            capability: .transcription, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "openai-api-key",
            markColor: Color(red: 0.05, green: 0.07, blue: 0.06),
            markTextColor: .white,
            markLetter: "W",
            docsURL: URL(string: "https://platform.openai.com/api-keys"),
            models: [
                ModelInfo(id: "gpt-4o-transcribe", displayName: "gpt-4o-transcribe", tier: .best, speedDescription: "~20\u{00D7} realtime", costDescription: "$0.006/min", contextWindow: nil, sizeGB: nil, features: nil),
                ModelInfo(id: "whisper-1", displayName: "whisper-1", tier: .balanced, speedDescription: "~30\u{00D7} realtime", costDescription: "$0.006/min", contextWindow: nil, sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .deepgram, name: "Deepgram", vendor: "Deepgram",
            capability: .transcription, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "deepgram-api-key",
            markColor: Color(red: 0.07, green: 0.94, blue: 0.58),
            markTextColor: Color(red: 0.04, green: 0.12, blue: 0.09),
            markLetter: "D",
            docsURL: URL(string: "https://console.deepgram.com/"),
            models: [
                ModelInfo(id: "nova-3", displayName: "Nova-3", tier: .best, speedDescription: "~40\u{00D7} realtime", costDescription: "$0.0043/min", contextWindow: nil, sizeGB: nil, features: ["diarization", "punctuation"]),
                ModelInfo(id: "nova-2", displayName: "Nova-2", tier: .balanced, speedDescription: "~50\u{00D7} realtime", costDescription: "$0.0043/min", contextWindow: nil, sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: true, isDefault: false
        ),
        ProviderInfo(
            id: .assemblyAI, name: "AssemblyAI", vendor: "AssemblyAI",
            capability: .transcription, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "assemblyai-api-key",
            markColor: Color(red: 0.16, green: 0.27, blue: 1.0),
            markTextColor: .white,
            markLetter: "A",
            docsURL: URL(string: "https://www.assemblyai.com/dashboard/"),
            models: [
                ModelInfo(id: "universal-2", displayName: "Universal-2", tier: .best, speedDescription: "~25\u{00D7} realtime", costDescription: "$0.0065/min", contextWindow: nil, sizeGB: nil, features: ["diarization", "speaker labels"]),
            ],
            supportsBuiltInDiarization: true, isDefault: false
        ),
        ProviderInfo(
            id: .groqTranscription, name: "Groq Whisper", vendor: "Groq",
            capability: .transcription, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "groq-api-key",
            markColor: Color(red: 0.96, green: 0.31, blue: 0.21),
            markTextColor: .white,
            markLetter: "G",
            docsURL: URL(string: "https://console.groq.com/keys"),
            models: [
                ModelInfo(id: "whisper-large-v3-turbo", displayName: "whisper-large-v3-turbo", tier: .fast, speedDescription: "~200\u{00D7} realtime", costDescription: "$0.04/hr", contextWindow: nil, sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .googleTranscription, name: "Google Cloud", vendor: "Google",
            capability: .transcription, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "google-api-key",
            markColor: .white,
            markTextColor: Color(red: 0.1, green: 0.45, blue: 0.91),
            markLetter: "G",
            docsURL: URL(string: "https://aistudio.google.com/apikey"),
            models: [
                ModelInfo(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", tier: .fast, speedDescription: "~15\u{00D7} realtime", costDescription: "$0.10/hr", contextWindow: nil, sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
    ]

    // MARK: Summarization Providers

    static let summarizationProviders: [ProviderInfo] = [
        ProviderInfo(
            id: .localMLX, name: "On-device (MLX)", vendor: "Local \u{00B7} on-device",
            capability: .summarization, privacy: .onDevice,
            requiresAPIKey: false, keychainAccount: nil,
            markColor: Color(red: 0.89, green: 0.96, blue: 0.9),
            markTextColor: Color(red: 0.24, green: 0.47, blue: 0.28),
            markLetter: "M", docsURL: nil,
            models: [
                ModelInfo(id: "gemma-3-4b-it", displayName: "Gemma 3 4B", tier: .fast, speedDescription: nil, costDescription: nil, contextWindow: "8K", sizeGB: "2.5 GB", features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: true
        ),
        ProviderInfo(
            id: .anthropic, name: "Claude", vendor: "Anthropic",
            capability: .summarization, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "anthropic-api-key",
            markColor: Color(red: 0.85, green: 0.47, blue: 0.34),
            markTextColor: .white,
            markLetter: "C",
            docsURL: URL(string: "https://console.anthropic.com/settings/keys"),
            models: [
                ModelInfo(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", tier: .best, speedDescription: nil, costDescription: "$3 / $15 per M", contextWindow: "200K", sizeGB: nil, features: nil),
                ModelInfo(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", tier: .fast, speedDescription: nil, costDescription: "$1 / $5 per M", contextWindow: "200K", sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .openAISummarization, name: "OpenAI", vendor: "OpenAI",
            capability: .summarization, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "openai-api-key",
            markColor: Color(red: 0.05, green: 0.07, blue: 0.06),
            markTextColor: .white,
            markLetter: "O",
            docsURL: URL(string: "https://platform.openai.com/api-keys"),
            models: [
                ModelInfo(id: "gpt-4.1", displayName: "GPT-4.1", tier: .best, speedDescription: nil, costDescription: "$2 / $8 per M", contextWindow: "1M", sizeGB: nil, features: nil),
                ModelInfo(id: "gpt-4o-mini", displayName: "GPT-4o mini", tier: .fast, speedDescription: nil, costDescription: "$0.15 / $0.60 per M", contextWindow: "128K", sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .googleGemini, name: "Gemini", vendor: "Google",
            capability: .summarization, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "google-api-key",
            markColor: .white,
            markTextColor: Color(red: 0.1, green: 0.45, blue: 0.91),
            markLetter: "G",
            docsURL: URL(string: "https://aistudio.google.com/apikey"),
            models: [
                ModelInfo(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", tier: .best, speedDescription: nil, costDescription: "$1.25 / $10 per M", contextWindow: "2M", sizeGB: nil, features: nil),
                ModelInfo(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", tier: .fast, speedDescription: nil, costDescription: "$0.30 / $2.50 per M", contextWindow: "1M", sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .mistral, name: "Mistral", vendor: "Mistral AI",
            capability: .summarization, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "mistral-api-key",
            markColor: Color(red: 0.98, green: 0.32, blue: 0.06),
            markTextColor: .white,
            markLetter: "M",
            docsURL: URL(string: "https://console.mistral.ai/api-keys"),
            models: [
                ModelInfo(id: "mistral-large-latest", displayName: "Mistral Large", tier: .best, speedDescription: nil, costDescription: "$2 / $6 per M", contextWindow: "128K", sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .ollama, name: "Ollama", vendor: "Local \u{00B7} on-device",
            capability: .summarization, privacy: .onDevice,
            requiresAPIKey: false, keychainAccount: nil,
            markColor: Color(red: 0.89, green: 0.96, blue: 0.9),
            markTextColor: Color(red: 0.24, green: 0.47, blue: 0.28),
            markLetter: "O",
            docsURL: URL(string: "https://ollama.com"),
            models: [
                ModelInfo(id: "llama3.3:70b", displayName: "Llama 3.3 70B", tier: .best, speedDescription: nil, costDescription: nil, contextWindow: nil, sizeGB: "40 GB", features: nil),
                ModelInfo(id: "qwen2.5:7b", displayName: "Qwen 2.5 7B", tier: .fast, speedDescription: nil, costDescription: nil, contextWindow: nil, sizeGB: "4.7 GB", features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
        ProviderInfo(
            id: .groqSummarization, name: "Groq", vendor: "Groq",
            capability: .summarization, privacy: .cloud,
            requiresAPIKey: true, keychainAccount: "groq-api-key",
            markColor: Color(red: 0.96, green: 0.31, blue: 0.21),
            markTextColor: .white,
            markLetter: "G",
            docsURL: URL(string: "https://console.groq.com/keys"),
            models: [
                ModelInfo(id: "llama-3.3-70b-versatile", displayName: "Llama 3.3 70B", tier: .best, speedDescription: nil, costDescription: "$0.59 / $0.79 per M", contextWindow: "128K", sizeGB: nil, features: nil),
            ],
            supportsBuiltInDiarization: false, isDefault: false
        ),
    ]

    static let all: [ProviderInfo] = transcriptionProviders + summarizationProviders

    /// Providers that share the same keychain account
    static let sharedKeychainAccounts: [String: [ProviderID]] = [
        "openai-api-key": [.openAIWhisper, .openAISummarization],
        "google-api-key": [.googleTranscription, .googleGemini],
        "groq-api-key": [.groqTranscription, .groqSummarization],
    ]

    static func provider(for id: ProviderID) -> ProviderInfo? {
        all.first { $0.id == id }
    }

    static func providers(for capability: ProviderCapability) -> [ProviderInfo] {
        switch capability {
        case .transcription: return transcriptionProviders
        case .summarization: return summarizationProviders
        }
    }
}
