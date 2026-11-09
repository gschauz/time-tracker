import AppKit
import SwiftUI

extension View {
    func clickCursor() -> some View { modifier(ClickCursorModifier()) }
}

private struct ClickCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var ownsCursor = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    guard isEnabled else { releaseCursor(); return }
                    if !ownsCursor {
                        NSCursor.pointingHand.push()
                        ownsCursor = true
                    }
                    // Reapply while moving because the hosting view can reset the cursor.
                    NSCursor.pointingHand.set()
                case .ended:
                    releaseCursor()
                }
            }
            .onChange(of: isEnabled) { enabled in
                if !enabled { releaseCursor() }
            }
            .onDisappear { releaseCursor() }
    }

    private func releaseCursor() {
        guard ownsCursor else { return }
        ownsCursor = false
        NSCursor.pop()
    }
}
