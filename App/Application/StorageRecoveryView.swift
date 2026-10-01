import SwiftUI

/// The main window's content when saved records could not be opened (docs/STORAGE.md › Recovery).
struct StorageRecoveryView: View {
    let browser: BrowserModel
    let failure: StorageFailure

    var body: some View {
        ContentUnavailableView {
            Label("Saved data unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(verbatim: failure.message)
        } actions: {
            VStack {
                HStack {
                    Button("Retry") { Task { await browser.start() } }
                        .fixedSize()
                        .accessibilityIdentifier("storage.retry")
                    Button("Show files") { browser.revealStorage() }
                        .fixedSize()
                        .accessibilityIdentifier("storage.showFiles")
                }
                if failure.canRestore {
                    Button("Restore previous state…") {
                        browser.present(.confirmation(Confirmation(
                            id: "restoreStorage", title: Text("Restore the previous browser state?"),
                            message: Text("Changes since that snapshot will be replaced, including tabs, permissions and extension settings. Current files will be preserved separately. Browsing history is not restored."),
                            confirmTitle: "Restore previous state", identifier: "storage.confirmRestore", inSettings: false) { [browser] in
                            await browser.restoreStorage()
                        }))
                    }
                        .fixedSize()
                        .accessibilityIdentifier("storage.restore")
                }
            }
            .disabled(browser.isOpeningStorage)
        }
    }
}
