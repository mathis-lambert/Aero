import BrowserCore
import SwiftUI

/// Editing state belongs to the selected command and is discarded when selection changes.
struct ShortcutDetailView: View {
    let command: BrowserCommand
    let shortcuts: ShortcutPreferences
    @State private var recording = false
    @State private var candidate: ShortcutBinding?
    @State private var invalid = false
    @FocusState private var recordButtonFocused: Bool

    private var conflicts: [BrowserCommand] { candidate.map { shortcuts.conflicts(for: $0, excluding: command) } ?? [] }
    private var nativeConflict: String? { candidate.flatMap { shortcuts.nativeConflict($0, for: command) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(command.title).font(.title2.weight(.semibold))
                        Text(command.summary).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    options
                }
                bindingEditor
                if let blocked = shortcuts.blocked[command], !blocked.isEmpty {
                    Text("Unavailable: conflicts with \(blocked.joined(separator: ", ")).")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("shortcuts.blocked.\(command.rawValue)")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var options: some View {
        Menu {
            if command.supportsWebsitePriority {
                Section("When a website uses this shortcut") {
                    Picker("Priority", selection: Binding(
                        get: { shortcuts.priority(for: command) },
                        set: { shortcuts.setPriority($0, for: command) }
                    )) {
                        ForEach(ShortcutPriority.allCases) { priority in Text(priority.title).tag(priority) }
                    }
                    .pickerStyle(.inline)
                }
                Divider()
            }
            Button("Disable shortcut", systemImage: "minus.circle") { shortcuts.disable(command) }
                .disabled(shortcuts.shortcut(for: command) == nil)
                .accessibilityIdentifier("shortcuts.disable")
            Button("Restore default", systemImage: "arrow.counterclockwise") { shortcuts.restore(command) }
                .disabled(!shortcuts.isCustomized(command))
                .accessibilityIdentifier("shortcuts.restore")
        } label: {
            Label("Shortcut settings", systemImage: "gearshape")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tooltip(Text("Shortcut settings"))
        .accessibilityIdentifier("shortcuts.settings")
        .disabled(shortcuts.error != nil || recording)
    }

    @ViewBuilder private var bindingEditor: some View {
        if recording {
            VStack(alignment: .leading, spacing: 12) {
                Text("Press a shortcut with Command or Control. Escape cancels.").foregroundStyle(.secondary)
                ShortcutRecorder(record: { event in
                    guard let binding = ShortcutBinding(event: event), binding.isValid else { invalid = true; return }
                    candidate = binding
                    invalid = false
                }, cancel: finishRecording)
                .frame(height: 56)
                .overlay {
                    Group {
                        if let candidate { Keycaps(candidate.shortcut) }
                        else { Text("Press shortcut").foregroundStyle(.secondary) }
                    }
                    .allowsHitTesting(false)
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                .accessibilityLabel("Record shortcut")
                .accessibilityIdentifier("shortcuts.recorder")
                if invalid { Text("Use Command or Control with a key.").foregroundStyle(.red) }
                if let nativeConflict { Text("Reserved by macOS: \(nativeConflict).").foregroundStyle(.red) }
                if !conflicts.isEmpty {
                    Text("Already assigned to \(conflicts.map(\.title).joined(separator: ", ")). Replacing removes that assignment.")
                        .accessibilityIdentifier("shortcuts.conflict")
                }
                HStack {
                    Button("Cancel") { finishRecording() }
                    Spacer()
                    Button(conflicts.isEmpty ? "Save shortcut" : "Replace shortcut") {
                        if let candidate { shortcuts.assign(candidate, to: command) }
                        finishRecording()
                    }
                    .disabled(candidate == nil || invalid || nativeConflict != nil)
                    .accessibilityIdentifier("shortcuts.save")
                }
            }
        } else {
            Button {
                candidate = nil
                invalid = false
                recording = true
            } label: {
                Group {
                    if let shortcut = shortcuts.shortcut(for: command) { Keycaps(shortcut) }
                    else { Text("Record shortcut") }
                }
                .padding(.horizontal, 16)
                .frame(minWidth: 100, minHeight: 44)
            }
            .tooltip(Text("Record shortcut"))
            .focused($recordButtonFocused)
            .accessibilityLabel(Text(command.title))
            .accessibilityValue(Text(verbatim: shortcuts.shortcut(for: command)?.keys.joined() ?? String(localized: "None")))
            .accessibilityIdentifier("shortcuts.record.\(command.rawValue)")
            .disabled(shortcuts.error != nil)
        }
    }

    private func finishRecording() {
        recording = false
        candidate = nil
        invalid = false
        recordButtonFocused = true
    }
}
