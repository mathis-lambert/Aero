import BrowserCore
import Foundation
import WebKit

/// A dialog a page opens with `alert`, `confirm` or `prompt`. It names the frame's site, so a page cannot pass a
/// question off as another site's or the browser's. See docs/BROWSING.md › Page dialogs.
public struct PageDialog: Sendable {
    public enum Kind: Sendable, Equatable {
        case alert, confirm
        case prompt(defaultText: String)
    }

    /// Longer messages are cut, so a page cannot fill the window.
    static let maximumLength = 2048

    public let kind: Kind
    public let message: String
    /// The host of the frame that asks, or its whole address when it has none.
    public let site: String
    /// A page that keeps asking can be told to stop: from its second dialog on, until it navigates.
    public let offersSuppression: Bool
}

public struct PageDialogAnswer: Sendable {
    public let accepted: Bool
    /// What the person typed for `prompt`.
    public let text: String?
    /// No more dialogs from this page until it navigates; they are answered as dismissed.
    public let suppressesMore: Bool

    public static let dismissed = PageDialogAnswer(accepted: false, text: nil, suppressesMore: false)

    public init(accepted: Bool, text: String? = nil, suppressesMore: Bool = false) {
        self.accepted = accepted
        self.text = text
        self.suppressesMore = suppressesMore
    }
}
