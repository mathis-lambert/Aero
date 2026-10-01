import BrowserCore
import SwiftUI

struct ProfilePrompt: View {
    let browser: BrowserModel
    var onCreated: ((UUID) -> Void)?
    @State private var name = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        Prompt(title: Text("New profile"), message: Text("Cookies and website sign-ins stay separate for each profile.")) {
            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("profiles.name")
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: "Create profile") {
                task = Task {
                    if let id = await browser.createProfile(name: name) {
                        browser.dismissPrompt()
                        onCreated?(id)
                    }
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > BrowserProfile.maximumNameLength)
            .accessibilityIdentifier("profiles.save")
        }
        .disabled(browser.isChangingStructure || !browser.extensionsReady)
        .onDisappear { task?.cancel() }
    }
}
