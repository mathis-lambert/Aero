import AppKit
import BrowserCore
import SwiftTerm
import SwiftUI

/// A terminal tab's page (docs/TERMINAL.md): its shell on the page's own surface, in the system's monospaced face, the
/// space's color for its caret and selection. When the shell ends, a glass capsule offers to start another.
struct TerminalPane: View {
    private static let inset: CGFloat = 12

    let browser: BrowserModel
    let tab: BrowserTab
    @Environment(\.palette) private var palette

    var body: some View {
        let session = browser.terminalSession(for: tab)
        let theme = TerminalTheme(palette: palette, accent: browser.accent.light(in: palette.scheme))
        TerminalHost(session: session, theme: theme, takesFocus: browser.window.selectedTabID == tab.id)
            .padding(Self.inset)
            .background(SwiftUI.Color(nsColor: theme.background))
            .overlay(alignment: .bottom) {
                if !session.isRunning {
                    Button { session.start() } label: {
                        Label("Shell ended — Start Again", systemImage: "arrow.clockwise")
                            .font(BrowserDesign.Typography.label)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                    }
                    .buttonStyle(QuietButtonStyle(radius: 16))
                    .browserGlass(.control, radius: 16)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("terminal.restart")
                }
            }
            .browserAnimation(value: session.isRunning)
            .accessibilityIdentifier("terminal")
    }
}

/// The terminal's colors, from the chrome's: its surface and ink, the space's color for what the person acts on, and
/// sixteen ANSI colors tuned to read on that surface in each appearance.
struct TerminalTheme: Equatable {
    let background: NSColor
    let foreground: NSColor
    let accent: NSColor
    let dark: Bool

    init(palette: BrowserPalette, accent: SwiftUI.Color) {
        background = NSColor(palette.canvas)
        foreground = NSColor(palette.ink)
        self.accent = NSColor(accent)
        dark = palette.scheme == .dark
    }

    /// Black, red, green, yellow, blue, magenta, cyan, white, then their bright forms.
    var ansi: [SwiftTerm.Color] {
        let hex: [UInt32] = dark
            ? [0x2B2D2C, 0xF2777A, 0x99CC99, 0xE8C46A, 0x7AA6DA, 0xC397D8, 0x70C0B1, 0xD6D4CF,
               0x5C5F5D, 0xFF8F8F, 0xB5E3A9, 0xFFD787, 0x9CC2F0, 0xDAB3EE, 0x8FDCCF, 0xF4F2EC]
            : [0x2E3331, 0xC4392F, 0x3A7D44, 0x9A6B00, 0x2F64B0, 0x8A4AA6, 0x1F7C7A, 0xC9C6BF,
               0x6B706D, 0xE0473C, 0x4E9A57, 0xB98500, 0x3F7BD1, 0xA45EC2, 0x2A9895, 0xF2F0EA]
        return hex.map { value in
            let channel = { (shift: UInt32) in UInt16((value >> shift) & 0xFF) * 257 }
            return SwiftTerm.Color(red: channel(16), green: channel(8), blue: channel(0))
        }
    }
}

/// Shows a session's view, which outlives this host as the web view of a page does its own.
private struct TerminalHost: NSViewRepresentable {
    private static let fontSize: CGFloat = 12.5
    /// The container last given each session shows it, as `WebPageHost` does for pages.
    private static let owners = NSMapTable<TerminalSession, NSView>.weakToWeakObjects()

    let session: TerminalSession
    let theme: TerminalTheme
    /// The selected tab's terminal takes the keyboard as it shows; a pane beside the focused one does not.
    let takesFocus: Bool

    final class Coordinator {
        weak var session: TerminalSession?
        var theme: TerminalTheme?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        if context.coordinator.session !== session {
            context.coordinator.session = session
            Self.owners.setObject(container, forKey: session)
        }
        let view = session.view
        if context.coordinator.theme != theme {
            context.coordinator.theme = theme
            apply(theme, to: view)
        }
        guard Self.owners.object(forKey: session) === container, view.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        // Shown for its tab, it takes the keyboard, as a page does when its tab is chosen.
        if takesFocus { Task { @MainActor in view.window?.makeFirstResponder(view) } }
    }

    private func apply(_ theme: TerminalTheme, to view: LocalProcessTerminalView) {
        view.font = NSFont.monospacedSystemFont(ofSize: Self.fontSize, weight: .regular)
        view.installColors(theme.ansi)
        view.nativeBackgroundColor = theme.background
        view.nativeForegroundColor = theme.foreground
        view.caretColor = theme.accent
        view.selectedTextBackgroundColor = theme.accent.withAlphaComponent(0.3)
    }
}
