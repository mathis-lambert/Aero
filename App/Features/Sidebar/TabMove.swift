import BrowserCore
import SwiftUI

/// Where a tab can go: a group of its space, out of its group, or another space.
enum TabMoveChoice: Identifiable, Equatable {
    case group(TabGroup)
    case ungroup
    case space(BrowserSpace)

    var id: String {
        switch self {
        case .group(let group): "group.\(group.id)"
        case .ungroup: "ungroup"
        case .space(let space): "space.\(space.id)"
        }
    }
}

extension BrowserModel {
    /// The groups of the tab's space, then “Out of Group” when it is in one.
    func groupChoices(for tab: BrowserTab) -> [TabMoveChoice] {
        let groups = session.spaces.first { $0.id == tab.spaceID }?.groups ?? []
        let isGrouped = if case .list(group: .some) = tab.place { true } else { false }
        return groups.map(TabMoveChoice.group) + (isGrouped ? [.ungroup] : [])
    }

    func isCurrent(_ choice: TabMoveChoice, for tab: BrowserTab) -> Bool {
        switch choice {
        case .group(let group): tab.place == .list(group: group.id)
        case .ungroup: false
        case .space(let space): tab.spaceID == space.id
        }
    }

    func move(_ tabID: UUID, to choice: TabMoveChoice) {
        switch choice {
        case .group(let group): moveTab(tabID, to: .list(group: group.id), before: nil)
        case .ungroup: moveTab(tabID, to: .list(group: nil), before: nil)
        case .space(let space): moveTab(tabID, toSpace: space.id)
        }
    }

    /// The profile's name, when there are several to tell spaces apart.
    func profileName(of space: BrowserSpace) -> String? {
        guard session.profiles.count > 1 else { return nil }
        return session.profiles.first { $0.id == space.profileID }?.name
    }
}

/// The same choices in the context menu and the menu bar; the command bar and shortcuts show `TabMovePrompt`.
struct MoveToGroupMenu: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        Menu("Move to Group", systemImage: BrowserCommand.moveToGroup.symbol) {
            let groups = browser.session.spaces.first { $0.id == tab.spaceID }?.groups ?? []
            ForEach(groups) { group in
                Button { browser.move(tab.id, to: .group(group)) } label: { Text(verbatim: group.name) }
                    .disabled(tab.place == .list(group: group.id))
            }
            if case .list(group: .some) = tab.place {
                Divider()
                Button("Out of Group") { browser.move(tab.id, to: .ungroup) }
            }
        }
    }
}

struct MoveToSpaceMenu: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        Menu("Move to Space", systemImage: BrowserCommand.moveToSpace.symbol) {
            let profiles = browser.session.profiles.filter { profile in browser.session.spaces.contains { $0.profileID == profile.id } }
            ForEach(profiles) { profile in
                let spaces = browser.session.spaces.filter { $0.profileID == profile.id }
                if profiles.count > 1 { Section(profile.name) { buttons(spaces) } } else { buttons(spaces) }
            }
        }
    }

    private func buttons(_ spaces: [BrowserSpace]) -> some View {
        ForEach(spaces) { space in
            Button { browser.move(tab.id, to: .space(space)) } label: { Text(verbatim: space.name) }
                .disabled(space.id == tab.spaceID)
        }
    }
}

struct TabMovePresentation: Equatable {
    enum Target { case group, space }
    let tabID: UUID
    let target: Target
}

/// Chooses a group or a space for a tab, like the control bar chooses a result: arrows move, Return moves the tab.
struct TabMovePrompt: View {
    private static let width: CGFloat = 360
    private static let rowHeight: CGFloat = 36
    private static let visibleRows = 7

    let browser: BrowserModel
    let presentation: TabMovePresentation
    @State private var selection: TabMoveChoice.ID?
    @FocusState private var focused: Bool
    @Environment(\.palette) private var palette

    private var tab: BrowserTab? { browser.session.tabs.first { $0.id == presentation.tabID } }

