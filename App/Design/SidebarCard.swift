import SwiftUI

/// The cards above the sidebar's footer, the media player and the update reminder: they come up from the footer and
/// go back into it, and close from a button that shows under the pointer.
extension BrowserDesign {
    static let cardSpring = Animation.spring(duration: 0.45, bounce: 0.28)
}

extension BrowserDesign.Typography {
    static let cardTitle = Font.system(size: 11.5, weight: .semibold)
    static let cardSubtitle = Font.system(size: 10.5, weight: .medium)
}

extension AnyTransition {
    static var sidebarCard: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.9, anchor: .bottom)).combined(with: .opacity),
                    removal: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }
}

/// Overlaid on a card's top trailing corner while the pointer is over it.
struct CardCloseButton: View {
    let label: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 18)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}
