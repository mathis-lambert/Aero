import SwiftUI

struct SpaceRemovalPrompt: View {
    let browser: BrowserModel
    let spaceID: UUID
    @State private var task: Task<Void, Never>?

    var body: some View {
        Prompt(title: Text("Delete space?"), message: Text("Its tabs and groups will be removed. Profile data will be kept.")) {
            if let space = browser.session.spaces.first(where: { $0.id == spaceID }) {
                HStack(spacing: 8) {
                    SpaceIcon(space: space)
                    Text(verbatim: space.name).font(.headline)
                }
            }
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: "Delete space") {
                task = Task {
                    await browser.removeSpace(spaceID)
                    if !browser.session.spaces.contains(where: { $0.id == spaceID }) { browser.dismissPrompt() }
                }
            }
            .accessibilityIdentifier("spaces.confirmDelete")
        }
        .disabled(browser.isChangingStructure)
        .onDisappear { task?.cancel() }
    }
}
