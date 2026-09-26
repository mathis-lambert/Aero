import SwiftUI

/// Chooses how much of a profile's history to clear, like Safari's Clear History.
struct ClearHistoryPrompt: View {
    let browser: BrowserModel
    let clear: (HistoryClearRange) -> Void
    @State private var range = HistoryClearRange.lastHour

    var body: some View {
        Prompt(title: Text("Clear history for “\(browser.profile?.name ?? "")”?"),
               message: Text("Visited pages are removed from this profile’s history. Tabs, website data and sign-ins are kept.")) {
            Picker("Clear", selection: $range) {
                ForEach(HistoryClearRange.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("history.clearRange")
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: "Clear history") {
                clear(range)
                browser.dismissPrompt()
            }
            .accessibilityIdentifier("history.confirmClear")
        }
    }
}
