import SwiftUI

/// Floating find bar shown at the top of the session detail content. Search field +
/// match count + previous/next + close. Keyboard: Return = next, Shift+Return =
/// previous, Esc = close.
struct FindBar: View {
    @ObservedObject var find: FindController
    @FocusState.Binding var focused: Bool
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Find in this view", text: $find.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 200)
                .focused($focused)
                .onKeyPress { press in
                    // Return = next, Shift+Return = previous, Esc = close. Everything
                    // else is ignored so normal typing flows into the field.
                    switch press.key {
                    case .return:
                        if press.modifiers.contains(.shift) { onPrevious() } else { onNext() }
                        return .handled
                    case .escape:
                        onClose()
                        return .handled
                    default:
                        return .ignored
                    }
                }

            Text(countLabel)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, alignment: .trailing)

            Divider().frame(height: 16)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(!find.hasMatches)
            .help("Previous match (Shift+Return)")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(!find.hasMatches)
            .help("Next match (Return)")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var countLabel: String {
        if find.query.isEmpty { return "" }
        if !find.hasMatches { return "No results" }
        return "\(find.currentIndex + 1) of \(find.matchCount)"
    }
}
