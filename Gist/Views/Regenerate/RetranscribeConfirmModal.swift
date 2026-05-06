import SwiftUI

struct RetranscribeConfirmModal: View {
    let sessionName: String
    let currentProviderID: ProviderID
    let currentModelID: String
    let onConfirm: (_ providerID: ProviderID, _ modelID: String, _ setAsDefault: Bool) -> Void
    let onClose: () -> Void

    @State private var selectedProviderID: ProviderID
    @State private var selectedModelID: String
    @State private var setAsDefault = false
    @State private var showModelPicker = false
    @State private var searchQuery = ""

    init(
        sessionName: String,
        currentProviderID: ProviderID,
        currentModelID: String,
        onConfirm: @escaping (ProviderID, String, Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.sessionName = sessionName
        self.currentProviderID = currentProviderID
        self.currentModelID = currentModelID
        self.onConfirm = onConfirm
        self.onClose = onClose
        self._selectedProviderID = State(initialValue: currentProviderID)
        self._selectedModelID = State(initialValue: currentModelID)
    }

    private var selectedInfo: (provider: ProviderInfo, model: ModelInfo)? {
        guard let p = ProviderCatalog.provider(for: selectedProviderID),
              let m = p.models.first(where: { $0.id == selectedModelID }) ?? p.models.first else { return nil }
        return (p, m)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.1))
                        Image(systemName: "waveform")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 36, height: 36)
                    .padding(.bottom, 14)

                    Text("Re-transcribe?")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.bottom, 8)

                    Group {
                        Text("This replaces the current transcript for ") +
                        Text(sessionName).fontWeight(.medium) +
                        Text(". The audio file is unchanged.")
                    }
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)

                // Model selection
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("USE MODEL")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.08 * 11)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                        if let info = selectedInfo {
                            Button { showModelPicker.toggle() } label: {
                                HStack(spacing: 12) {
                                    ProviderMarkView(provider: info.provider, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(info.model.displayName)
                                                .font(.system(size: 14, weight: .semibold))
                                            if selectedModelID != currentModelID || selectedProviderID != currentProviderID {
                                                Text("NEW")
                                                    .font(.system(size: 9.5, weight: .semibold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .foregroundStyle(Color.accentColor)
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                            }
                                        }
                                        if let speed = info.model.speedDescription {
                                            Text(speed)
                                                .font(.system(size: 11.5, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(showModelPicker ? "Collapse" : "Change")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color(.controlBackgroundColor))
                                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                                        )
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.controlBackgroundColor).opacity(0.5))
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showModelPicker {
                            inlineModelPicker
                        }

                        // Set as default toggle
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: $setAsDefault)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Set as default for future recordings")
                                    .font(.system(size: 13.5, weight: .medium))
                                if let info = selectedInfo {
                                    Text("Apply \(info.model.displayName) to every new transcription, not just this one.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }

                Divider()

                // Footer
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { onClose() }
                        .buttonStyle(.bordered)
                    Button {
                        onConfirm(selectedProviderID, selectedModelID, setAsDefault)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Re-transcribe")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .frame(width: 520)
            .frame(maxHeight: 540)
            .background(Color(.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 32, y: 16)
        }
    }

    // MARK: - Inline Model Picker

    @ViewBuilder
    private var inlineModelPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Model list grouped by On-device / Cloud
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let groups = groupedModels
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        Text(group.title)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.08 * 10)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(group.items, id: \.model.id) { item in
                            let isSelected = item.model.id == selectedModelID && item.provider.id == selectedProviderID
                            let needsKey = item.provider.requiresAPIKey && !ProviderRegistry.shared.isConnected(item.provider.id)
                            Button {
                                if !needsKey {
                                    selectedProviderID = item.provider.id
                                    selectedModelID = item.model.id
                                    showModelPicker = false
                                    searchQuery = ""
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    MiniProviderMark(providerID: item.provider.id, size: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text(item.model.displayName)
                                                .font(.system(size: 13, weight: .medium))
                                            if needsKey {
                                                Text("KEY NEEDED")
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.orange.opacity(0.15))
                                                    .foregroundStyle(.orange)
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                            }
                                        }
                                        if let speed = item.model.speedDescription {
                                            Text(speed)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .font(.system(size: 14))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .opacity(needsKey ? 0.5 : 1)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 280)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    private struct ModelItem {
        let provider: ProviderInfo
        let model: ModelInfo
    }

    private struct ModelGroup {
        let title: String
        let items: [ModelItem]
    }

    private var groupedModels: [ModelGroup] {
        var allItems: [ModelItem] = []
        for p in ProviderCatalog.transcriptionProviders {
            for m in p.models {
                allItems.append(ModelItem(provider: p, model: m))
            }
        }

        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            let filtered = allItems.filter {
                $0.model.displayName.lowercased().contains(q) ||
                $0.provider.name.lowercased().contains(q)
            }
            return [ModelGroup(title: "Results", items: filtered)]
        }

        let onDevice = allItems.filter { $0.provider.privacy == .onDevice }
        let cloud = allItems.filter { $0.provider.privacy == .cloud }
        var groups: [ModelGroup] = []
        if !onDevice.isEmpty { groups.append(ModelGroup(title: "On-device", items: onDevice)) }
        if !cloud.isEmpty { groups.append(ModelGroup(title: "Cloud", items: cloud)) }
        return groups
    }
}
