import SwiftUI

struct ProviderMarkView: View {
    let provider: ProviderInfo
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27)
                .fill(provider.markColor)
                .overlay(
                    provider.id == .googleTranscription || provider.id == .googleGemini
                    ? RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    : nil
                )
            Text(provider.markLetter)
                .font(.system(size: size * 0.43, weight: .bold))
                .foregroundStyle(provider.markTextColor)
        }
        .frame(width: size, height: size)
    }
}

struct MiniProviderMark: View {
    let providerID: ProviderID
    var size: CGFloat = 18

    var body: some View {
        if let info = ProviderCatalog.provider(for: providerID) {
            ProviderMarkView(provider: info, size: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.27)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: size, height: size)
        }
    }
}
