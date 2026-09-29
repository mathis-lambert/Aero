import AppKit
import BrowserCore
import os
import SwiftUI

/// An address a page asked to open in another app, such as a sign-in returning to its app or a `mailto:` link.
/// See docs/OTHER_APPS.md › Links to other apps.
struct ApplicationLink {
    let tabID: UUID
    let url: URL
    /// The app macOS opens `url` with.
    let application: URL

    var applicationName: String { FileManager.default.displayName(atPath: application.path).replacing(/\.app$/, with: "") }
}

extension BrowserModel {
    private static let applicationLinkLogger = Logger(subsystem: Diagnostics.subsystem, category: "OtherApps")

    /// Only the selected tab asks, one question at a time: a background page or a burst of requests cannot stack
    /// prompts or open apps. An address no app opens is dropped, since pages probe for installed apps this way.
    func page(_ tabID: UUID, requestsApplicationFor url: URL) {
        guard tabID == window.selectedTabID, window.prompt == nil, !isChangingStructure else { return }
        guard let application = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            Self.applicationLinkLogger.info("No app opens a link of scheme \(url.scheme ?? "", privacy: .public)")
            return
        }
        guard application.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else { return }
        present(.applicationLink(ApplicationLink(tabID: tabID, url: url, application: application)))
    }

    /// The prompt is answered for the tab that asked; a tab left meanwhile opens nothing.
    func openApplicationLink(_ link: ApplicationLink) {
        dismissPrompt()
        guard link.tabID == window.selectedTabID else { return }
        NSWorkspace.shared.open([link.url], withApplicationAt: link.application, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct ApplicationLinkPrompt: View {
    let browser: BrowserModel
    let link: ApplicationLink

    var body: some View {
        Prompt(title: Text("Open “\(link.applicationName)”?"),
               message: Text("This page wants to open a link in another app."),
               icon: Image(nsImage: NSWorkspace.shared.icon(forFile: link.application.path))) {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: "Open") { browser.openApplicationLink(link) }
                .accessibilityIdentifier("applicationLink.open")
        }
        .accessibilityIdentifier("applicationLink.prompt")
    }
}