    private var choices: [TabMoveChoice] {
        guard let tab else { return [] }
        return presentation.target == .group ? browser.groupChoices(for: tab) : browser.session.spaces.map(TabMoveChoice.space)
    }

    private var available: [TabMoveChoice] {
        guard let tab else { return [] }
        return choices.filter { !browser.isCurrent($0, for: tab) }
    }

    var body: some View {
        Prompt(title: presentation.target == .group ? Text("Move to Group") : Text("Move to Space")) {
            VStack(alignment: .leading, spacing: 10) {
                if let tab { header(tab) }
                Divider()
                list
            }
            .frame(width: Self.width)
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: "Move") { commit() }
                .disabled(selection == nil)
                .accessibilityIdentifier("tabMove.confirm")
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            moveSelection(by: press.key == .downArrow ? 1 : -1)
            return .handled
        }
        .task {
            selection = available.first?.id
            // After the prompt took the keyboard from the page.
            await Task.yield()
            focused = true
        }
        .onChange(of: tab == nil) { _, closed in if closed { browser.dismissPrompt() } }
    }

    /// The tab being moved, so the question is never ambiguous.
    private func header(_ tab: BrowserTab) -> some View {
        HStack(spacing: 8) {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.tabIconSize) {
                Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe").foregroundStyle(palette.secondary)
            }
            .frame(width: BrowserDesign.rowIconWidth)
            Text(verbatim: tab.displayTitle).lineLimit(1).truncationMode(.middle).foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, BrowserDesign.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(choices) { choice in row(choice).id(choice.id) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: CGFloat(min(choices.count, Self.visibleRows)) * (Self.rowHeight + 2))
            .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private func row(_ choice: TabMoveChoice) -> some View {
        let isCurrent = tab.map { browser.isCurrent(choice, for: $0) } ?? false
        let selected = selection == choice.id
        return Button {
            selection = choice.id
            commit()
        } label: {
            HStack(spacing: BrowserDesign.rowInset) {
                icon(choice).frame(width: BrowserDesign.rowIconWidth)
                VStack(alignment: .leading, spacing: 1) {
                    title(choice).lineLimit(1)
                    if let detail = detail(choice) {
                        detail.font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if isCurrent { Text("Current").font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary) }
                else if selected { Keycaps(.defaultAction) }
            }
            .padding(.horizontal, BrowserDesign.rowInset)
            .frame(height: Self.rowHeight)
            .background(selected ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .contentShape(Rectangle())
            .opacity(isCurrent ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { if $0, !isCurrent { selection = choice.id } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tabMove.choice")
    }

    @ViewBuilder private func icon(_ choice: TabMoveChoice) -> some View {
        switch choice {
        case .group: Image(systemName: "folder").foregroundStyle(palette.secondary)
        case .ungroup: Image(systemName: "folder.badge.minus").foregroundStyle(palette.secondary)
        case .space(let space): SpaceIcon(space: space)
        }
    }

    private func title(_ choice: TabMoveChoice) -> Text {
        switch choice {
        case .group(let group): Text(verbatim: group.name)
        case .ungroup: Text("Out of Group")
        case .space(let space): Text(verbatim: space.name)
        }
    }

    private func detail(_ choice: TabMoveChoice) -> Text? {
        switch choice {
        case .group(let group):
            let count = browser.session.tabs.filter { $0.place == .list(group: group.id) }.count
            return Text("\(count) tabs")
        case .ungroup: return nil
        case .space(let space): return browser.profileName(of: space).map { Text(verbatim: $0) }
        }
    }

    private func moveSelection(by offset: Int) {
        let ids = available.map(\.id)
        guard !ids.isEmpty else { return }
        let index = selection.flatMap { ids.firstIndex(of: $0) }.map { ($0 + offset + ids.count) % ids.count } ?? 0
        selection = ids[index]
    }

    private func commit() {
        guard let selection, let choice = available.first(where: { $0.id == selection }) else { return }
        browser.dismissPrompt()
        // A move to another profile's space asks next, with its own prompt.
        browser.move(presentation.tabID, to: choice)
    }
}
