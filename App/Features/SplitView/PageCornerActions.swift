import BrowserCore
import SwiftUI

extension View {
    /// The pointer pushed into the page's top trailing corner brings out a few actions on glass: a terminal or a New Tab
    /// beside the selected tab, and separating its split (docs/SPLIT_VIEW.md).
    func pageCornerActions(_ browser: BrowserModel) -> some View {
        modifier(PageCornerActions(browser: browser))
    }
}

private struct PageCornerActions: ViewModifier {
    /// How close to the corner the pointer must come: at the very edge, so the page's own corner keeps its clicks.
    private static let reach: CGFloat = 14
    /// How long the actions stay once the pointer has left them.
    private static let grace = Duration.milliseconds(450)
    private static let motion = Animation.spring(response: 0.34, dampingFraction: 0.72)

    let browser: BrowserModel
    @State private var shown = false
    @State private var overActions = false
    @State private var size = CGSize.zero
    @State private var hiding: Task<Void, Never>?
    @Environment(\.browserReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        let available = browser.window.selectedTabID != nil && browser.window.peek == nil && browser.window.controlBar == nil
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            // Hovering never takes a click from the page.
            .onContinuousHover { phase in
                guard available, case .active(let point) = phase else { return }
                let trailing = layoutDirection == .rightToLeft ? point.x <= Self.reach : point.x >= size.width - Self.reach
                if trailing, point.y <= Self.reach { show() }
            }
            .overlay(alignment: .topTrailing) {
                if shown, available {
                    actions
                        .padding(8)
                        .onHover { hovering in
                            overActions = hovering
                            if hovering { hiding?.cancel() } else { hideSoon() }
                        }
                        .transition(.scale(scale: 0.4, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : Self.motion, value: shown)
            .onChange(of: browser.window.selectedTabID) { shown = false }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            action(.newTerminal)
            action(.newPane)
            if browser.currentSplit != nil { action(.separateSplit) }
        }
        .padding(4)
        .browserGlass(.panel, radius: 20)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page.cornerActions")
    }

    private func action(_ command: BrowserCommand) -> some View {
        Button {
            shown = false
            browser.perform(command)
        } label: {
            Image(systemName: command.symbol)
                .font(BrowserDesign.Typography.chrome.weight(.medium))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(QuietButtonStyle(radius: 16))
        .disabled(!browser.isEnabled(command))
        .tooltip(Text(verbatim: command.title), shortcut: browser.shortcuts.shortcut(for: command))
        .accessibilityLabel(Text(verbatim: command.title))
        .accessibilityIdentifier("page.corner.\(command.rawValue)")
    }

    private func show() {
        hiding?.cancel()
        shown = true
        // Brought out by a pass of the pointer, the actions go if it does not come onto them.
        hideSoon()
    }

    private func hideSoon() {
        hiding?.cancel()
        hiding = Task {
            do { try await Task.sleep(for: Self.grace) } catch { return }
            if !overActions { shown = false }
        }
    }
}
