import AppKit
import SwiftUI

extension BrowserModel {
    /// The Quit menu item: asks in the browser window, unless the person turned the prompt off or
    /// the window cannot show it. A second request while it is shown quits. See docs/BROWSING.md › Quitting.
    func requestQuit() {
        if case .quit = window.prompt { NSApp.terminate(nil); return }
        guard preferences.confirmsQuit, let main = WindowConfiguration.mainWindow, main.isVisible || main.isMiniaturized else {
            NSApp.terminate(nil)
            return
        }
        main.deminiaturize(nil)
        main.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window.controlBar = nil
        present(.quit)
    }
}

struct QuitPrompt: View {
    let browser: BrowserModel

    var body: some View {
        Prompt(title: Text("Quit Aero?"), icon: Image(nsImage: NSApp.applicationIconImage)) {
            Button("Quit, and don't ask again") {
                browser.preferences.confirmsQuit = false
                NSApp.terminate(nil)
            }
            .buttonStyle(PanelButtonStyle())
            .accessibilityIdentifier("quit.never")
            Spacer(minLength: 16)
            PromptCancelButton { browser.dismissPrompt() }
                .accessibilityIdentifier("quit.cancel")
            PromptConfirmButton(title: "Quit") { NSApp.terminate(nil) }
                .accessibilityIdentifier("quit.confirm")
        }
        .accessibilityIdentifier("quit.prompt")
    }
}
