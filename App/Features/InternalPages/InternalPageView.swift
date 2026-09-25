import BrowserCore
import SwiftUI

/// Draws a browser page natively in the page surface, instead of a web view.
struct InternalPageView: View {
    let page: InternalPage
    let browser: BrowserModel

    var body: some View {
        switch page {
        case .history: HistoryView(browser: browser)
        }
    }
}

extension InternalPage {
    var title: String {
        switch self {
        case .history: String(localized: "History")
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock"
        }
    }
}
