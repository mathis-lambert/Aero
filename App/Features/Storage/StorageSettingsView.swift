import SwiftUI

/// What Aero keeps on this Mac, what can be cleaned, and resetting Aero. See docs/STORAGE.md › Storage settings.
struct StorageSettingsView: View {
    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void
    @State private var usage: StorageUsage?
    /// The action running; every other one waits.
    @State private var working: String?
    @State private var confirmation: Confirmation?
    @State private var failure: String?
    @Environment(\.palette) private var palette

    private enum Confirmation: Identifiable {
        case siteData(UUID, String), history, reset
        var id: String {
            switch self {
            case .siteData(let id, _): "siteData.\(id)"
            case .history: "history"
            case .reset: "reset"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                overview
                FormSection("Caches", footer: "Caches fill again as you browse. Sign-ins stay.") {
                    rows {
                        row(.websiteCache, detail: "Pages, images and scripts kept to open sites faster.") { clearButton("websiteCache") { await browser.clearWebsiteCache() } }
                        row(.icons, detail: "Fetched again as pages load.") { clearButton("icons") { try await browser.clearIcons() } }
                        row(.blockingLists, detail: "Needed to block ads and trackers; kept up to date on their own.") { EmptyView() }
                    }
                }
                FormSection("Website data", footer: "Clearing a profile’s data signs you out of its sites.") {
                    rows {
                        ForEach(browser.profiles) { profile in
                            StorageRow(title: Text(verbatim: profile.name), detail: Text("Cookies and site data"),
                                       size: usage?.siteData[profile.id] ?? (usage == nil ? nil : 0), identifier: "siteData.\(profile.name)") {
                                ProfileMonogram(name: profile.name, size: 22)
                            } action: {
                                actionButton("Clear…", identifier: "siteData.\(profile.name)") { confirmation = .siteData(profile.id, profile.name) }
                            }
                        }
                        if let unused = usage?.unusedSiteData, unused > 0 {
                            StorageRow(title: Text("Deleted profiles"), detail: Text("Website data left by profiles that no longer exist"), size: unused, identifier: "unusedSiteData") {
                                Image(systemName: "person.crop.circle.badge.xmark").foregroundStyle(palette.secondary)
                            } action: {
                                clearButton("unusedSiteData", title: "Remove") { try await browser.removeUnusedSiteData() }
                            }
                        }
                    }
                }
                FormSection("History") {
                    rows {
                        row(.history, detail: "Every profile’s visited pages.") {
                            actionButton("Clear…", identifier: "history") { confirmation = .history }
                        }
                    }
                }
                FormSection("Aero") {
                    rows {
                        row(.extensions, detail: "Installed extensions and their files.") {
                            actionButton("Manage…", identifier: "extensions") { navigate(.section(.extensions)) }
                        }
                        row(.records, detail: "Profiles, spaces, tabs and favorites.") { EmptyView() }
                    }
                }
                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    Button { confirmation = .reset } label: { Label("Reset Aero…", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PanelButtonStyle())
                        .accessibilityIdentifier("storage.reset")
                    Text("Erases every profile, space, tab, favorite, history, password, website data, extension and setting. Aero then opens as new.")
                        .font(BrowserDesign.Typography.caption)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure {
                    Text(failure).font(BrowserDesign.Typography.caption).foregroundStyle(palette.miss).accessibilityIdentifier("storage.failure")
                }
            }
            .disabled(working != nil)
            .frame(maxWidth: BrowserDesign.listWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .task { await measure() }
        .confirmationDialog(confirmationTitle, isPresented: Binding { confirmation != nil } set: { if !$0 { confirmation = nil } }, presenting: confirmation) { item in
            switch item {
            case .siteData(let id, _):
                Button("Clear site data", role: .destructive) { run("siteData") { await browser.clearSiteData(profileID: id) } }
            case .history:
                Button("Clear history", role: .destructive) { run("history") { try await browser.clearAllHistory() } }
            case .reset:
                Button("Reset Aero", role: .destructive) { run("reset") { try await browser.reset() } }
            }
        } message: { item in
            switch item {
            case .siteData: Text("Its sites will sign you out and forget their settings. Other profiles keep theirs.")
            case .history: Text("Visited pages are removed from every profile. Tabs and favorites stay.")
            case .reset: Text("Profiles, spaces, tabs, history, passwords, website data, extensions and settings will be erased. Aero then quits and opens as new.")
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .siteData(_, let name): String(localized: "Clear the cookies and site data of \(name)?")
        case .history: String(localized: "Clear the history of every profile?")
        case .reset: String(localized: "Reset Aero?")
        case nil: ""
        }
    }

    // MARK: - Overview

    /// The total, and a bar with one part per item in the colors of the rows below.
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if let usage {
                    Text(usage.total.formatted(.byteCount(style: .file)))
                        .font(BrowserDesign.Typography.title)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("storage.total")
                    Text("used by Aero on this Mac").font(BrowserDesign.Typography.chrome).foregroundStyle(palette.secondary)
                } else {
                    Text("Measuring…").font(BrowserDesign.Typography.chrome).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 8)
                SectionActionButton("Show in Finder", symbol: "folder") { browser.revealStorage() }
            }
            StorageBar(usage: usage)
        }
        .browserAnimation(value: usage)
    }

