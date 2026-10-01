import SwiftUI

/// A row of the Profiles and Spaces pages in their form: an identity tile, a name with a summary, and trailing
/// details, opening its detail page.
struct SettingsRow<Tile: View, Subtitle: View, Trailing: View>: View {
    let title: String
    let open: () -> Void
    @ViewBuilder var tile: Tile
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Button(action: open) {
            HStack(spacing: BrowserDesign.rowInset) {
                tile.frame(width: BrowserDesign.identityHeight, height: BrowserDesign.identityHeight)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).lineLimit(1)
                    subtitle.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
