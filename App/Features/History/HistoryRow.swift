import BrowserCore
import SwiftUI

struct HistoryRow: View {
    let entry: HistoryEntry
    let favicons: FaviconCache
    let profileID: UUID?

    private var time: String { entry.lastVisit.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        HStack(spacing: BrowserDesign.rowInset) {
            FaviconView(cache: favicons, key: profileID.flatMap { FaviconKey(profileID: $0, url: entry.url) }, size: BrowserDesign.tabIconSize) {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
            .frame(width: BrowserDesign.rowIconWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.displayTitle).lineLimit(1)
                Text(verbatim: entry.url.siteName).font(BrowserDesign.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(verbatim: time).font(BrowserDesign.Typography.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
        .help(entry.url.absoluteString)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.displayTitle))
        .accessibilityValue(Text(verbatim: "\(entry.url.siteName), \(time)"))
        .accessibilityIdentifier("history.row")
    }
}
