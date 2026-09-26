import AppKit
import SwiftUI

/// Automatic plus every alternate icon; the choice applies everywhere at once.
struct AppIconPicker: View {
    let browser: BrowserModel

    private static let tileSize: CGFloat = 44
    private static let selectionWidth: CGFloat = 2

    /// Rendered away from the main actor while the page is shown: each artwork holds about a thousand shapes.
    @State private var thumbnails: [AppIconVariant: CGImage] = [:]
    @Environment(\.displayScale) private var displayScale
    @Environment(\.palette) private var palette

    private var selection: AppIconVariant? { browser.preferences.appIcon }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("App icon", caption: "Shown in the Dock, the Finder and Launchpad, even while Aero is closed.") { EmptyView() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize), spacing: 8)], alignment: .leading, spacing: 8) {
                tile(nil, image: Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)), label: String(localized: "Automatic"))
                ForEach(AppIconVariant.all) { variant in
                    tile(variant, image: thumbnails[variant].map { Image(decorative: $0, scale: displayScale) }, label: variant.label)
                }
            }
        }
        .task(id: displayScale) {
            let pixels = Int(Self.tileSize * displayScale)
            var loaded: [AppIconVariant: CGImage] = [:]
            for variant in AppIconVariant.all {
                guard !Task.isCancelled else { return }
                loaded[variant] = await Self.thumbnail(of: variant, pixels: pixels)
            }
            guard !Task.isCancelled else { return }
            thumbnails = loaded
        }
    }

    private func tile(_ variant: AppIconVariant?, image: Image?, label: String) -> some View {
        let selected = selection == variant
        return Button { browser.setAppIcon(variant) } label: {
            Group {
                if let image {
                    image.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    palette.raised
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.tileSize * BrowserDesign.faviconCornerRatio))
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay {
                RoundedRectangle(cornerRadius: Self.tileSize * BrowserDesign.faviconCornerRatio + Self.selectionWidth * 2)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: Self.selectionWidth)
                    .padding(-Self.selectionWidth * 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle(radius: Self.tileSize * BrowserDesign.faviconCornerRatio))
        .tooltip(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("settings.appIcon.\(variant?.id ?? "automatic")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @concurrent
    private static func thumbnail(of variant: AppIconVariant, pixels: Int) async -> CGImage? {
        guard let url = variant.artworkURL, let artwork = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        return artwork.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
