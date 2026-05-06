import Foundation
import SwiftUI

// MARK: - Model Defaults

struct ModelDefaults: Codable {
    var transcriptionProviderID: ProviderID = .localWhisper
    var transcriptionModelID: String = "large-v3-turbo"
    var summarizationProviderID: ProviderID = .localMLX
    var summarizationModelID: String = "gemma-3-4b-it"
    var allowPerSessionOverride: Bool = true
    var fallbackToLocalOnCloudFailure: Bool = true
    var sendOnlyRedactedTranscript: Bool = false
}

// MARK: - Provider Config

struct ProviderConfig: Codable {
    var providerID: ProviderID
    var isConnected: Bool = false
    var selectedModelID: String?
    var lastTestedAt: Date?
}

// MARK: - Session Model Override

struct SessionModelOverride: Codable {
    var transcriptionProviderID: ProviderID?
    var transcriptionModelID: String?
    var summarizationProviderID: ProviderID?
    var summarizationModelID: String?
}

// MARK: - Provider Registry

@MainActor
final class ProviderRegistry: ObservableObject {
    static let shared = ProviderRegistry()

    @Published var defaults: ModelDefaults {
        didSet { saveDefaults() }
    }
    @Published var configurations: [ProviderID: ProviderConfig] {
        didSet { saveConfigurations() }
    }

    private let defaultsKey = "gist.modelDefaults"
    private let configsKey = "gist.providerConfigurations"

    init() {
        // Load saved defaults
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(ModelDefaults.self, from: data) {
            self.defaults = saved
        } else {
            self.defaults = ModelDefaults()
        }

        // Load saved configurations
        if let data = UserDefaults.standard.data(forKey: configsKey),
           let saved = try? JSONDecoder().decode([ProviderID: ProviderConfig].self, from: data) {
            self.configurations = saved
        } else {
            self.configurations = [:]
        }

        // Sync keychain state — mark providers connected if their key exists
        syncKeychainState()
    }

    // MARK: - Provider Access

    func providerInfo(for id: ProviderID) -> ProviderInfo? {
        ProviderCatalog.provider(for: id)
    }

    func isConnected(_ providerID: ProviderID) -> Bool {
        guard let info = providerInfo(for: providerID) else { return false }
        if !info.requiresAPIKey { return true }
        return configurations[providerID]?.isConnected ?? false
    }

    func apiKey(for providerID: ProviderID) -> String? {
        guard let info = providerInfo(for: providerID),
              let account = info.keychainAccount else { return nil }
        return KeychainService.shared.getKey(for: account)
    }

    // MARK: - API Key Management

    func saveAPIKey(_ key: String, for providerID: ProviderID) throws {
        guard let info = providerInfo(for: providerID),
              let account = info.keychainAccount else { return }

        try KeychainService.shared.saveKey(key, for: account)

        // Mark all providers sharing this keychain account as connected
        let sharedProviders = ProviderCatalog.sharedKeychainAccounts[account] ?? [providerID]
        for pid in sharedProviders {
            var config = configurations[pid] ?? ProviderConfig(providerID: pid)
            config.isConnected = true
            config.lastTestedAt = Date()
            configurations[pid] = config
        }
    }

    func deleteAPIKey(for providerID: ProviderID) throws {
        guard let info = providerInfo(for: providerID),
              let account = info.keychainAccount else { return }

        try KeychainService.shared.deleteKey(for: account)

        let sharedProviders = ProviderCatalog.sharedKeychainAccounts[account] ?? [providerID]
        for pid in sharedProviders {
            var config = configurations[pid] ?? ProviderConfig(providerID: pid)
            config.isConnected = false
            configurations[pid] = config
        }
    }

    func markConnected(_ providerID: ProviderID) {
        var config = configurations[providerID] ?? ProviderConfig(providerID: providerID)
        config.isConnected = true
        config.lastTestedAt = Date()
        configurations[providerID] = config
    }

    // MARK: - Active Provider Resolution

    func activeTranscriptionProviderID(override: SessionModelOverride? = nil) -> (ProviderID, String) {
        if defaults.allowPerSessionOverride,
           let ov = override,
           let pid = ov.transcriptionProviderID,
           let mid = ov.transcriptionModelID,
           isConnected(pid) {
            return (pid, mid)
        }
        return (defaults.transcriptionProviderID, defaults.transcriptionModelID)
    }

    func activeSummarizationProviderID(override: SessionModelOverride? = nil) -> (ProviderID, String) {
        if defaults.allowPerSessionOverride,
           let ov = override,
           let pid = ov.summarizationProviderID,
           let mid = ov.summarizationModelID,
           isConnected(pid) {
            return (pid, mid)
        }
        return (defaults.summarizationProviderID, defaults.summarizationModelID)
    }

    // MARK: - Persistence

    private func saveDefaults() {
        if let data = try? JSONEncoder().encode(defaults) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: configsKey)
        }
    }

    private func syncKeychainState() {
        for provider in ProviderCatalog.all where provider.requiresAPIKey {
            guard let account = provider.keychainAccount else { continue }
            let hasKey = KeychainService.shared.hasKey(for: account)
            if hasKey {
                var config = configurations[provider.id] ?? ProviderConfig(providerID: provider.id)
                config.isConnected = true
                configurations[provider.id] = config
            }
        }
    }
}
