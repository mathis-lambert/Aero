import AppKit
import Foundation
import WebKit

extension ProfileExtensions {
    /// Chrome's `clipboardRead`, which WebKit lacks: with it, a page reads what another app copied without waiting for
    /// the person to confirm a paste. Without it, the page is left to WebKit's own confirmation (`nil`).
    func clipboardRequest(_ action: String, context: WKWebExtensionContext) throws -> Any? {
        guard action == "read" else { throw ExtensionBridge.Failure.unknownRequest }
        guard providedGrants[context.uniqueIdentifier]?.contains("clipboardRead") == true else { return nil }
        return NSPasteboard.general.string(forType: .string) ?? ""
    }
}
