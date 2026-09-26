import SwiftUI

/// A shortcut drawn as keys: one cap per modifier and key, raised by a darker bottom edge.
struct Keycaps: View {
    private static let height: CGFloat = 18
    private static let edge: CGFloat = 1

    let keys: [String]
    /// On an accent fill, such as a prominent button.
    var onAccent = false
    @Environment(\.palette) private var palette

    init(_ keys: String..., onAccent: Bool = false) {
        self.keys = keys
        self.onAccent = onAccent
    }

    init(_ shortcut: KeyboardShortcut, onAccent: Bool = false) {
        keys = shortcut.keys
        self.onAccent = onAccent
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in cap(key) }
        }
    }

    private func cap(_ key: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrowserDesign.Radius.xs)
        return Text(verbatim: key)
            .font(BrowserDesign.Typography.keycap)
            .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(palette.secondary))
            .padding(.horizontal, 4)
            .frame(minWidth: Self.height, minHeight: Self.height - Self.edge)
            .background {
                ZStack {
                    shape.fill(onAccent ? .black.opacity(0.18) : palette.keycapEdge).offset(y: Self.edge)
                    shape.fill(onAccent ? .white.opacity(0.2) : palette.keycap)
                    shape.strokeBorder(onAccent ? .white.opacity(0.25) : palette.line, lineWidth: 0.5)
                }
            }
            .padding(.bottom, Self.edge)
            .accessibilityLabel(Text(verbatim: key))
            .accessibilityIdentifier("keycap")
    }
}

extension KeyboardShortcut {
    /// The keys in menu order: “⇧”, “⌘”, “T”.
    var keys: [String] {
        let modifierSymbols: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return modifierSymbols.filter { modifiers.contains($0.0) }.map(\.1) + [key.symbol]
    }
}

private extension KeyEquivalent {
    var symbol: String {
        switch self {
        case .return: "↵"
        case .escape: "esc"
        case .tab: "⇥"
        case .delete: "⌫"
        case .space: "␣"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        default: String(character).uppercased()
        }
    }
}
