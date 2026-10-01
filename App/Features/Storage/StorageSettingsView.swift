import SwiftUI

/// What Aero keeps on this Mac, what can be cleaned, and resetting Aero. See docs/STORAGE.md › Storage settings.
struct StorageSettingsView: View {
    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void
    @State private var usage: StorageUsage?
    /// The action running; every other one waits.
    @State private var working: String?
    @State private var failure: String?
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Group {
                Section { overview }
                Section {
                        row(.websiteCache, detail: "Pages, images and scripts kept to open sites faster.") { clearButton("websiteCache") { await browser.clearWebsiteCache() } }
                        row(.icons, detail: "Fetched again as pages load.") { clearButton("icons") { try await browser.clearIcons() } }
                        row(.blockingLists, detail: "Needed to block ads and trackers; kept up to date on their own.") { EmptyView() }
                } header: { Text("Caches") } footer: { Text("Caches fill again as you browse. Sign-ins stay.") }
                Section {
                        ForEach(browser.profiles) { profile in
                            StorageRow(title: Text(verbatim: profile.name), detail: Text("Cookies and site data"),
                                       size: usage?.siteData[profile.id] ?? (usage == nil ? nil : 0), identifier: "siteData.\(profile.name)") {
                                ProfileMonogram(name: profile.name, size: 22)
                            } action: {
                                actionButton("Clear…", identifier: "siteData.\(profile.name)") {
                                    confirm(id: "siteData", title: Text("Clear the cookies and site data of \(profile.name)?"),
                                            message: Text("Its sites will sign you out and forget their settings. Other profiles keep theirs."),
                                            action: "Clear site data") { [browser] in await browser.clearSiteData(profileID: profile.id) }
                                }
                            }
                        }
                        if let unused = usage?.unusedSiteData, unused > 0 {
                            StorageRow(title: Text("Deleted profiles"), detail: Text("Website data left by profiles that no longer exist"), size: unused, identifier: "unusedSiteData") {
                                Image(systemName: "person.crop.circle.badge.xmark").foregroundStyle(.secondary)
                            } action: {
                                clearButton("unusedSiteData", title: "Remove") { try await browser.removeUnusedSiteData() }
                            }
                        }
                } header: { Text("Website data") } footer: { Text("Clearing a profile’s data signs you out of its sites.") }
                Section("History") {
                        row(.history, detail: "Every profile’s visited pages.") {
                            actionButton("Clear…", identifier: "history") {
                                confirm(id: "history", title: Text("Clear the history of every profile?"),
                                        message: Text("Visited pages are removed from every profile. Tabs and favorites stay."),
                                        action: "Clear history") { [browser] in try await browser.clearAllHistory() }
                            }
                        }
                }
                Section("Aero") {
                        row(.extensions, detail: "Installed extensions and their files.") {
                            actionButton("Manage…", identifier: "extensions") { navigate(.section(.extensions)) }
                        }
                        row(.records, detail: "Profiles, spaces, tabs and favorites.") { EmptyView() }
                }
                Section {
                    Button(role: .destructive) {
                        confirm(id: "reset", title: Text("Reset Aero?"),
                                message: Text("Profiles, spaces, tabs, history, passwords, website data, extensions and settings will be erased. Aero then quits and opens as new."),
                                action: "Reset Aero") { [browser] in try await browser.reset() }
                    } label: { Label("Reset Aero…", systemImage: "arrow.counterclockwise") }
                        .accessibilityIdentifier("storage.reset")
                } footer: {
                    Text("Erases every profile, space, tab, favorite, history, password, website data, extension and setting. Aero then opens as new.")
                }
                if let failure {
                    Section { Text(failure).foregroundStyle(palette.miss).accessibilityIdentifier("storage.failure") }
                }
            }
            .disabled(working != nil)
        }
        .task { await measure() }
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
                    Text("used by Aero on this Mac").foregroundStyle(.secondary)
                } else {
                    Text("Measuring…").foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { browser.revealStorage() } label: { Label("Show in Finder", systemImage: "folder") }
            }
            StorageBar(usage: usage)
        }
        .browserAnimation(value: usage)
    }

    // MARK: - Rows

    private func row(_ item: StorageItem, detail: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        StorageRow(title: Text(item.title), detail: Text(detail), size: usage?.size(of: item), identifier: item.rawValue) {
            Circle().fill(item.color).frame(width: 10, height: 10)
        } action: { action() }
    }

    private func actionButton(_ title: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .accessibilityIdentifier("storage.clear.\(identifier)")
    }

    private func clearButton(_ identifier: String, title: LocalizedStringKey = "Clear", _ action: @escaping () async throws -> Void) -> some View {
        actionButton(title, identifier: identifier) { run(identifier, action) }
    }

    private func confirm(id: String, title: Text, message: Text, action: LocalizedStringKey, _ perform: @escaping () async throws -> Void) {
        browser.present(.confirmation(Confirmation(id: "storage.\(id)", title: title, message: message, confirmTitle: action,
                                                   identifier: "storage.confirm") { run(id, perform) }))
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
                        .tooltip(Text("\(Text(item.title)): \(size.formatted(.byteCount(style: .file)))"))
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

/// A row of the form: an icon, what it is, its size and its action.
private struct StorageRow<Icon: View, Action: View>: View {
    let title: Text
    let detail: Text
    /// `nil` while measuring.
    let size: Int64?
    let identifier: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: BrowserDesign.rowInset) {
            icon.frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                title.lineLimit(1)
                detail.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(size.map { $0.formatted(.byteCount(style: .file)) } ?? "–")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityIdentifier("storage.size.\(identifier)")
            action
        }
    }
}
