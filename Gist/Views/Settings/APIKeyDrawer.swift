import SwiftUI

struct APIKeyDrawer: View {
    let provider: ProviderInfo
    let onClose: () -> Void
    let onSave: (String) -> Void

    @State private var apiKey = ""
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, testing, success(String), error(String)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    ProviderMarkView(provider: provider, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect to \(provider.name)")
                            .font(.system(size: 14.5, weight: .semibold))
                        Text(provider.vendor)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    // API Key field
                    Text("API key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)

                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        SecureField("sk-...", text: $apiKey)
                            .font(.system(size: 13, design: .monospaced))
                            .textFieldStyle(.plain)
                        Text("\(apiKey.count) chars")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(.controlBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
                    )

                    // Keychain notice
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Your key is stored in ") +
                            Text("macOS Keychain").fontWeight(.medium) +
                            Text(". Gist never sends it to our servers.")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)

                        Spacer()

                        if let url = provider.docsURL {
                            Link("Get a key \u{2192}", destination: url)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(.controlBackgroundColor).opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    )
                    .padding(.top, 10)

                    // Test result
                    if testState != .idle {
                        testResultView
                            .padding(.top, 12)
                    }
                }
                .padding(20)

                Divider()

                // Footer
                HStack(spacing: 10) {
                    Button("Test connection") {
                        testConnection()
                    }
                    .disabled(apiKey.isEmpty)
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Cancel") { onClose() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                    Button("Save & connect") {
                        onSave(apiKey)
                        onClose()
                    }
                    .disabled(apiKey.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .frame(width: 480)
            .background(Color(.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.3), radius: 32, y: 12)
        }
    }

    @ViewBuilder
    private var testResultView: some View {
        switch testState {
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing connection...")
                    .font(.system(size: 12.5))
            }
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))

        case .success(let msg):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(msg)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(red: 0.24, green: 0.47, blue: 0.28))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.green.opacity(0.08)))

        case .error(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.red)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.red.opacity(0.08)))

        case .idle:
            EmptyView()
        }
    }

    private func testConnection() {
        testState = .testing
        Task {
            do {
                let success = try await testProviderConnection()
                testState = success
                    ? .success("Connection verified.")
                    : .error("Could not authenticate. Check the key and try again.")
            } catch {
                testState = .error(error.localizedDescription)
            }
        }
    }

    private func testProviderConnection() async throws -> Bool {
        guard let account = provider.keychainAccount else { return false }

        // Temporarily save the key for testing
        try KeychainService.shared.saveKey(apiKey, for: account)

        let testURL: URL
        let headers: [String: String]

        switch provider.id {
        case .openAIWhisper, .openAISummarization:
            testURL = URL(string: "https://api.openai.com/v1/models")!
            headers = ["Authorization": "Bearer \(apiKey)"]
        case .anthropic:
            testURL = URL(string: "https://api.anthropic.com/v1/models")!
            headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        case .deepgram:
            testURL = URL(string: "https://api.deepgram.com/v1/projects")!
            headers = ["Authorization": "Token \(apiKey)"]
        case .assemblyAI:
            testURL = URL(string: "https://api.assemblyai.com/v2/transcript?limit=1")!
            headers = ["Authorization": apiKey]
        case .groqTranscription, .groqSummarization:
            testURL = URL(string: "https://api.groq.com/openai/v1/models")!
            headers = ["Authorization": "Bearer \(apiKey)"]
        case .googleTranscription, .googleGemini:
            testURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
            headers = [:]
        case .mistral:
            testURL = URL(string: "https://api.mistral.ai/v1/models")!
            headers = ["Authorization": "Bearer \(apiKey)"]
        default:
            return false
        }

        return try await CloudHTTPClient.shared.testConnection(url: testURL, headers: headers)
    }
}
