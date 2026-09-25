import BrowserWebKit
import Foundation
import Observation

/// Find state of one browser window. Only the latest search may update the result, so a slow
/// answer for an earlier query never overrides the current one.
@MainActor @Observable
final class FindInPage {
    private(set) var isPresented = false
    private(set) var hasNoMatches = false
    /// Counts searches that turned up nothing, to animate each miss once.
    private(set) var missCount = 0
    var query = ""
    private(set) var focusRequest = UUID()
    @ObservationIgnored private var generation = 0

    /// Prefills with the page's selection, like Safari, then focuses the field.
    func present(on page: BrowserPage) async {
        if !isPresented, let selection = await page.selectedText() { query = selection }
        isPresented = true
        focusRequest = UUID()
    }

    func search(on page: BrowserPage, backwards: Bool = false) async {
        generation += 1
        let current = generation
        guard !query.isEmpty else {
            hasNoMatches = false
            return
        }
        let found = await page.find(query, backwards: backwards)
        guard current == generation, isPresented else { return }
        if !found, !hasNoMatches { missCount += 1 }
        hasNoMatches = !found
    }

    func dismiss(returningFocusTo page: BrowserPage? = nil) {
        guard isPresented else { return }
        generation += 1
        isPresented = false
        hasNoMatches = false
        page?.focus()
    }
}
