import BrowserCore
import BrowserStorage
import SwiftUI

/// The History page, shown in a tab (`auro://history`).
struct HistoryView: View {
    /// Waits for a pause in typing, and coalesces refreshes while pages load.
    private static let reloadDelay = Duration.milliseconds(150)
    private static let contentWidth: CGFloat = 760
    private static let searchHeight: CGFloat = 44

    let browser: BrowserModel
    @State private var query = ""
    @State private var entries: [HistoryEntry] = []
    @State private var hasMore = false
    @State private var isUnavailable = false
    @State private var selection: Set<HistoryEntry.ID> = []
    @State private var confirmingClear = false
    @FocusState private var focus: Focus?
    @Environment(\.colorScheme) private var scheme

    private enum Focus { case search, list }

    private struct LoadKey: Hashable {
        let profileID: UUID?
        let query: String
        let revision: Int
    }

    private var profileID: UUID? { browser.window.selectedProfileID }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            searchField
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: Self.contentWidth)
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: browser.window.inputFocusRequest) {
            await Task.yield()
            focus = .search
        }
        // Choosing an entry moves the keyboard to the list, so Delete and Return act on it.
        .onChange(of: selection) { _, selected in if !selected.isEmpty { focus = .list } }
        .sheet(isPresented: $confirmingClear) {
            ClearHistorySheet(profileName: browser.profile?.name ?? "", clear: clear)
        }
        .task(id: LoadKey(profileID: profileID, query: query, revision: browser.history.revision)) {
            do { try await Task.sleep(for: Self.reloadDelay) } catch { return }
            await load(appending: false)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History").font(.system(size: 24, weight: .semibold))
                Text(verbatim: browser.profile?.name ?? "").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear history…") { confirmingClear = true }
                .disabled(isUnavailable || (entries.isEmpty && query.isEmpty))
                .accessibilityIdentifier("history.clear")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onKeyPress(.downArrow) {
                    guard let first = entries.first else { return .ignored }
                    selection = [first.id]
                    return .handled
                }
                .onExitCommand { query = "" }
                .accessibilityIdentifier("history.search")
        }
        .padding(.horizontal, 14)
        .frame(height: Self.searchHeight)
        .browserSurface(fill: BrowserPalette(scheme: scheme).raised,
                        border: BrowserPalette(scheme: scheme).line,
                        radius: BrowserDesign.Radius.card)
    }

    @ViewBuilder private var content: some View {
        if isUnavailable {
            ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle",
                                   description: Text("History could not be opened. It has been kept unchanged."))
        } else if entries.isEmpty, query.isEmpty {
            ContentUnavailableView("No history", systemImage: "clock", description: Text("Pages you visit appear here."))
        } else if entries.isEmpty {
            ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try other words."))
        } else {
            List(selection: $selection) {
                ForEach(HistoryDay.group(entries)) { day in
                    Section { rows(of: day) } header: {
                        day.title
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(BrowserPalette(scheme: scheme).canvas)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .focused($focus, equals: .list)
            .onDeleteCommand { delete(selection) }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard !selection.isEmpty else { return .ignored }
                delete(selection)
                return .handled
            }
            .contextMenu(forSelectionType: HistoryEntry.ID.self) { ids in
                Button("Open") { open(ids) }
                Button("Open in new tab") { openInBackground(ids) }
                Divider()
                Button("Delete", role: .destructive) { delete(ids) }
            } primaryAction: { ids in
                open(ids)
            }
        }
    }

    private func rows(of day: HistoryDay) -> some View {
        ForEach(day.entries) { entry in
            HistoryRow(entry: entry, favicons: browser.favicons, profileID: profileID)
                .tag(entry.id)
                .onAppear { loadMoreIfLast(entry) }
        }
    }

    /// Fetches the next page when the last loaded entry scrolls into view.
    private func loadMoreIfLast(_ entry: HistoryEntry) {
        guard hasMore, entry.id == entries.last?.id else { return }
        Task { await load(appending: true) }
    }

    private func load(appending: Bool) async {
        guard let profileID else { return }
        do {
            let page = try await browser.history.entries(profileID: profileID, matching: query,
                                                         before: appending ? entries.last?.lastVisit : nil)
            entries = appending ? entries + page : page
            hasMore = page.count == HistoryStore.pageSize
            selection.formIntersection(entries.map(\.id))
        } catch {
            isUnavailable = true
        }
    }

    private func selectedEntries(_ ids: Set<HistoryEntry.ID>) -> [HistoryEntry] {
        entries.filter { ids.contains($0.id) }
    }

    /// Like Chromium: one entry replaces the History page in its tab; several open in new tabs.
    private func open(_ ids: Set<HistoryEntry.ID>) {
        let chosen = selectedEntries(ids)
        if chosen.count == 1, let entry = chosen.first, let tabID = browser.window.selectedTabID {
            browser.navigate(tabID, to: entry.url)
        } else {
            openInBackground(ids)
        }
    }

    private func openInBackground(_ ids: Set<HistoryEntry.ID>) {
        guard let spaceID = browser.space?.id else { return }
        for entry in selectedEntries(ids) { browser.addTab(entry.url, in: spaceID) }
    }

    private func delete(_ ids: Set<HistoryEntry.ID>) {
        guard let profileID, !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        browser.history.delete(ids, profileID: profileID)
    }

    private func clear(_ range: HistoryClearRange) {
        guard let profileID else { return }
        browser.history.clear(profileID: profileID, since: range.start())
    }
}
