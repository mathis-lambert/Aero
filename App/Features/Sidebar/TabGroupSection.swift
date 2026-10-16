import AppKit
import BrowserCore
import SwiftUI

/// A group of favorites: a header that opens and closes it, then its rows, indented. Dragged by its header, the
/// group shows as a gap where it would land; a closed group lights up when a dragged tab would go into it. ⌘ or ⇧ on
/// the header picks the group with other groups and tabs.
struct TabGroupSection: View {
    private static let indent: CGFloat = 12

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

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
            header
                .opacity(isLifted ? 0 : 1)
                .background {
                    if isLifted { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(palette.fill) }
                    else if isTargeted { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(Color.accentColor.opacity(0.18)) }
                    else if isMarked { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(palette.raised) }
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
    }

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
            Image(systemName: "folder")
                .font(BrowserDesign.Typography.chrome)
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: isTargeted)
                .frame(width: BrowserDesign.rowIconWidth)
            content()
        }
        .padding(.leading, BrowserDesign.rowInset)
        .frame(height: BrowserDesign.tabRowHeight)
        .contentShape(Rectangle())
    }
}
