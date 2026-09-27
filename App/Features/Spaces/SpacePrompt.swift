import SwiftUI

struct SpacePrompt: View {
    let browser: BrowserModel
    let profileID: UUID?
    @State private var draft = SpaceDraft()
    @State private var task: Task<Void, Never>?

    var body: some View {
        Prompt(title: Text("New space")) {
            SpaceForm(draft: $draft, profiles: browser.profiles)
                .frame(width: BrowserDesign.formWidth, alignment: .leading)
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: "Create space") {
                task = Task { if await browser.saveSpace(draft) { browser.dismissPrompt() } }
            }
            .disabled(!draft.isValid)
            .accessibilityIdentifier("spaces.save")
        }
        .disabled(browser.isChangingStructure || !browser.extensionsReady)
        .onAppear { draft = SpaceDraft(profileID: profileID ?? browser.profile?.id, besides: browser.session.spaces) }
        .onDisappear { task?.cancel() }
    }
}
