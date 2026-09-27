import BrowserCore
import SwiftUI

/// A group of favorites: a header that opens and closes it, then its rows, indented.
struct TabGroupSection: View {
    private static let indent: CGFloat = 12

    let browser: BrowserModel
    let group: TabGroup
    let tabs: [BrowserTab]
    let selectedTabID: UUID?
    let lifted: UUID?
    let selection: Namespace.ID
    let layout: TabDropLayout

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
            header.dropFrame(.groupHeader(group.id), in: layout)
            if !group.isCollapsed {
                ForEach(tabs) { tab in
                    TabRow(browser: browser, tab: tab, selected: selectedTabID == tab.id, lifted: lifted == tab.id, selection: selection, layout: layout)
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
            Button { browser.setGroupCollapsed(group.id, !group.isCollapsed) } label: {
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
            .accessibilityLabel(Text(verbatim: group.name))
            .accessibilityIdentifier("sidebar.group")
            .contextMenu {
                Button("Rename…", systemImage: "pencil") { browser.window.renaming = .group(group.id) }
                Button("Ungroup", systemImage: "folder.badge.minus") { browser.removeGroup(group.id) }
            }
        }
    }

    private func label(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: BrowserDesign.rowInset) {
            Image(systemName: "folder")
                .font(BrowserDesign.Typography.chrome)
                .foregroundStyle(.secondary)
                .frame(width: BrowserDesign.rowIconWidth)
            content()
        }
        .padding(.leading, BrowserDesign.rowInset)
        .frame(height: BrowserDesign.tabRowHeight)
        .contentShape(Rectangle())
    }
}
