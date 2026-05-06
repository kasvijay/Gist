import SwiftUI

struct ModelsSettingsSheet: View {
    @EnvironmentObject var registry: ProviderRegistry
    @Environment(\.dismiss) private var dismiss

    var initialTab: ProviderCapability = .transcription
    @State private var activeTab: ProviderCapability = .transcription
    @State private var selectedProviderID: ProviderID?
    @State private var showAPIKeyDrawer: ProviderInfo?

    private var providers: [ProviderInfo] {
        ProviderCatalog.providers(for: activeTab)
    }

    private var selectedProvider: ProviderInfo? {
        guard let id = selectedProviderID else { return providers.first }
        return ProviderCatalog.provider(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings \u{00B7} Models")
                        .font(.system(size: 16, weight: .bold))
                    Text("Choose how Gist transcribes audio and writes summaries.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Tabs
            HStack(spacing: 4) {
                tabButton("Transcription", icon: "waveform", tab: .transcription)
                tabButton("Summary & insights", icon: "sparkles", tab: .summarization)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Divider()

            // Body
            HStack(spacing: 0) {
                // Left: Provider list
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("PROVIDER")
                                .font(.system(size: 11.5, weight: .semibold))
                                .tracking(0.06 * 11.5)
                                .foregroundStyle(.secondary)
                            Text("Pick one default.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.bottom, 12)

                        ForEach(providers) { provider in
                            providerRow(provider)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: Model selection
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let provider = selectedProvider {
                            modelPanel(for: provider)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)
                .background(Color(.controlBackgroundColor).opacity(0.3))
            }

            Divider()

            // Footer
            HStack(spacing: 10) {
                Text("Changes take effect on the next recording.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Save defaults") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 920, height: 640)
        .overlay {
            if let provider = showAPIKeyDrawer {
                APIKeyDrawer(
                    provider: provider,
                    onClose: { showAPIKeyDrawer = nil },
                    onSave: { key in
                        try? registry.saveAPIKey(key, for: provider.id)
                    }
                )
            }
        }
        .onAppear {
            activeTab = initialTab
            selectedProviderID = activeTab == .transcription
                ? registry.defaults.transcriptionProviderID
                : registry.defaults.summarizationProviderID
        }
        .onChange(of: activeTab) { _, _ in
            selectedProviderID = activeTab == .transcription
                ? registry.defaults.transcriptionProviderID
                : registry.defaults.summarizationProviderID
        }
    }

    // MARK: - Tab Button

    private func tabButton(_ label: String, icon: String, tab: ProviderCapability) -> some View {
        Button {
            activeTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(activeTab == tab ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if activeTab == tab {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Provider Row

    private func providerRow(_ provider: ProviderInfo) -> some View {
        let isSelected = selectedProviderID == provider.id
            || (selectedProviderID == nil && provider.isDefault)
        let isDefault = activeTab == .transcription
            ? registry.defaults.transcriptionProviderID == provider.id
            : registry.defaults.summarizationProviderID == provider.id

        return Button {
            selectedProviderID = provider.id
            if activeTab == .transcription {
                registry.defaults.transcriptionProviderID = provider.id
                registry.defaults.transcriptionModelID = provider.models.first?.id ?? ""
            } else {
                registry.defaults.summarizationProviderID = provider.id
                registry.defaults.summarizationModelID = provider.models.first?.id ?? ""
            }
        } label: {
            HStack(spacing: 12) {
                // Radio
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: isSelected ? 5 : 1.5)
                    .frame(width: 18, height: 18)

                ProviderMarkView(provider: provider, size: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(provider.name)
                            .font(.system(size: 14, weight: .semibold))
                        privacyBadge(provider.privacy)
                        if isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(provider.vendor)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Circle().fill(Color.secondary.opacity(0.3)).frame(width: 2, height: 2)
                        Text("\(provider.models.count) model\(provider.models.count != 1 ? "s" : "")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if provider.requiresAPIKey {
                    connectionBadge(registry.isConnected(provider.id))
                }

                Button(registry.isConnected(provider.id) ? "Manage" : "Connect") {
                    showAPIKeyDrawer = provider
                }
                .font(.system(size: 11.5, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(.controlBackgroundColor) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    // MARK: - Model Panel

    @ViewBuilder
    private func modelPanel(for provider: ProviderInfo) -> some View {
        Text("MODEL \u{2014} \(provider.name)")
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.06 * 11.5)
            .foregroundStyle(.secondary)
            .padding(.bottom, 12)

        if provider.requiresAPIKey && !registry.isConnected(provider.id) {
            // Not configured state
            VStack(spacing: 14) {
                Text("Connect \(provider.name) to see models")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add your API key \u{2014} stored locally in macOS Keychain.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Add API key") {
                    showAPIKeyDrawer = provider
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundStyle(Color.primary.opacity(0.14))
            )
        } else {
            // Model options
            ForEach(provider.models) { model in
                modelOption(model, provider: provider)
            }
        }

        // Behavior toggles
        VStack(alignment: .leading, spacing: 0) {
            Text("Behavior")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            Toggle("Allow per-session model override", isOn: $registry.defaults.allowPerSessionOverride)
                .font(.system(size: 12.5))
                .padding(.vertical, 4)

            if activeTab == .transcription {
                Toggle("Fall back to local model if cloud fails", isOn: $registry.defaults.fallbackToLocalOnCloudFailure)
                    .font(.system(size: 12.5))
                    .padding(.vertical, 4)
            }

            if activeTab == .summarization {
                Toggle("Send only redacted transcript to summary model", isOn: $registry.defaults.sendOnlyRedactedTranscript)
                    .font(.system(size: 12.5))
                    .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
        .padding(.top, 18)

        // Active configuration footer
        activeConfigFooter
            .padding(.top, 14)
    }

    private func modelOption(_ model: ModelInfo, provider: ProviderInfo) -> some View {
        let currentModelID = activeTab == .transcription
            ? registry.defaults.transcriptionModelID
            : registry.defaults.summarizationModelID
        let isSelected = model.id == currentModelID && selectedProviderID == provider.id

        return Button {
            if activeTab == .transcription {
                registry.defaults.transcriptionModelID = model.id
            } else {
                registry.defaults.summarizationModelID = model.id
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: isSelected ? 4 : 1.5)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        tierChip(model.tier)
                    }
                    HStack(spacing: 10) {
                        if let speed = model.speedDescription {
                            Label(speed, systemImage: "bolt.fill")
                        }
                        if let cost = model.costDescription {
                            Label(cost, systemImage: "dollarsign.circle")
                        }
                        if let ctx = model.contextWindow {
                            Label("\(ctx) ctx", systemImage: "rectangle.stack")
                        }
                        if let size = model.sizeGB {
                            Label(size, systemImage: "arrow.down.circle")
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
                    .overlay(
                        isSelected ? RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1) : nil
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var activeConfigFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active configuration")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                let transName = ProviderCatalog.provider(for: registry.defaults.transcriptionProviderID)?.name ?? "Unknown"
                Text("\(transName) \u{00B7} \(registry.defaults.transcriptionModelID)")
                    .font(.system(size: 12, design: .monospaced))
            }
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                let sumName = ProviderCatalog.provider(for: registry.defaults.summarizationProviderID)?.name ?? "Unknown"
                Text("\(sumName) \u{00B7} \(registry.defaults.summarizationModelID)")
                    .font(.system(size: 12, design: .monospaced))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Helper Views

    private func privacyBadge(_ privacy: PrivacyLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(privacy == .onDevice ? Color.green : Color.accentColor)
                .frame(width: 5, height: 5)
            Text(privacy == .onDevice ? "ON-DEVICE" : "CLOUD")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.04 * 10.5)
        }
        .foregroundStyle(privacy == .onDevice ? Color.green : Color.accentColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(privacy == .onDevice ? Color.green.opacity(0.1) : Color.accentColor.opacity(0.1))
        )
    }

    private func connectionBadge(_ connected: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(connected ? "Connected" : "API key needed")
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(connected ? Color.green : Color.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(connected ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
        )
    }

    private func tierChip(_ tier: ModelTier) -> some View {
        Text(tier.rawValue)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(tierColor(tier).opacity(0.1))
            )
            .foregroundStyle(tierColor(tier))
    }

    private func tierColor(_ tier: ModelTier) -> Color {
        switch tier {
        case .best: return .orange
        case .balanced: return .secondary
        case .fast: return .blue
        }
    }
}
