import BrowserCore
import SwiftUI

struct HistoryRow: View {
    let entry: HistoryEntry
    let favicons: FaviconCache
    let profileID: UUID?

    private var title: String { entry.title.isEmpty ? host : entry.title }
    private var host: String { entry.url.host ?? entry.url.absoluteString }
    private var time: String { entry.lastVisit.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(cache: favicons, key: profileID.flatMap { FaviconKey(profileID: $0, url: entry.url) }, size: BrowserDesign.tabIconSize) {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
            .frame(width: BrowserDesign.rowIconWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).lineLimit(1)
                Text(verbatim: host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(verbatim: time).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
        .help(entry.url.absoluteString)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: "\(host), \(time)"))
        .accessibilityIdentifier("history.row")
    }
}
