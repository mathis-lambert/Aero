import AppKit
import SwiftUI

extension BrowserModel {
    /// The Quit menu item: asks in the browser window, unless the person turned the prompt off or
    /// the window cannot show it. A second request while it is shown quits. See docs/BROWSING.md › Quitting.
    func requestQuit() {
        guard preferences.confirmsQuit, !window.quitPromptPresented, let main = WindowConfiguration.mainWindow, main.isVisible || main.isMiniaturized else {
            NSApp.terminate(nil)
            return
        }
        main.deminiaturize(nil)
        main.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Return and Escape then reach the prompt, not the page or a field.
        main.makeFirstResponder(nil)
        window.controlBar = nil
        window.quitPromptPresented = true
    }
}

struct QuitPrompt: View {
    private static let minimumWidth: CGFloat = 440
    private static let iconSize: CGFloat = 64

    let browser: BrowserModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
            Text("Quit Aero?").font(BrowserDesign.Typography.title)
            HStack(spacing: 8) {
                Button("Quit, and don't ask again") {
                    browser.preferences.confirmsQuit = false
                    NSApp.terminate(nil)
                }
                .buttonStyle(PanelButtonStyle())
                .accessibilityIdentifier("quit.never")
                Spacer(minLength: 16)
                Button { browser.window.quitPromptPresented = false } label: {
                    HStack(spacing: 8) { Text("Cancel"); Keycaps("esc") }
                }
                .buttonStyle(PanelButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("quit.cancel")
                Button { NSApp.terminate(nil) } label: {
                    HStack(spacing: 8) { Text("Quit"); Keycaps("↵", onAccent: true) }
                }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("quit.confirm")
            }
        }
        .padding(28)
        .frame(minWidth: Self.minimumWidth)
        .fixedSize()
        .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.window)
        .panelShadow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quit.prompt")
    }
}
