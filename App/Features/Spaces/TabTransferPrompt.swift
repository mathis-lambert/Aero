import SwiftUI

struct TabTransferPrompt: View {
    let browser: BrowserModel
    let tabID: UUID
    let spaceID: UUID

    var body: some View {
        Prompt(title: Text("Change browsing profile?"), message: Text("The page will reload. Unsaved input may be lost. Cookies and history stay in the original profile.")) {
            if let space = browser.session.spaces.first(where: { $0.id == spaceID }) { Text(verbatim: space.name).font(.headline) }
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: "Move tab") {
                browser.dismissPrompt()
                browser.transferTab(tabID, toSpace: spaceID)
            }
            .accessibilityIdentifier("spaces.confirmTransfer")
        }
    }
}
