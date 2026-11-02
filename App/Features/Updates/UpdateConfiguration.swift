import Foundation

/// Source builds and tests never create Sparkle, even if their preferences enable updates. A distribution must be
/// the one Aero app, with a valid public key.
enum UpdateConfiguration: Equatable {
    case disabled, invalid, enabled

    init(info: [String: Any], isTestRun: Bool) {
        guard !isTestRun, info["AeroUpdatesEnabled"] as? String == "YES" else {
            self = .disabled
            return
        }
        guard info["CFBundleIdentifier"] as? String == "app.getaero.browser",
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32 else {
            self = .invalid
            return
        }
        self = .enabled
    }
}
