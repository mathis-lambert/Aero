import BrowserCore
import SwiftUI

struct ProfilePrompt: View {
    let browser: BrowserModel
    var usesSheetBackground = false
    var onCreated: ((UUID) -> Void)?
    var onCancel: (() -> Void)?
    @State private var name = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        Prompt(title: Text("New profile"), message: Text("Cookies and website sign-ins stay separate for each profile."), usesSheetBackground: usesSheetBackground) {
            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("profiles.name")
        } actions: {
            PromptCancelButton { if let onCancel { onCancel() } else { browser.dismissPrompt() } }
            PromptConfirmButton(title: "Create profile") {
                task = Task {
                    if let id = await browser.createProfile(name: name) {
                        if let onCreated { onCreated(id) } else { browser.dismissPrompt() }
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
