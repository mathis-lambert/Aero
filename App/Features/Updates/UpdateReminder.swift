import SwiftUI

/// Above the sidebar's footer: an update found or downloaded, gently (docs/UPDATES.md › In Aero). It names the version
/// and offers the one step left, restarting into a downloaded update or opening it in Sparkle's window; its close
/// button keeps it away until a newer version.
struct UpdateReminder: View {
    let browser: BrowserModel
    @State private var hovered = false
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let reminder = browser.updater.reminder
        Group {
            if let reminder, let version = reminder.pendingVersion { card(version: version, ready: reminder.isReady) }
        }
        .padding(.horizontal, BrowserDesign.sidebarInset)
        .padding(.top, reminder == nil ? 0 : 6)
        .animation(reduceMotion ? nil : BrowserDesign.cardSpring, value: reminder)
    }

    private func card(version: String, ready: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: ready ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: ready)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Aero \(version)").font(BrowserDesign.Typography.cardTitle).foregroundStyle(palette.ink)
                    Text(ready ? "Ready to install" : "Update available")
                        .font(BrowserDesign.Typography.cardSubtitle)
                        .foregroundStyle(palette.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding([.horizontal, .top], 2)
            Button(ready ? "Restart" : "Update") { browser.updater.check() }
                .buttonStyle(PanelButtonStyle(prominent: true, card: true))
                .accessibilityIdentifier("updates.reminder.install")
        }
        .padding(6)
        .browserGlass(.control, radius: BrowserDesign.Radius.card)
        .overlay(alignment: .topTrailing) {
            if hovered {
                CardCloseButton(label: "Later", identifier: "updates.reminder.dismiss") { browser.updater.dismissReminder() }
            }
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered)
        .transition(.sidebarCard)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("updates.reminder")
    }
}
