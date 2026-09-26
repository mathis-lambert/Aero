import BrowserCore
import SwiftUI

/// The browser's only address, search and command field, on the New Tab page (`presentation`
/// is `nil`) and over the selected tab. See docs/CONTROL_BAR.md.
struct ControlBarView: View {
    static let fieldHeight: CGFloat = 44
    private static let width: CGFloat = 600
    /// The smallest space kept on each side in narrow windows.
    private static let margin: CGFloat = 48
    private static let fieldInset: CGFloat = 16
    private static let rowHeight = BrowserDesign.tabRowHeight
    private static let rowSpacing: CGFloat = 2
    private static let listPadding: CGFloat = 8
    /// Whole rows only, so the list never ends on half a row.
    private static let visibleRows = 8

    let browser: BrowserModel
    /// When the bar's light crosses it after it appears: on the New Tab page, as the wave reaches it.
    let lightDelay: TimeInterval
    @State private var model: ControlBarModel
    @FocusState private var focused: Bool
    @State private var textSelection: TextSelection?
    /// The pointer only selects rows once it moves, so a bar opening under a still pointer keeps
    /// its first row, which Return opens.
    @State private var pointer: CGPoint?
    @State private var pointerMoved = false
    @Environment(\.palette) private var palette

    init(browser: BrowserModel, presentation: ControlBarPresentation?, lightDelay: TimeInterval = 0) {
        self.browser = browser
        self.lightDelay = lightDelay
        _model = State(initialValue: ControlBarModel(browser: browser, presentation: presentation))
    }

    var body: some View {
        // Computed once per update: every row reads the same list.
        let items = model.items
        let selected = model.selectedIndex(in: items)
        VStack(spacing: 0) {
            field
            if !items.isEmpty {
                Hairline()
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
                .accessibilityHidden(true)
            TextField(model.isOverlay ? "Search, enter an address, or find a command" : "Search or enter an address", text: $model.text, selection: $textSelection)
                .textFieldStyle(.plain)
                .font(BrowserDesign.Typography.field)
                .focused($focused)
                .onSubmit { model.activateSelection() }
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onExitCommand {
                    if model.isOverlay { browser.window.controlBar = nil } else { model.text = "" }
                }
                .accessibilityIdentifier("controlBar.input")
            if model.isOverlay { Keycaps(.cancelAction) }
        }
        .padding(.horizontal, Self.fieldInset)
        .frame(height: Self.fieldHeight)
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
                if let shortcut = item.shortcut { Keycaps(shortcut) }
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
        if let url = item.site, let profileID = browser.window.selectedProfileID {
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

    var shortcut: KeyboardShortcut? {
        if case .command(let command) = self { command.shortcut } else { nil }
    }
}
