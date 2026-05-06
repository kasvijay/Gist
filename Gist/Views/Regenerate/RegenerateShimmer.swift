import SwiftUI

struct RegenerateShimmer: View {
    let providerID: ProviderID
    let modelID: String
    let onCancel: () -> Void

    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status banner
            HStack(spacing: 12) {
                MiniProviderMark(providerID: providerID, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text("Regenerating with \(displayName)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor.opacity(0.5))
                    }
                    Text("Reading transcript \u{00B7} drafting summary")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1))
            )
            .padding(.bottom, 28)

            // Shimmer blocks
            shimmerBlock(width: 56, height: 10)
                .padding(.bottom, 14)
            shimmerBlock(width: nil, height: 16, widthFraction: 0.92)
                .padding(.bottom, 8)
            shimmerBlock(width: nil, height: 16, widthFraction: 0.78)

            Spacer().frame(height: 36)

            shimmerBlock(width: 90, height: 11)
                .padding(.bottom, 12)
            shimmerBlock(width: nil, height: 14, widthFraction: 1.0)
                .padding(.bottom, 8)
            shimmerBlock(width: nil, height: 14, widthFraction: 0.96)
                .padding(.bottom, 8)
            shimmerBlock(width: nil, height: 14, widthFraction: 0.64)

            Spacer().frame(height: 36)

            shimmerBlock(width: 120, height: 11)
                .padding(.bottom, 16)

            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 12) {
                        shimmerBlock(width: 20, height: 20, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 6) {
                            shimmerBlock(width: nil, height: 14, widthFraction: i % 2 == 0 ? 0.82 : 0.68)
                            shimmerBlock(width: 120, height: 11)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
    }

    private func shimmerBlock(width: CGFloat? = nil, height: CGFloat, widthFraction: CGFloat = 1.0, cornerRadius: CGFloat = 6) -> some View {
        GeometryReader { geo in
            let w = width ?? geo.size.width * widthFraction
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.primary.opacity(0.04), location: 0),
                            .init(color: Color.primary.opacity(0.08), location: 0.5),
                            .init(color: Color.primary.opacity(0.04), location: 1),
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 1, y: 0),
                        endPoint: UnitPoint(x: shimmerPhase, y: 0)
                    )
                )
                .frame(width: w, height: height)
        }
        .frame(width: width, height: height)
    }

    private var displayName: String {
        guard let info = ProviderCatalog.provider(for: providerID) else { return modelID }
        return info.models.first { $0.id == modelID }?.displayName ?? modelID
    }
}
