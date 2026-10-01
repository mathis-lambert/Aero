import SwiftUI

/// A native text edit commits on Return, focus loss or leaving the page.
struct SettingsNameField: View {
    let name: String
    let maximumLength: Int
    let identifier: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .labelsHidden()
            .focused($focused)
            .accessibilityIdentifier(identifier)
            .onAppear { text = name }
            .onChange(of: name) { _, name in if !focused { text = name } }
            .onChange(of: focused) { _, focused in if !focused { save() } }
            .onSubmit(save)
            .onDisappear(perform: save)
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumLength else { text = name; return }
        if value != name { commit(value) }
        text = value
    }
}
