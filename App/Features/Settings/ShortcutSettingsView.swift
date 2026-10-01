import BrowserCore
import SwiftUI

struct ShortcutSettingsView: View {
    let browser: BrowserModel
    private var shortcuts: ShortcutPreferences { browser.shortcuts }
    @State private var search = ""
    @State private var selection: BrowserCommand? = .newTab

    private var commands: [BrowserCommand] {
        BrowserCommand.allCases.filter { search.isEmpty || $0.matchesSearch(search) }
    }

    var body: some View {
        let commands = commands
        return VStack(spacing: 0) {
            if let error = shortcuts.error {
                Text(error).foregroundStyle(.red).padding(20)
            }
            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(BrowserCommand.Category.allCases) { category in
                        let commands = commands.filter { $0.category == category }
                        if !commands.isEmpty {
                            Section(category.title) {
                                ForEach(commands, id: \.self) { command in
                                    HStack(spacing: 12) {
                                        Text(command.title)
                                        Spacer(minLength: 0)
                                        if let shortcut = shortcuts.shortcut(for: command) { Keycaps(shortcut) }
                                        if shortcuts.blocked[command] != nil {
                                            Image(systemName: "exclamationmark.triangle")
                                                .accessibilityLabel("Shortcut conflict")
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .tag(command)
                                    .accessibilityIdentifier("shortcuts.command.\(command.rawValue)")
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(width: 320)
                .frame(maxHeight: .infinity)
                .overlay {
                    if commands.isEmpty { ContentUnavailableView.search(text: search) }
                }
                Divider()
                Group {
                    if let selection, commands.contains(selection) {
                        ShortcutDetailView(command: selection, shortcuts: shortcuts)
                            .id(selection)
                    } else {
                        ContentUnavailableView("Select a shortcut", systemImage: "keyboard")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: Text("Search shortcuts"))
        .toolbar {
            ToolbarItem {
                Button("Restore all defaults…", systemImage: "arrow.counterclockwise") {
                    browser.present(.confirmation(Confirmation(id: "restoreShortcuts", title: Text("Restore all keyboard shortcuts?"),
                                                               confirmTitle: "Restore defaults", identifier: "shortcuts.confirmRestore") { [shortcuts] in
                        shortcuts.restoreAll()
                    }))
                }
                .tooltip(Text("Restore all defaults…"))
                .accessibilityIdentifier("shortcuts.restoreAll")
            }
        }
        .onChange(of: search) { _, _ in
            if selection.map({ !commands.contains($0) }) ?? true { selection = commands.first }
        }
    }
}
