import BrowserCore
import SwiftUI

struct ShortcutSettingsView: View {
    let shortcuts: ShortcutPreferences
    @State private var search = ""
    @State private var selection: BrowserCommand? = .newTab
    @State private var confirmsReset = false

    private var commands: [BrowserCommand] {
        BrowserCommand.allCases.filter { search.isEmpty || $0.matchesSearch(search) }
    }

    var body: some View {
        let commands = commands
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search shortcuts", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("shortcuts.search")
                    if !search.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                Button("Restore all defaults…", systemImage: "arrow.counterclockwise") { confirmsReset = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Restore all defaults…")
                    .accessibilityIdentifier("shortcuts.restoreAll")
            }
            .padding(20)
            if let error = shortcuts.error {
                Text(error).foregroundStyle(.red).padding(.horizontal, 20).padding(.bottom, 12)
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
        .onChange(of: search) { _, _ in
            if selection.map({ !commands.contains($0) }) ?? true { selection = commands.first }
        }
        .confirmationDialog("Restore all keyboard shortcuts?", isPresented: $confirmsReset) {
            Button("Restore defaults", role: .destructive) { shortcuts.restoreAll() }
        }
    }
}
