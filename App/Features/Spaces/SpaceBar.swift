import BrowserCore
import SwiftUI

/// One icon per space in the sidebar's footer: its emoji, or a dot in its color. Tabs dragged onto an icon go to
/// its space (`SpaceDropTarget`).
struct SpaceBar: View {
    private static let iconSize: CGFloat = 24

    let browser: BrowserModel
    @State private var targetedSpaceID: UUID?
    @Environment(\.palette) private var palette

    var body: some View {
        // Centered while they fit; past that, the selected space scrolls into the middle.
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(browser.session.spaces) { space in icon(space, selected: space.id == browser.window.selectedSpaceID) }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollPosition(id: Binding(get: { browser.window.selectedSpaceID }, set: { _ in }), anchor: .center)
        .frame(height: Self.iconSize)
    }

    private func icon(_ space: BrowserSpace, selected: Bool) -> some View {
        let targeted = targetedSpaceID == space.id
        return Button { browser.switchSpace(space.id) } label: {
            SpaceIcon(space: space, size: 13)
                .opacity(selected || targeted ? 1 : 0.5)
                .scaleEffect(targeted ? 1.2 : 1)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(targeted ? space.color.tint.opacity(0.25) : selected ? palette.fill : .clear,
                        in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .browserAnimation(value: targeted)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .tooltip(space.name)
        .accessibilityLabel(Text(verbatim: space.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.space")
        // Behind the button, so clicks reach it; drags find the native view all the same.
        .background(SpaceDropTarget(browser: browser, space: space, targeted: Binding {
            targetedSpaceID == space.id
        } set: { targeted in
            if targeted { targetedSpaceID = space.id } else if targetedSpaceID == space.id { targetedSpaceID = nil }
        }))
        .contextMenu {
            Button("Edit Space…", systemImage: "pencil") { browser.showSettings(.space(space.id)) }
            Divider()
            Button("Move Left", systemImage: "arrow.left") { browser.reorderSpace(space.id, by: -1) }
                .disabled(browser.session.spaces.first?.id == space.id)
            Button("Move Right", systemImage: "arrow.right") { browser.reorderSpace(space.id, by: 1) }
                .disabled(browser.session.spaces.last?.id == space.id)
            Divider()
            Button("Delete Space…", systemImage: "trash", role: .destructive) { browser.present(.removeSpace(space.id)) }
                .disabled(browser.session.spaces.count <= 1)
        }
    }
}
