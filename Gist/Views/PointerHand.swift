import AppKit
import SwiftUI

extension View {
    /// Show the macOS pointing-hand cursor while the pointer is over this view.
    /// Use on custom-styled buttons and tap-gesture surfaces where the default
    /// arrow cursor would otherwise leave the affordance ambiguous.
    func pointerHand() -> some View {
        modifier(PointerHandModifier())
    }
}

private struct PointerHandModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content.onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
