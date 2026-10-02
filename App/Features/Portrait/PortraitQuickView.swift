import BrowserCore
import SwiftUI

/// The quick flow, in a popover on the sidebar's address: the portrait, its backdrop and tint, the ways out, and
/// Customize…, which hands the same capture to the studio. See docs/PORTRAIT.md › Quick capture.
struct PortraitQuickView: View {
    static let width: CGFloat = 340
    private static let previewHeight: CGFloat = 200

    let browser: BrowserModel
    let studio: PortraitStudio
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(BrowserCommand.capturePortrait.title)
                    .font(BrowserDesign.Typography.label)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: customize) {
                    Label("Customize…", systemImage: "slider.horizontal.3")
                        .font(BrowserDesign.Typography.label)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle())
                .fixedSize()
                .accessibilityIdentifier("portrait.customize")
            }
            PortraitPreview(studio: studio, inset: 12)
                .frame(height: Self.previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card, style: .continuous))
            HStack(spacing: 6) {
                ForEach(PortraitStyle.Backdrop.allCases) { backdrop in
                    BackdropTile(studio: studio, backdrop: backdrop, selected: studio.style.backdrop == backdrop, compact: true) {
                        studio.style.backdrop = backdrop
                    }
                }
            }
            if studio.style.backdrop.isTinted {
                PortraitTintPicker(tint: Binding(get: { studio.style.tint }, set: { studio.style.tint = $0 }))
            }
            HStack(spacing: 8) {
                PortraitStatus(studio: studio, showsTitle: false)
                Spacer(minLength: 8)
                PortraitActions(studio: studio, compact: true, close: close)
            }
        }
        .padding(14)
        .frame(width: Self.width)
        .tint(browser.accent.tint)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BrowserCommand.capturePortrait.title)
        .accessibilityIdentifier("portrait.quick")
    }

    private func close() {
        if browser.window.portrait === studio { browser.window.portrait = nil }
    }

    /// The same capture, with its style, in the studio over the window.
    private func customize() {
        browser.window.portrait = nil
        browser.present(.portrait(studio))
    }
}
