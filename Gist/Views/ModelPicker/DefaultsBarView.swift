import SwiftUI

struct DefaultsBarView: View {
    @EnvironmentObject var registry: ProviderRegistry
    @State private var showModelsSheet = false

    var body: some View {
        HStack(spacing: 4) {
            defaultButton(
                label: "TRANSCRIBE",
                icon: "waveform",
                providerID: registry.defaults.transcriptionProviderID,
                modelName: modelDisplayName(registry.defaults.transcriptionModelID, provider: registry.defaults.transcriptionProviderID)
            )
            Divider().frame(height: 28)
            defaultButton(
                label: "SUMMARIZE",
                icon: "sparkles",
                providerID: registry.defaults.summarizationProviderID,
                modelName: modelDisplayName(registry.defaults.summarizationModelID, provider: registry.defaults.summarizationProviderID)
            )
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .onTapGesture {
            showModelsSheet = true
        }
        .sheet(isPresented: $showModelsSheet) {
            ModelsSettingsSheet()
        }
    }

    private func defaultButton(label: String, icon: String, providerID: ProviderID, modelName: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.06 * 9.5)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                MiniProviderMark(providerID: providerID, size: 14)
                Text(modelName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func modelDisplayName(_ modelID: String, provider: ProviderID) -> String {
        guard let info = ProviderCatalog.provider(for: provider) else { return modelID }
        return info.models.first { $0.id == modelID }?.displayName ?? modelID
    }
}
