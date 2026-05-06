import SwiftUI

struct SummaryModelTag: View {
    let providerID: ProviderID
    let modelID: String

    var body: some View {
        HStack(spacing: 7) {
            MiniProviderMark(providerID: providerID, size: 18)
            Text(displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    private var displayName: String {
        guard let info = ProviderCatalog.provider(for: providerID) else { return modelID }
        return info.models.first { $0.id == modelID }?.displayName ?? modelID
    }
}
