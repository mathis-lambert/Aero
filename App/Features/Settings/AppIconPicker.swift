import SwiftUI

/// Automatic, drawn in both of its appearances, then the alternates by mark. Every tile is drawn from
/// its own artwork, so none changes with the icon chosen. The choice applies everywhere at once.
struct AppIconPicker: View {
    private static let tileSize: CGFloat = 32
    private static let automatic = [AppIconVariant.system(dark: false), .system(dark: true)]

    let browser: BrowserModel
    /// Rendered away from the main actor while the page is shown: each artwork holds about a thousand shapes.
    @State private var thumbnails: [AppIconVariant: CGImage] = [:]
    @Environment(\.displayScale) private var displayScale

    private var selection: AppIconVariant? { browser.preferences.appIcon }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            choice(nil, label: String(localized: "Automatic")) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) { ForEach(Self.automatic) { icon($0) } }.ring(selection == nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic")
                        Text("Light or dark, with Aero").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(AppIconVariant.Mark.allCases, id: \.self) { mark in
                VStack(alignment: .leading, spacing: 6) {
                    Text(mark.label).font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(AppIconVariant.all.filter { $0.mark == mark }) { variant in
                            choice(variant, label: variant.label) { icon(variant).ring(selection == variant) }
                                .tooltip(variant.paletteName)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: displayScale) {
            let pixels = Int(Self.tileSize * displayScale)
            var loaded: [AppIconVariant: CGImage] = [:]
            for variant in Self.automatic + AppIconVariant.all {
                guard !Task.isCancelled else { return }
                loaded[variant] = await Self.thumbnail(of: variant, pixels: pixels)
            }
            guard !Task.isCancelled else { return }
            thumbnails = loaded
        }
    }

    private func icon(_ variant: AppIconVariant) -> some View {
        Group {
            if let thumbnail = thumbnails[variant] {
                Image(decorative: thumbnail, scale: displayScale).resizable().interpolation(.high)
            } else {
                Color.secondary.opacity(0.1)
            }
        }
        .frame(width: Self.tileSize, height: Self.tileSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.tileSize * BrowserDesign.faviconCornerRatio))
    }

    private func choice(_ variant: AppIconVariant?, label: String, @ViewBuilder content: () -> some View) -> some View {
        Button { browser.setAppIcon(variant) } label: { content().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("settings.appIcon.\(variant?.id ?? "automatic")")
            .accessibilityAddTraits(selection == variant ? [.isButton, .isSelected] : .isButton)
    }

    @concurrent
    private static func thumbnail(of variant: AppIconVariant, pixels: Int) async -> CGImage? {
        guard let artwork = variant.artwork else { return nil }
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        return artwork.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

private extension View {
    /// The accent ring around a chosen icon; its room is kept when not chosen, so nothing moves.
    func ring(_ shown: Bool) -> some View {
        padding(4).overlay {
            RoundedRectangle(cornerRadius: 11).strokeBorder(shown ? Color.accentColor : .clear, lineWidth: 2)
        }
    }
}
