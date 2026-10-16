import SwiftUI

struct TabTransferPrompt: View {
    let browser: BrowserModel
    let transfer: TabTransfer

    var body: some View {
        let several = browser.tabIDs(of: transfer.items).count > 1
        Prompt(title: Text("Change browsing profile?"),
               message: several ? Text("The pages will reload. Unsaved input may be lost. Cookies and history stay in the original profile.")
                   : Text("The page will reload. Unsaved input may be lost. Cookies and history stay in the original profile.")) {
            if let space = browser.session.spaces.first(where: { $0.id == transfer.spaceID }) { Text(verbatim: space.name).font(.headline) }
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: several ? "Move Tabs" : "Move tab") {
                browser.dismissPrompt()
                browser.transferTabs(transfer)
            }
            .accessibilityIdentifier("spaces.confirmTransfer")
        }
    }
}
