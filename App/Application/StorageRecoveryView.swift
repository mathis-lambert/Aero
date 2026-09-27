import SwiftUI

struct StorageRecoveryView: View {
    let browser: BrowserModel
    @State private var confirmsRecovery = false

    var body: some View {
        ContentUnavailableView {
            Label("Saved data unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(verbatim: browser.storageFailureMessage ?? "")
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
                if browser.canRecoverStorage {
                    Button("Restore previous state…") { confirmsRecovery = true }
                        .fixedSize()
                        .accessibilityIdentifier("storage.restore")
                }
            }
            .disabled(browser.isOpeningStorage)
        }
        .confirmationDialog("Restore the previous browser state?", isPresented: $confirmsRecovery) {
            Button("Restore previous state", role: .destructive) { Task { await browser.restoreStorage() } }
        } message: {
            Text("Changes since that snapshot will be replaced, including tabs, permissions and extension settings. Current files will be preserved separately. Browsing history is not restored.")
        }
    }
}
