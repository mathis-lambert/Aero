import AppKit
import SwiftUI

/// The chrome's one kind of modal: a card over the window, which is dimmed and takes no clicks.
/// Every question the browser asks uses it, so they look and behave the same. See docs/DESIGN.md › Prompts.
struct Prompt<Content: View, Actions: View>: View {
    private static var minimumWidth: CGFloat { 400 }

    let title: Text
    var message: Text?
    var icon: Image?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let icon { icon.resizable().frame(width: 56, height: 56).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 6) {
                title.font(BrowserDesign.Typography.heading)
                if let message { message.foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(24)
        .frame(minWidth: Self.minimumWidth, alignment: .leading)
        .fixedSize()
        .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.window)
        .panelShadow()
        .accessibilityElement(children: .contain)
    }
}

extension Prompt where Content == EmptyView {
    init(title: Text, message: Text? = nil, icon: Image? = nil, @ViewBuilder actions: () -> Actions) {
        self.init(title: title, message: message, icon: icon, content: { EmptyView() }, actions: actions)
    }
}

/// Escape and a click outside the card do the same.
struct PromptCancelButton: View {
    var title: LocalizedStringKey = "Cancel"
    let action: () -> Void

    var body: some View {
        Button(action: action) { HStack(spacing: 8) { Text(title); Keycaps("esc") } }
            .buttonStyle(PanelButtonStyle())
            .keyboardShortcut(.cancelAction)
    }
}

/// Return does the same.
struct PromptConfirmButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { HStack(spacing: 8) { Text(title); Keycaps("↵", onAccent: true) } }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
    }
}

extension View {
    /// Shows the prompt `content` builds for `item` over this view, until `item` is `nil`.
    func prompt<Item: Identifiable, Card: View>(_ item: Item?, onCancel: @escaping () -> Void, @ViewBuilder content: @escaping (Item) -> Card) -> some View {
        overlay {
            if let item {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onCancel)
                        .accessibilityHidden(true)
                    content(item)
                }
                .background(KeyboardToPrompt())
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .browserAnimation(value: item?.id)
    }
}

/// Takes the keyboard away from the page or field that had it, so Return and Escape reach the prompt.
private struct KeyboardToPrompt: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Resetter() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Resetter: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(nil)
        }
    }
}
