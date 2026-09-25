import BrowserWebKit
import SwiftUI

struct FindBar: View {
    private static let width: CGFloat = 320
    /// Waits for a pause in typing before searching, so WebKit is not asked once per keystroke.
    private static let typingDelay = Duration.milliseconds(80)

    let find: FindInPage
    let page: BrowserPage
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in page", text: Bindable(find).query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { search(backwards: false) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    search(backwards: true)
                    return .handled
                }
                .onExitCommand { find.dismiss(returningFocusTo: page) }
                .accessibilityIdentifier("find.input")
            if find.hasNoMatches {
                Text("No matches")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityIdentifier("find.noMatches")
                    .transition(.opacity)
            }
            IconButton(symbol: "chevron.up", label: "Previous match", size: BrowserDesign.navigationButtonSize) { search(backwards: true) }
                .accessibilityIdentifier("find.previous")
            IconButton(symbol: "chevron.down", label: "Next match", size: BrowserDesign.navigationButtonSize) { search(backwards: false) }
                .accessibilityIdentifier("find.next")
            IconButton(symbol: "xmark", label: "Close find bar", size: BrowserDesign.navigationButtonSize) { find.dismiss(returningFocusTo: page) }
                .accessibilityIdentifier("find.close")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(width: Self.width, height: BrowserDesign.controlHeight + 8)
        .browserSurface(fill: BrowserPalette(scheme: scheme).raised,
                        border: find.hasNoMatches ? Color.red.opacity(0.45) : BrowserPalette(scheme: scheme).line,
                        radius: BrowserDesign.Radius.card)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .shake(trigger: find.missCount)
        .animation(reduceMotion ? nil : BrowserDesign.motion, value: find.hasNoMatches)
        .onChange(of: find.focusRequest, initial: true) { focused = true }
        .task(id: find.query) {
            do { try await Task.sleep(for: Self.typingDelay) } catch { return }
            await find.search(on: page)
        }
    }

    private func search(backwards: Bool) {
        Task { await find.search(on: page, backwards: backwards) }
    }
}