    // MARK: - Rows

    private func rows(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 6) { content() }
    }

    private func row(_ item: StorageItem, detail: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        StorageRow(title: Text(item.title), detail: Text(detail), size: usage?.size(of: item), identifier: item.rawValue) {
            Circle().fill(item.color).frame(width: 10, height: 10)
        } action: { action() }
    }

    private func actionButton(_ title: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PanelButtonStyle())
            .accessibilityIdentifier("storage.clear.\(identifier)")
    }

    private func clearButton(_ identifier: String, title: LocalizedStringKey = "Clear", _ action: @escaping () async throws -> Void) -> some View {
        actionButton(title, identifier: identifier) { run(identifier, action) }
    }

    /// One action at a time; the sizes are measured again once it ends.
    private func run(_ identifier: String, _ action: @escaping () async throws -> Void) {
        guard working == nil else { return }
        working = identifier
        failure = nil
        Task {
            do { try await action() } catch {
                failure = String(localized: "This could not be cleared. Quit Aero and try again.")
            }
            await measure()
            working = nil
        }
    }

    private func measure() async {
        let measured = await browser.storageUsage()
        guard !Task.isCancelled else { return }
        usage = measured
    }
}

extension StorageItem {
    var title: LocalizedStringKey {
        switch self {
        case .siteData: "Cookies and site data"
        case .websiteCache: "Website cache"
        case .history: "History"
        case .extensions: "Extensions"
        case .icons: "Site icons"
        case .blockingLists: "Ad blocking lists"
        case .records: "Tabs and spaces"
        }
    }

    var color: Color {
        switch self {
        case .siteData: .purple
        case .websiteCache: .blue
        case .history: .orange
        case .extensions: .pink
        case .icons: .green
        case .blockingLists: .teal
        case .records: .gray
        }
    }
}

/// One part per item, in proportion to its size; a part never disappears below a sliver.
private struct StorageBar: View {
    let usage: StorageUsage?
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, usage?.total ?? 0)
            let items = StorageItem.allCases.filter { (usage?.size(of: $0) ?? 0) > 0 }
            let spacing: CGFloat = 2
            let width = max(0, proxy.size.width - spacing * CGFloat(max(0, items.count - 1)))
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    let size = usage?.size(of: item) ?? 0
                    Rectangle().fill(item.color)
                        .frame(width: max(3, width * CGFloat(size) / CGFloat(total)))
                        .help(Text("\(Text(item.title)): \(size.formatted(.byteCount(style: .file)))"))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 12)
        .background(palette.fill)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// A card like the other Settings lists: an icon, what it is, its size and its action.
private struct StorageRow<Icon: View, Action: View>: View {
    let title: Text
    let detail: Text
    /// `nil` while measuring.
    let size: Int64?
    let identifier: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var action: Action
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: BrowserDesign.rowInset) {
            icon.frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                title.font(BrowserDesign.Typography.chrome.weight(.medium)).lineLimit(1)
                detail.font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(size.map { $0.formatted(.byteCount(style: .file)) } ?? "–")
                .font(BrowserDesign.Typography.chrome)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
                .contentTransition(.numericText())
                .accessibilityIdentifier("storage.size.\(identifier)")
            action
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
    }
}
