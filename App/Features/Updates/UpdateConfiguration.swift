import Foundation

/// Source builds and tests never create Sparkle, even if their preferences enable updates.
enum UpdateConfiguration: Equatable {
    case disabled, invalid, enabled

    init(info: [String: Any], isTestRun: Bool) {
        guard !isTestRun, info["AeroUpdatesEnabled"] as? String == "YES" else {
            self = .disabled
            return
        }
        guard let channel = info["AeroChannel"] as? String,
              ["stable", "beta", "nightly"].contains(channel),
              info["CFBundleIdentifier"] as? String == "app.getaero.browser" + (channel == "stable" ? "" : "." + channel),
              info["SUFeedURL"] as? String == "https://getaero.app/updates/\(channel).xml",
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32 else {
            self = .invalid
            return
        }
        self = .enabled
    }
}
