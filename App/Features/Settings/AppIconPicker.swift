import AppKit
import SwiftUI

/// Automatic plus every alternate icon; the choice applies to the Dock at once and at each launch.
struct AppIconPicker: View {
    let browser: BrowserModel

    private static let tileSize: CGFloat = 52
    private static let selectionWidth: CGFloat = 2
    /// Parsed once: the SVGs are only drawn at thumbnail size here.
    private static let artworks: [AppIconVariant: NSImage] = Dictionary(uniqueKeysWithValues:
        AppIconVariant.all.compactMap { variant in DockIcon.artwork(for: variant).map { (variant, $0) } })

    private var selection: AppIconVariant? { browser.preferences.appIcon }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsRow("App icon", caption: "Shown in the Dock while Aero is running. The Finder and Launchpad keep the default icon.") { EmptyView() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize), spacing: 12)], alignment: .leading, spacing: 12) {
                tile(nil, image: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath), label: String(localized: "Automatic"))
                ForEach(AppIconVariant.all) { variant in
                    if let artwork = Self.artworks[variant] { tile(variant, image: artwork, label: variant.label) }
                }
            }
        }
    }

    private func tile(_ variant: AppIconVariant?, image: NSImage, label: String) -> some View {
        let selected = selection == variant
        return Button { browser.setAppIcon(variant) } label: {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Self.tileSize * BrowserDesign.faviconCornerRatio))
                .frame(width: Self.tileSize, height: Self.tileSize)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.tileSize * BrowserDesign.faviconCornerRatio + Self.selectionWidth * 2)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: Self.selectionWidth)
                        .padding(-Self.selectionWidth * 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("settings.appIcon.\(variant?.id ?? "automatic")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
