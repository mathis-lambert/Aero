import BrowserCore
import SwiftUI

/// Draws a browser page natively in the page surface, instead of a web view.
struct InternalPageView: View {
    let page: InternalPage
    let tab: BrowserTab
    let browser: BrowserModel

    var body: some View {
        switch page {
        case .history: HistoryView(browser: browser)
        case .terminal: TerminalPane(browser: browser, tab: tab)
        }
    }
}

extension InternalPage {
    var title: String {
        switch self {
        case .history: String(localized: "History")
        case .terminal: String(localized: "Terminal")
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock"
        case .terminal: "apple.terminal"
        }
    }
}
