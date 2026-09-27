import SwiftUI

/// A row of the Profiles and Spaces pages: an identity tile, a name with a summary, and trailing
/// details. Shown as a card that highlights under the pointer and opens its detail page.
struct SettingsRow<Tile: View, Subtitle: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var tile: Tile
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var trailing: Trailing
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: BrowserDesign.rowInset) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(BrowserDesign.Typography.chrome.weight(.medium)).lineLimit(1)
                subtitle
                    .font(BrowserDesign.Typography.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
            Image(systemName: "chevron.forward")
                .font(BrowserDesign.Typography.glyph)
                .foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
    }
}

/// What a Settings list holds, and its main action.
struct SettingsListIntro<Action: View>: View {
    let text: LocalizedStringKey
    @ViewBuilder var action: Action
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(text)
                .font(BrowserDesign.Typography.chrome)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action.buttonStyle(PanelButtonStyle())
        }
    }
}
