import BrowserCore
import SwiftUI

/// A page visited: its favicon, title and site, and when; picked, it takes the space's color, and under the pointer a
/// button forgets it.
struct HistoryRow: View {
    let entry: HistoryEntry
    let favicons: FaviconCache
    let profileID: UUID?
    let selected: Bool
    /// The list has the keyboard: the pick shows in full.
    let focused: Bool
    let delete: () -> Void
    @State private var hovered = false
    @Environment(\.palette) private var palette

    private var time: String { entry.lastVisit.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(cache: favicons, key: profileID.flatMap { FaviconKey(profileID: $0, url: entry.url) }, size: BrowserDesign.tabIconSize) {
                Image(systemName: "globe").foregroundStyle(palette.secondary)
            }
            .frame(width: 28, height: 28)
            .background(palette.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.displayTitle).font(BrowserDesign.Typography.chrome.weight(.medium)).foregroundStyle(palette.ink)
                Text(verbatim: entry.url.siteName).font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            Text(verbatim: time).font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).monospacedDigit()
            Button(action: delete) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
            }
            .buttonStyle(QuietButtonStyle(radius: 11))
            .foregroundStyle(palette.secondary)
            .opacity(hovered ? 1 : 0)
            .accessibilityLabel(Text("Delete from History"))
            .accessibilityIdentifier("history.deleteRow")
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(focused ? 0.22 : 0.12) : hovered ? palette.hover : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(BrowserDesign.hover, value: hovered)
        .tooltip(entry.url.absoluteString)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: entry.displayTitle))
        .accessibilityValue(Text(verbatim: "\(entry.url.siteName), \(time)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("history.row")
    }
}
