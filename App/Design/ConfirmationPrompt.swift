import SwiftUI

/// A question before something the person asked for that cannot be undone, such as deleting a profile, asked in the
/// window where it was asked. See docs/DESIGN.md › Prompts.
struct Confirmation {
    let id: String
    let title: Text
    var message: Text?
    let confirmTitle: LocalizedStringKey
    /// Identifies the confirm button for UI tests.
    var identifier: String?
    /// Asked from Settings, so shown over the Settings window.
    var inSettings = true
    /// Runs after the prompt closes.
    let confirm: @MainActor () async -> Void
    /// Runs when the prompt is cancelled, by its button, Escape, a click outside, or another prompt taking its place.
    var cancel: (@MainActor () -> Void)?
}

struct ConfirmationPrompt: View {
    let browser: BrowserModel
    let confirmation: Confirmation

    var body: some View {
        Prompt(title: confirmation.title, message: confirmation.message) {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: confirmation.confirmTitle) { browser.confirm(confirmation) }
            .accessibilityIdentifier(confirmation.identifier ?? "prompt.confirm")
        }
    }
}
