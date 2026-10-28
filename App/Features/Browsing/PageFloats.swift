import BrowserWebKit
import SwiftUI

extension View {
    /// What floats over the selected tab's page: the password picker and offers, the find bar and the zoom indicator.
    /// In a split, they float over the focused pane only; the others keep the modifier, so no pane is rebuilt as the
    /// focus moves.
    func pageFloats(_ browser: BrowserModel, page: BrowserPage, isFocused: Bool = true) -> some View {
        modifier(PageFloats(browser: browser, page: page, isFocused: isFocused))
    }
}

private struct PageFloats: ViewModifier {
    let browser: BrowserModel
    let page: BrowserPage
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isFocused, let picker = browser.passwords.picker, picker.tabID == browser.window.selectedTabID {
                    GeometryReader { area in
                        PasswordPickerView(browser: browser, picker: picker, bounds: area.size)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFocused { floats }
            }
    }

    private var floats: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let offer = browser.passwords.offer, offer.tabID == browser.window.selectedTabID {
                PasswordOfferView(browser: browser, offer: offer)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let failure = browser.passwords.failure {
                HStack(alignment: .top, spacing: 8) {
                    Text(failure)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss", systemImage: "xmark") { browser.passwords.failure = nil }
                        .labelStyle(.iconOnly)
                }
                .padding(12)
                .frame(width: 340)
                .browserGlass(.panel, radius: BrowserDesign.Radius.card)
                .accessibilityIdentifier("passwords.failure")
            }
            if browser.window.find.isPresented {
                FindBar(find: browser.window.find, page: page, shortcuts: browser.shortcuts)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let feedback = browser.window.zoomFeedback, feedback.tabID == browser.window.selectedTabID {
                PageZoomIndicator(feedback: feedback) {
                    if browser.window.zoomFeedback?.id == feedback.id { browser.window.zoomFeedback = nil }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88, anchor: .topTrailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(BrowserDesign.floatingInset)
        .browserAnimation(value: browser.window.zoomFeedback != nil)
        .browserAnimation(value: browser.passwords.offer?.id)
    }
}
