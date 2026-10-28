import BrowserCore
import BrowserStorage
import SwiftUI

/// The History page, shown in a tab (`aero://history`): a search, then the days, newest first, each a card of the pages
/// visited that day, its header staying on top while its pages scroll. A click picks a page, a double click or Return
/// opens it in this tab, ⌘ opens it in a tab of its own; Delete forgets it, as its row's button does under the pointer.
/// The list follows visits and deletions while it shows. See docs/BROWSING.md › History.
struct HistoryView: View {
    /// Waits for a pause in typing.
    private static let reloadDelay = Duration.milliseconds(150)
    private static let contentWidth: CGFloat = 720

    let browser: BrowserModel
    @State private var query = ""
    @State private var entries: [HistoryEntry] = []
    @State private var hasMore = false
    @State private var isUnavailable = false
    @State private var loadingMore = false
    @State private var loadRevision = 0
    @State private var selection: HistoryEntry.ID?
    @FocusState private var focus: Focus?
    @Environment(\.palette) private var palette

    private enum Focus { case search, list }

    private struct LoadKey: Hashable {
        let profileID: UUID?
        let query: String
        /// Visits and deletions since: the list follows them.
        let changes: Int
    }

    private var profileID: UUID? { browser.profile?.id }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: Self.contentWidth)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 16)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: browser.window.inputFocusRequest) {
            // Once the field is in the window: focus asked for earlier is lost.
            await Task.yield()
            focus = .search
        }
        .task(id: LoadKey(profileID: profileID, query: query, changes: browser.history.changes)) {
            do { try await Task.sleep(for: Self.reloadDelay) } catch { return }
            await load(appending: false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").font(BrowserDesign.Typography.title)
                Text(verbatim: browser.profile?.name ?? "").foregroundStyle(palette.secondary)
                Spacer()
                Button("Clear history…", systemImage: "trash") { browser.present(.clearHistory(clear)) }
                    .buttonStyle(QuietButtonStyle())
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(palette.secondary)
                    .disabled(isUnavailable || (entries.isEmpty && query.isEmpty))
                    .accessibilityIdentifier("history.clear")
            }
            HStack(spacing: BrowserDesign.rowInset) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary).accessibilityHidden(true)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .search)
                    .onKeyPress(.downArrow) {
                        guard let first = entries.first else { return .ignored }
                        selection = first.id
                        focus = .list
                        return .handled
                    }
                    .onSubmit { if let first = entries.first { open(first) } }
                    .onExitCommand { query = "" }
                    .accessibilityIdentifier("history.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .browserGlass(.control, radius: 20)
            if browser.history.writeFailed {
                Label("Some history changes could not be saved. Try the action again.", systemImage: "exclamationmark.triangle")
                    .font(BrowserDesign.Typography.caption)
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if isUnavailable {
            ContentUnavailableView {
                Label("History unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("History could not be opened. It has been kept unchanged.")
            } actions: {
                Button("Retry") { Task { await load(appending: false) } }
            }
            .frame(maxHeight: .infinity)
        } else if entries.isEmpty, query.isEmpty {
            ContentUnavailableView("No history", systemImage: "clock", description: Text("Pages you visit appear here."))
                .frame(maxHeight: .infinity)
        } else if entries.isEmpty {
            ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try other words."))
                .frame(maxHeight: .infinity)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: .sectionHeaders) {
                    ForEach(HistoryDay.group(entries)) { day in
                        Section {
                            VStack(spacing: 0) {
                                ForEach(day.entries) { entry in
                                    row(entry, last: entry.id == day.entries.last?.id)
                                }
                            }
                            .padding(4)
                            .background(palette.hover, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card, style: .continuous))
                        } header: {
                            HistoryDayHeader(day: day) { clear(day) }
                        }
                    }
                }
                .frame(maxWidth: Self.contentWidth)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .list)
            .onKeyPress(.downArrow) { move(by: 1, proxy) }
            .onKeyPress(.upArrow) { move(by: -1, proxy) }
            .onKeyPress(.return) {
                guard let entry = selectedEntry else { return .ignored }
                open(entry)
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard let entry = selectedEntry else { return .ignored }
                delete(entry)
                return .handled
            }
        }
    }

    private func row(_ entry: HistoryEntry, last: Bool) -> some View {
        HistoryRow(entry: entry, favicons: browser.favicons, profileID: profileID, selected: selection == entry.id, focused: focus == .list) {
            delete(entry)
        }
        .id(entry.id)
        .onTapGesture(count: 2) { open(entry) }
        .simultaneousGesture(TapGesture().onEnded {
            if NSEvent.modifierFlags.contains(.command) { openInBackground(entry) } else { selection = entry.id; focus = .list }
        })
        .iconContextMenu {
            Button("Open", systemImage: "arrow.up.forward.square") { open(entry) }
            Button("Open in New Tab", systemImage: "plus.square.on.square") { openInBackground(entry) }
            Divider()
            Button("Copy Link", systemImage: BrowserCommand.copyLink.symbol) { browser.copy([entry.url]) }
            Divider()
            Button("Delete from History", systemImage: "trash", role: .destructive) { delete(entry) }
        }
        .onAppear { loadMoreIfLast(entry) }
    }

    private var selectedEntry: HistoryEntry? { entries.first { $0.id == selection } }

    private func move(by offset: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !entries.isEmpty else { return .ignored }
        let index = entries.firstIndex { $0.id == selection }.map { $0 + offset } ?? 0
        if index < 0 { focus = .search; selection = nil; return .handled }
        let entry = entries[min(index, entries.count - 1)]
        selection = entry.id
        proxy.scrollTo(entry.id)
        return .handled
    }

    /// Fetches the next page when the last loaded entry scrolls into view.
    private func loadMoreIfLast(_ entry: HistoryEntry) {
        guard hasMore, !loadingMore, entry.id == entries.last?.id else { return }
        Task { await load(appending: true) }
    }

    /// Reloading keeps as many entries as were shown, so following a visit never takes the place scrolled to.
    private func load(appending: Bool) async {
        guard let profileID else { return }
        if appending && loadingMore { return }
        loadRevision += 1
        let revision = loadRevision
        let search = query
        loadingMore = appending
        defer { if revision == loadRevision { loadingMore = false } }
        let limit = appending ? HistoryStore.pageSize : max(HistoryStore.pageSize, entries.count)
        do {
            let page = try await browser.history.entries(profileID: profileID, matching: query,
                                                         before: appending ? entries.last?.cursor : nil, limit: limit)
            guard revision == loadRevision, profileID == self.profileID, search == query, !Task.isCancelled else { return }
            isUnavailable = false
            entries = appending ? entries + page : page
            hasMore = page.count == limit
            if let selection, !entries.contains(where: { $0.id == selection }) { self.selection = nil }
        } catch {
            if revision == loadRevision, profileID == self.profileID, search == query, !Task.isCancelled { isUnavailable = true }
        }
    }

    /// Like Chromium: an entry replaces the History page in its tab.
    private func open(_ entry: HistoryEntry) {
        if let tabID = browser.window.selectedTabID { browser.navigate(tabID, to: entry.url) } else { openInBackground(entry) }
    }

    private func openInBackground(_ entry: HistoryEntry) {
        guard let spaceID = browser.space?.id else { return }
        browser.addTab(entry.url, in: spaceID)
    }

    /// The list follows on its own (`BrowserHistory.changes`); the pick moves to the next page.
    private func delete(_ entry: HistoryEntry) {
        guard let profileID else { return }
        if selection == entry.id, let index = entries.firstIndex(where: { $0.id == entry.id }) {
            selection = entries.indices.contains(index + 1) ? entries[index + 1].id : index > 0 ? entries[index - 1].id : nil
        }
        Task {
            do { try await browser.history.delete([entry.id], profileID: profileID) } catch { showWriteError() }
        }
    }

    private func clear(_ day: HistoryDay) {
        guard let profileID, let end = Calendar.current.date(byAdding: .day, value: 1, to: day.id) else { return }
        Task {
            do { try await browser.history.deleteVisits(profileID: profileID, from: day.id, through: end.addingTimeInterval(-0.001)) }
            catch { showWriteError() }
        }
    }

    private func showWriteError() {
        browser.present(.error(String(localized: "History could not be changed. Check available disk space and try again.")))
    }

    private func clear(_ range: HistoryClearRange) {
        guard let profileID else { return }
        Task {
            do { try await browser.history.clear(profileID: profileID, since: range.start()) } catch { showWriteError() }
        }
    }
}

/// A day's title over its card, staying on top while its pages scroll by; under the pointer it offers to forget the day.
private struct HistoryDayHeader: View {
    let day: HistoryDay
    let clear: () -> Void
    @State private var hovered = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            day.title
                .font(BrowserDesign.Typography.label.weight(.semibold))
                .foregroundStyle(palette.ink)
            Spacer()
            Button("Clear Day", systemImage: "trash", action: clear)
                .buttonStyle(QuietButtonStyle())
                .labelStyle(.titleAndIcon)
                .font(BrowserDesign.Typography.caption)
                .foregroundStyle(palette.secondary)
                .opacity(hovered ? 1 : 0)
                .accessibilityIdentifier("history.clearDay")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(palette.canvas)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(BrowserDesign.hover, value: hovered)
    }
}
