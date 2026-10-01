import Foundation
import WebKit

/// `privacy.services`: what Aero can represent of Chrome's privacy settings. A password manager turns off the browser's
/// password saving to fill the profile's passwords itself. Aero fills no addresses or cards.
extension ProfileExtensions {
    func privacyRequest(_ action: String, _ body: [String: Any], context: WKWebExtensionContext) throws -> Any? {
        let extensionID = context.uniqueIdentifier
        try require("privacy", of: extensionID)
        guard let host else { throw CancellationError() }
        switch action {
        case "passwordSaving":
            let owner = host.passwordExtension(inProfile: profileID)
            let control = owner == extensionID ? "controlled_by_this_extension"
                : owner == nil ? "controllable_by_this_extension" : "controlled_by_other_extensions"
            return ["value": owner == nil && host.offersToSavePasswords, "levelOfControl": control]
        case "setPasswordSaving":
            guard let value = body["value"] as? Bool else { throw ExtensionBridge.Failure.invalidRequest }
            let owner = host.passwordExtension(inProfile: profileID)
            if !value { host.setPasswordExtension(extensionID, inProfile: profileID) }
            else if owner == extensionID { host.setPasswordExtension(nil, inProfile: profileID) }
            return nil
        case "clearPasswordSaving":
            if host.passwordExtension(inProfile: profileID) == extensionID { host.setPasswordExtension(nil, inProfile: profileID) }
            return nil
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }

    /// The profile's passwords changed hands; extensions that may read the setting hear its new value.
    public func passwordExtensionDidChange(to extensionID: String?) {
        for (id, _) in contexts where providedGrants[id]?.contains("privacy") == true {
            let control = extensionID == id ? "controlled_by_this_extension"
                : extensionID == nil ? "controllable_by_this_extension" : "controlled_by_other_extensions"
            deliver("privacy.services.passwordSavingEnabled.onChange",
                    [["value": extensionID == nil && host?.offersToSavePasswords != false, "levelOfControl": control]], to: id)
        }
    }
}
