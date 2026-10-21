import AppKit
import BrowserCore
import SwiftUI

/// A group of favorites: a header that opens and closes it, then its rows, indented. Dragged by its header, the
/// group shows as a gap where it would land; a closed group lights up when a dragged tab would go into it. ⌘ or ⇧ on
/// the header picks the group with other groups and tabs, and resting on a closed group's header lists its tabs
/// beside it (`folderPreview`).
struct TabGroupSection: View {
    private static let indent: CGFloat = 12
    private static let paneBleed: CGFloat = 2
    private static let paneMargin: CGFloat = 4

    let browser: BrowserModel
    let group: TabGroup
    let tabs: [BrowserTab]
    let selectedTabID: UUID?
    let marked: Set<UUID>
    let lifted: Set<UUID>
    let isMarked: Bool
    let isLifted: Bool
    let isTargeted: Bool
    let selection: Namespace.ID
    let layout: TabDropLayout

    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
            header
                .opacity(isLifted ? 0 : 1)
                .background {
                    if isLifted { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(palette.fill) }
                    else if isTargeted { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(Color.accentColor.opacity(0.18)) }
                    else if isMarked { Color.clear.browserGlass(.hover, radius: BrowserDesign.Radius.control) }
                }
                .dropFrame(.groupHeader(group.id), in: layout)
            if !group.isCollapsed, !isLifted {
                ForEach(tabs) { tab in
                    TabRow(browser: browser, tab: tab, selected: selectedTabID == tab.id, marked: marked.contains(tab.id),
                           lifted: lifted.contains(tab.id), selection: selection, layout: layout)
                        .padding(.leading, Self.indent)
                }
            }
        }
        // An open folder holds its tabs on a pane of glass, just past their edges, so the selected one stands out on it.
        // The pane reaches up into the spacing above, so the header never moves as the folder opens; only the room
        // below its tabs grows, keeping it apart from a folder open after it.
        .padding(.bottom, hasPane ? Self.paneBleed + Self.paneMargin : 0)
        .background {
            if hasPane {
                Color.clear
                    .browserGlass(.container, radius: BrowserDesign.Radius.control + Self.paneBleed)
                    .padding(EdgeInsets(top: -Self.paneBleed, leading: -Self.paneBleed, bottom: Self.paneMargin, trailing: -Self.paneBleed))
                    .transition(.opacity)
            }
        }
    }

    private var hasPane: Bool { !group.isCollapsed && !isLifted && !tabs.isEmpty }

    @ViewBuilder private var header: some View {
        if browser.window.renaming == .group(group.id) {
            label {
                RenameField(name: group.name) { browser.renameGroup(group.id, to: $0) } end: { browser.window.endRenaming(.group(group.id)) }
            }
        } else {
            Button { browser.click(group, modifiers: NSEvent.modifierFlags) } label: {
                label {
                    Text(verbatim: group.name).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(BrowserDesign.Typography.glyph)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                        .padding(.trailing, BrowserDesign.rowInset)
                }
            }
            .buttonStyle(QuietButtonStyle())
            .groupDraggable(group, browser: browser)
            .folderPreview(browser: browser, groupID: group.id, enabled: group.isCollapsed && !tabs.isEmpty && browser.window.tabDrag == nil)
            .onHover { hovered = $0 }
            .accessibilityLabel(Text(verbatim: group.name))
            .accessibilityAddTraits(isMarked ? .isSelected : [])
            .accessibilityIdentifier("sidebar.group")
            .contextMenu {
                if let entries = browser.selectedEntries(for: group.id) {
                    SelectedEntriesMenu(browser: browser, entries: entries)
                } else { menu }
            }
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Rename Group…", systemImage: "pencil") { browser.window.renaming = .group(group.id) }
        Button(group.isCollapsed ? "Expand Group" : "Collapse Group", systemImage: group.isCollapsed ? "chevron.down" : "chevron.up") {
            browser.setGroupCollapsed(group.id, !group.isCollapsed)
        }
        if browser.session.spaces.count > 1 {
            MoveToSpaceMenu(browser: browser, isCurrent: { $0.groups.contains { $0.id == group.id } }) { space in
                browser.moveEntries([.group(group.id)], toSpace: space.id)
            }
        }
        Divider()
        // Its tabs stay pinned where the group was.
        Button("Ungroup", systemImage: "folder.badge.minus") { browser.removeGroup(group.id) }
    }

    private func label(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: BrowserDesign.rowInset) {
            FolderIcon(isOpen: !group.isCollapsed, isPeeking: hovered, tint: isTargeted ? Color.accentColor : .secondary)
                // A dragged tab about to go in lifts it a little.
                .scaleEffect(isTargeted ? 1.15 : 1)
                .animation(reduceMotion ? nil : BrowserDesign.motion, value: isTargeted)
                .frame(width: BrowserDesign.rowIconWidth)
            content()
        }
        .padding(.leading, BrowserDesign.rowInset)
        .frame(height: BrowserDesign.tabRowHeight)
        .contentShape(Rectangle())
    }
}
