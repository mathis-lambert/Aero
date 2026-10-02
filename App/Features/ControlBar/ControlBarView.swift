import AppKit
import BrowserCore
import SwiftUI

/// The browser's only address, search and command field, on the New Tab page, which keeps its model
/// and shelf, and over the selected tab. See docs/BROWSING.md.
struct ControlBarView: View {
    static let fieldHeight: CGFloat = 44
    static let width: CGFloat = 600
    /// The smallest space kept on each side in narrow windows.
    static let margin: CGFloat = 48
    private static let fieldInset: CGFloat = 16
    /// Where the field's text starts, from the bar's leading edge.
    static let textLeading = fieldInset + BrowserDesign.rowIconWidth + BrowserDesign.rowInset
    private static let rowHeight = BrowserDesign.tabRowHeight
    private static let rowSpacing: CGFloat = 2
    private static let listPadding: CGFloat = 8
    /// Whole rows only, so the list never ends on half a row.
    private static let visibleRows = 8

    let browser: BrowserModel
    /// When the bar's light crosses it after it appears: on the New Tab page, as the gust reaches it.
    let lightDelay: TimeInterval
    @State private var model: ControlBarModel
    /// On the New Tab page: what the arrow keys reach while the field is empty.
    private let shelf: NewTabShelf?
    @FocusState private var focused: Bool
    @State private var textSelection: TextSelection?
    /// The pointer only selects rows once it moves, so a bar opening under a still pointer keeps
    /// its first row, which Return opens.
    @State private var pointer: CGPoint?
    @State private var pointerMoved = false
    @Environment(\.palette) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    init(browser: BrowserModel, presentation: ControlBarPresentation, lightDelay: TimeInterval = 0) {
        self.init(browser: browser, model: ControlBarModel(browser: browser, presentation: presentation), shelf: nil, lightDelay: lightDelay)
    }

    /// The New Tab page keeps `model`, whose text decides whether its shelf shows.
    init(browser: BrowserModel, model: ControlBarModel, shelf: NewTabShelf?, lightDelay: TimeInterval = 0) {
        self.browser = browser
        self.lightDelay = lightDelay
        self.shelf = shelf
        _model = State(initialValue: model)
    }

    var body: some View {
        // Computed once per update: every row reads the same list.
        let items = model.items
        let selected = model.selectedIndex(in: items)
        VStack(spacing: 0) {
            field
            if !items.isEmpty {
                Divider()
                results(items, selected: selected)
            }
        }
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        .controlBarGlow(accent: browser.accent.light(in: palette.scheme), cornerRadius: BrowserDesign.Radius.card, delay: lightDelay)
        .panelShadow()
        .frame(maxWidth: Self.width)
        .padding(.horizontal, Self.margin)
        .task(id: model.text) { await model.refresh() }
        .task(id: browser.window.inputFocusRequest) {
            // Once the field is in the window: focus asked for earlier is lost.
            await Task.yield()
            focused = true
            // Typing replaces what the bar starts with, such as the page's address after ⌘L.
            textSelection = TextSelection(range: model.text.startIndex..<model.text.endIndex)
        }
    }

    private var field: some View {
        HStack(spacing: BrowserDesign.rowInset) {
            Image(systemName: "magnifyingglass")
                .font(BrowserDesign.Typography.field)
                .foregroundStyle(.secondary)
                .frame(width: BrowserDesign.rowIconWidth)
                .accessibilityHidden(true)
            TextField(model.isOverlay ? "Search, enter an address, or find a command" : "Search or enter an address", text: $model.text, selection: $textSelection)
                .textFieldStyle(.plain)
                .font(BrowserDesign.Typography.field)
                .focused($focused)
                .onSubmit {
                    if model.text.isEmpty, let shelf, shelf.activateFocus() { return }
                    model.activateSelection()
                }
                .onKeyPress(.downArrow) { shelfKey(.down) ?? moveSelection(by: 1) }
                .onKeyPress(.upArrow) { shelfKey(.up) ?? moveSelection(by: -1) }
                .onKeyPress(.leftArrow) { shelfKey(layoutDirection == .rightToLeft ? .next : .previous, onlyInside: true) ?? .ignored }
                .onKeyPress(.rightArrow) { shelfKey(layoutDirection == .rightToLeft ? .previous : .next, onlyInside: true) ?? .ignored }
                .onExitCommand {
                    if let shelf, shelf.focus != nil { shelf.clearFocus() }
                    else if model.isOverlay { browser.window.controlBar = nil } else { model.text = "" }
                }
                .accessibilityIdentifier("controlBar.input")
            if model.isOverlay { Keycaps(.cancelAction) }
        }
        .padding(.horizontal, Self.fieldInset)
        .frame(height: Self.fieldHeight)
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        model.moveSelection(by: offset)
        return .handled
    }

