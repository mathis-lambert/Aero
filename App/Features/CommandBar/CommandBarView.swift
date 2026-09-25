import BrowserCore
import SwiftUI

struct CommandBarView: View {
    let browser: BrowserModel
    let request: CommandBarRequest
    @State private var text = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    /// The whole catalog, in its order, except the palette itself.
    private var commands: [BrowserCommand] {
        BrowserCommand.allCases.filter { command in
            command != .commandPalette && browser.isEnabled(command)
                && (text.isEmpty || command.title.localizedStandardContains(text))
        }
    }
    private var hasNavigation: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var count: Int { commands.count + (hasNavigation ? 1 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: BrowserDesign.fieldSpacing) {
                Image(systemName: "magnifyingglass").font(BrowserDesign.Typography.fieldIcon).foregroundStyle(.secondary)
                TextField("Search, enter an address, or find a command", text: $text)
                    .textFieldStyle(.plain)
                    .font(BrowserDesign.Typography.field)
                    .focused($focused)
                    .onSubmit { activate() }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, count - 1)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
                    .accessibilityIdentifier("command.input")
                ShortcutLabel(text: "esc")
            }
            .padding(22)
            Hairline()
            VStack(spacing: 3) {
                if hasNavigation {
                    resultRow(symbol: "arrow.up.right", title: text, shortcut: "↵", index: 0) {
                        browser.submit(text, replacing: request.replacing)
                    }
                }
                ForEach(Array(commands.enumerated()), id: \.element) { offset, command in
                    resultRow(symbol: command.symbol, title: command.title, shortcut: command.shortcut?.label,
                              index: offset + (hasNavigation ? 1 : 0)) {
                        browser.window.commandBar = nil
                        browser.perform(command)
                    }
                }
            }
            .padding(8)
            Hairline()
            HStack(spacing: 6) {
                Text("Navigate with ↑ ↓")
                Spacer()
                Text("Open with ↵")
            }
            .font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
        .browserSurface(fill: BrowserPalette(scheme: scheme).canvas,
                        border: BrowserPalette(scheme: scheme).line,
                        radius: BrowserDesign.Radius.card)
        .paletteShadow()
        .onAppear { text = request.initialText }
        .defaultFocus($focused, true)
        .task {
            await Task.yield()
            focused = true
        }
        .onChange(of: text) { selection = 0 }
        .onExitCommand { browser.window.commandBar = nil }
    }

    private func resultRow(symbol: String, title: String, shortcut: String?, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: BrowserDesign.rowIconWidth).foregroundStyle(.secondary)
                Text(verbatim: title).lineLimit(1)
                Spacer()
                if let shortcut { ShortcutLabel(text: shortcut) }
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(selection == index ? BrowserPalette(scheme: scheme).fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == index ? .isSelected : [])
    }

    private func activate() {
        if hasNavigation, selection == 0 { browser.submit(text, replacing: request.replacing); return }
        let index = selection - (hasNavigation ? 1 : 0)
        guard commands.indices.contains(index) else { return }
        let command = commands[index]
        browser.window.commandBar = nil
        browser.perform(command)
    }
}
