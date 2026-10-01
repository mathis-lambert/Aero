import AppKit
import SwiftUI

/// The chrome's one kind of modal: a card over the window, which is dimmed and takes no clicks.
/// Every question the browser asks uses it, so they look and behave the same. See docs/DESIGN.md › Prompts.
struct Prompt<Content: View, Actions: View>: View {
    private static var minimumWidth: CGFloat { 400 }
    /// Long titles and messages wrap instead of widening the card.
    private static var maximumWidth: CGFloat { 520 }

    let title: Text
    var message: Text?
    var icon: Image?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.palette) private var palette
    @Environment(\.promptCancel) private var cancel

    var body: some View {
        layout
            .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.window)
            .panelShadow()
            .accessibilityElement(children: .contain)
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let icon { icon.resizable().frame(width: 56, height: 56).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 6) {
                title.font(BrowserDesign.Typography.heading)
                if let message { message.foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            // A focused field keeps Escape from the Cancel button's shortcut, so it cancels from here.
            content.onExitCommand { cancel?.action() }
            // Trailing, with no leading gap: a prompt's leftmost action lines up with its text.
            HStack(spacing: 8) { actions }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .modifier(BoundedWidth(minimum: Self.minimumWidth, maximum: Self.maximumWidth))
    }
}

/// Sizes the card to its content's natural width within the bounds; longer text wraps at the maximum.
private struct BoundedWidth: ViewModifier {
    let minimum: CGFloat
    let maximum: CGFloat

    func body(content: Content) -> some View {
        BoundedWidthLayout(minimum: minimum, maximum: maximum) { content }
    }
}

private struct BoundedWidthLayout: Layout {
    let minimum: CGFloat
    let maximum: CGFloat

    private func width(of subviews: Subviews) -> CGFloat {
        min(max(subviews.first?.sizeThatFits(.unspecified).width ?? minimum, minimum), maximum)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(of: subviews)
        let height = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

extension Prompt where Content == EmptyView {
    init(title: Text, message: Text? = nil, icon: Image? = nil, @ViewBuilder actions: () -> Actions) {
        self.init(title: title, message: message, icon: icon, content: { EmptyView() }, actions: actions)
    }
}

/// What Escape does inside a prompt's content; the Cancel button's shortcut covers the rest of the card.
struct PromptCancel {
    let action: () -> Void
}

extension EnvironmentValues {
    @Entry var promptCancel: PromptCancel?
}

/// Escape and a click outside the card do the same.
struct PromptCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { HStack(spacing: 8) { Text("Cancel"); Keycaps(.cancelAction) } }
            .buttonStyle(PanelButtonStyle())
            .keyboardShortcut(.cancelAction)
    }
}

/// Return does the same.
struct PromptConfirmButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { HStack(spacing: 8) { Text(title); Keycaps(.defaultAction, onAccent: true) } }
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
                        .environment(\.promptCancel, PromptCancel(action: onCancel))
                }
                // One per prompt: a prompt that replaces another takes the keyboard from it too.
                .background(KeyboardToPrompt().id(item.id))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .browserAnimation(value: item?.id)
    }
}

/// Takes the keyboard away from the page or field that had it, so Return and Escape reach the prompt.
struct KeyboardToPrompt: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Resetter() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Resetter: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(nil)
        }
    }
}
