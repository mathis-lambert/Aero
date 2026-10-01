import AppKit
import Foundation
import WebKit

extension ProfileExtensions {
    /// For a page that cannot reach the clipboard itself, such as an offscreen document without focus.
    func clipboardRequest(_ action: String, _ body: [String: Any], context: WKWebExtensionContext) throws -> Any? {
        switch action {
        case "write":
            guard context.hasPermission(.clipboardWrite) else { throw ExtensionBridge.Failure.notAllowed("clipboardWrite") }
            guard let text = body["text"] as? String else { throw ExtensionBridge.Failure.invalidRequest }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return nil
        case "read":
            try require("clipboardRead", of: context.uniqueIdentifier)
            return NSPasteboard.general.string(forType: .string) ?? ""
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }
}