    /// Moves on the shelf while the field is empty; `nil` leaves the key to the field. Left and right
    /// keep moving the insertion point until the arrows are on the shelf, and composition keeps every key.
    private func shelfKey(_ move: ShelfMove, onlyInside: Bool = false) -> KeyPress.Result? {
        guard let shelf, model.text.isEmpty, !onlyInside || shelf.focus != nil, !isComposing else { return nil }
        shelf.move(move)
        return .handled
    }

    /// An input method's unconfirmed text, which the field's text does not include yet.
    private var isComposing: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private func results(_ items: [ControlBarItem], selected: Int?) -> some View {
        ScrollView {
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    row(item, index: index, selected: index == selected)
                }
            }
            .padding(Self.listPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: CGFloat(min(items.count, Self.visibleRows)) * (Self.rowHeight + Self.rowSpacing) - Self.rowSpacing + 2 * Self.listPadding)
    }

    private func row(_ item: ControlBarItem, index: Int, selected: Bool) -> some View {
        let subtitle = item.subtitle(engine: browser.preferences.searchEngine)
        return Button { model.activate(item) } label: {
            HStack(spacing: BrowserDesign.rowInset) {
                icon(for: item).frame(width: BrowserDesign.rowIconWidth)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.title).lineLimit(1)
                    if let subtitle {
                        Text(verbatim: subtitle).font(BrowserDesign.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let shortcut = item.shortcut(using: browser.shortcuts) { Keycaps(shortcut) }
                else if selected { Keycaps(.defaultAction) }
            }
            .padding(.horizontal, BrowserDesign.rowInset)
            .frame(height: Self.rowHeight)
            .background(selected ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover(coordinateSpace: .global) { phase in
            guard case .active(let location) = phase else { return }
            if !pointerMoved {
                if let pointer, pointer != location { pointerMoved = true } else { pointer = location }
            }
            if pointerMoved, !selected { model.select(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityValue(Text(verbatim: subtitle ?? ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("controlBar.item")
    }

    @ViewBuilder private func icon(for item: ControlBarItem) -> some View {
        if let url = item.site, let profileID = browser.profile?.id {
            FaviconView(cache: browser.favicons, key: FaviconKey(profileID: profileID, url: url), size: BrowserDesign.tabIconSize) {
                Image(systemName: item.symbol).foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: item.symbol).foregroundStyle(.secondary)
        }
    }
}

private extension ControlBarItem {
    var title: String {
        switch self {
        case .open(let url): InternalPage(url: url)?.title ?? url.absoluteString.replacing(/^https?:\/\//, with: "")
        case .search(let query), .suggestion(let query): query
        case .tab(let tab): tab.displayTitle
        case .history(let entry): entry.displayTitle
        case .command(let command): command.title
        }
    }

    func subtitle(engine: SearchEngine) -> String? {
        switch self {
        case .open: String(localized: "Open")
        case .search: String(localized: "Search with \(engine.name)")
        case .suggestion: nil
        case .tab: String(localized: "Switch to tab")
        case .history(let entry): entry.url.siteName
        case .command: nil
        }
    }

    var symbol: String {
        switch self {
        case .open(let url): InternalPage(url: url)?.symbol ?? "globe"
        case .search, .suggestion: "magnifyingglass"
        case .tab: "square.on.square"
        case .history: "clock"
        case .command(let command): command.symbol
        }
    }

    /// The website whose icon the row shows.
    var site: URL? {
        switch self {
        case .open(let url): url
        case .tab(let tab): tab.url
        case .history(let entry): entry.url
        case .search, .suggestion, .command: nil
        }
    }

    @MainActor func shortcut(using shortcuts: ShortcutPreferences) -> KeyboardShortcut? {
        if case .command(let command) = self { shortcuts.shortcut(for: command) } else { nil }
    }
}
