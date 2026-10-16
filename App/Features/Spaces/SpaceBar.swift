import BrowserCore
import SwiftUI

/// The spaces in the sidebar's footer, where the space shown says who it is: a capsule in its color with its icon,
/// its name and, once there are several, its profile's. The others are smaller icons, their emoji or a dot in their
/// color. One capsule morphs from space to space, so choosing one slides it there and blends its color; the name
/// fades in from its icon. Every space stays on screen while it can: the name gives way first, cut short, the tooltip
/// giving it whole; past that the spaces scroll, the shown one kept in the middle. Tabs dragged onto a space go to it
/// (`SpaceDropTarget`).
struct SpaceBar: View {
    static let height: CGFloat = 28
    /// The width of a space not shown.
    static let iconSize: CGFloat = 18
    /// Spaces not shown are this much smaller.
    static let otherScale: CGFloat = 0.85
    /// A long name stops here; the tooltip and the space's settings give it whole.
    static let maximumNameWidth: CGFloat = 96
    /// The narrowest the shown space gets before the spaces scroll instead: its icon and a few letters.
    private static let minimumCapsuleWidth: CGFloat = 70
    /// Softer and a little longer than the shell's spring, for the capsule to travel and settle.
    private static let motion = Animation.spring(duration: 0.42, bounce: 0.16)

    let browser: BrowserModel
    @State private var targetedSpaceID: UUID?
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
                if let anchor, let space = browser.space {
                    let frame = proxy[anchor]
                    Capsule()
                        .fill(space.color.tint.opacity(0.16))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .animation(reduceMotion ? nil : Self.motion, value: selectedID)
    }

    private func item(_ space: BrowserSpace, selected: Bool) -> some View {
        let targeted = targetedSpaceID == space.id
        return Button { browser.switchSpace(space.id) } label: {
            HStack(spacing: 6) {
                SpaceIcon(space: space, size: 13)
                    .scaleEffect(selected || targeted ? 1 : Self.otherScale)
                if selected {
                    HStack(spacing: 6) {
                        Text(verbatim: space.name)
                            .font(BrowserDesign.Typography.label)
                            .foregroundStyle(palette.ink)
                        if let profile = browser.profileName(of: space) {
                            Text(verbatim: profile)
                                .font(BrowserDesign.Typography.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: Self.maximumNameWidth, alignment: .leading)
                    .layoutPriority(-1)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .opacity(selected || targeted ? 1 : 0.55)
            .padding(.horizontal, selected ? 10 : 0)
            .frame(minWidth: Self.iconSize)
            .frame(height: Self.height)
            .anchorPreference(key: SelectedSpaceBounds.self, value: .bounds) { selected ? $0 : nil }
            .background {
                if targeted, !selected { Capsule().fill(space.color.tint.opacity(0.25)) }
            }
            .animation(reduceMotion ? nil : BrowserDesign.hover, value: targeted)
            .contentShape(Capsule())
        }
        .buttonStyle(QuietButtonStyle(radius: Self.height / 2))
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

/// Where the selected space sits in the switcher, for its one capsule to follow.
private struct SelectedSpaceBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
