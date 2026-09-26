import AppKit
import BrowserCore
import SwiftUI

/// The control center's extensions: every enabled one, then the way to the Chrome Web Store.
struct ExtensionsGrid: View {
    private static let tileSize: CGFloat = 44

    let browser: BrowserModel
    @Environment(\.palette) private var palette

    var body: some View {
        if let profileID = browser.window.selectedProfileID {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileSize), spacing: 8)], alignment: .leading, spacing: 8) {
                if let extensions = browser.pages.extensionsIfMade(for: profileID) {
                    ForEach(browser.installedExtensions(inProfile: profileID).filter(\.isEnabled)) { record in
                        ExtensionButton(browser: browser, extensions: extensions, record: record, size: Self.tileSize)
                            .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                    }
                }
                tile("Get extensions", symbol: "plus", identifier: "controlCenter.getExtensions") {
                    browser.window.controlCenterPresented = false
                    browser.open(URL(string: "https://chromewebstore.google.com")!)
                }
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        }
        .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
        .tooltip(Text(title))
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }
}
