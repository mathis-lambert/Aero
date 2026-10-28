import SwiftUI

/// Edits a name in place: Return or leaving the field saves it, Escape keeps the old one. A file's name starts with
/// its stem selected, as in the Finder, so typing keeps the extension.
struct RenameField: View {
    let name: String
    var label: LocalizedStringKey = "Name"
    var isFilename = false
    let save: (String) -> Void
    let end: () -> Void
    @State private var text = ""
    @State private var selection: TextSelection?
    @State private var ended = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text, selection: $selection)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { finish(saving: true) }
            .onExitCommand { finish(saving: false) }
            .onChange(of: focused) { _, focused in if !focused { finish(saving: true) } }
            .onAppear { text = name }
            // After the menu that asked for the edit has closed, which would otherwise keep the focus.
            .task {
                focused = true
                let stem = (text as NSString).deletingPathExtension
                if isFilename, !stem.isEmpty, stem.count < text.count {
                    selection = TextSelection(range: text.startIndex..<text.index(text.startIndex, offsetBy: stem.count))
                }
            }
            .accessibilityIdentifier("sidebar.rename")
    }

    private func finish(saving: Bool) {
        guard !ended else { return }
        ended = true
        if saving { save(text) }
        end()
    }
}
