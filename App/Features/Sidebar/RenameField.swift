import SwiftUI

/// Edits a name in place: Return or leaving the field saves it, Escape keeps the old one.
struct RenameField: View {
    let name: String
    let save: (String) -> Void
    let end: () -> Void
    @State private var text = ""
    @State private var ended = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { finish(saving: true) }
            .onExitCommand { finish(saving: false) }
            .onChange(of: focused) { _, focused in if !focused { finish(saving: true) } }
            .onAppear { text = name }
            // After the menu that asked for the edit has closed, which would otherwise keep the focus.
            .task { focused = true }
            .accessibilityIdentifier("sidebar.rename")
    }

    private func finish(saving: Bool) {
        guard !ended else { return }
        ended = true
        if saving { save(text) }
        end()
    }
}
