import BrowserCore
import SwiftUI

/// The spaces in the sidebar's footer, small and quiet: the space shown has its icon and name on a faint pill, the
/// others are small grey icons that take their color back under the pointer. The pill slides from space to space and
/// the name fades in. Every space stays on screen while it can: the name gives way first, cut short, the tooltip giving
/// it whole; past that the spaces scroll, the shown one kept in the middle. Tabs dragged onto a space go to it
/// (`SpaceDropTarget`).
struct SpaceBar: View {
    static let height: CGFloat = 18
    /// The width of a space not shown.
    static let iconSize: CGFloat = 15
    /// The icon itself: an emoji, or its color's dot.
    static let glyphSize: CGFloat = 10
    static let nameFont = Font.system(size: 10, weight: .medium)
    /// Spaces not shown, until the pointer or a dragged tab is over them.
    static let otherOpacity: Double = 0.4
    /// A long name stops here; the tooltip and the space's settings give it whole.
    static let maximumNameWidth: CGFloat = 80
    /// The pill's inner margin, and the gap between its icon and name.
    static let capsulePadding: CGFloat = 6
    static let nameSpacing: CGFloat = 3
    /// The narrowest the shown space gets before the spaces scroll instead: its icon and a few letters.
    private static let minimumCapsuleWidth: CGFloat = 50
    /// Quick and without bounce: the pill is there by the time the page has slid.
    private static let motion = Animation.spring(duration: 0.22, bounce: 0)

    let browser: BrowserModel
    @State private var targetedSpaceID: UUID?
    @State private var hoveredSpaceID: UUID?
    @State private var width: CGFloat = 0
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let selectedID = browser.window.selectedSpaceID
        let others = CGFloat(max(0, browser.session.spaces.count - 1))
        Group {
            if width == 0 || others * Self.iconSize + Self.minimumCapsuleWidth <= width {
                row(selectedID)
            } else {
                ScrollView(.horizontal) { row(selectedID).scrollTargetLayout() }
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: Binding(get: { selectedID }, set: { _ in }), anchor: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private func row(_ selectedID: UUID?) -> some View {
        HStack(spacing: 0) {
            ForEach(browser.session.spaces) { space in item(space, selected: space.id == selectedID) }
        }
        .backgroundPreferenceValue(SelectedSpaceBounds.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let frame = proxy[anchor]
                    Capsule()
                        .fill(palette.fill)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .animation(reduceMotion ? nil : Self.motion, value: selectedID)
    }

    private func item(_ space: BrowserSpace, selected: Bool) -> some View {
        let targeted = targetedSpaceID == space.id
        let lit = selected || targeted || hoveredSpaceID == space.id
        return Button { browser.switchSpace(space.id) } label: {
            HStack(spacing: Self.nameSpacing) {
                SpaceIcon(space: space, size: Self.glyphSize)
                    .grayscale(lit ? 0 : 1)
                    .opacity(lit ? 1 : Self.otherOpacity)
                if selected {
                    let name = Text(verbatim: space.name).font(Self.nameFont).foregroundStyle(palette.ink).lineLimit(1)
                    // Its own width when it fits, so the pill hugs it; cut short within what is left otherwise.
                    ViewThatFits(in: .horizontal) {
                        name.fixedSize()
                        name.frame(maxWidth: Self.maximumNameWidth, alignment: .leading)
                    }
                    .layoutPriority(-1)
                        // The name leaving goes at once: fading, it would no longer hold its room and overlap the icons.
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
            .padding(.horizontal, selected ? Self.capsulePadding : 0)
            .frame(minWidth: Self.iconSize)
            .frame(height: Self.height)
            .anchorPreference(key: SelectedSpaceBounds.self, value: .bounds) { selected ? $0 : nil }
            .background {
                if targeted, !selected { Capsule().fill(space.color.tint.opacity(0.22)) }
            }
            .animation(reduceMotion ? nil : BrowserDesign.hover, value: lit)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredSpaceID = space.id } else if hoveredSpaceID == space.id { hoveredSpaceID = nil }
        }
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
        .iconContextMenu {
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

/// Where the selected space sits in the switcher, for its one capsule to follow.
private struct SelectedSpaceBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
