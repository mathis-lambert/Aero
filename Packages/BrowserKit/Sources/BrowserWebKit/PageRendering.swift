import WebKit

/// WebKit has no public high-refresh preference. Keep this opt-in confined to page creation;
/// display selection, background throttling and power/thermal limits remain WebKit's responsibility.
/// See docs/PERFORMANCE.md for the private API contract and its verification.
@MainActor
enum PageRendering {
    private static let highRefreshFeature: NSObject? = {
        let selector = NSSelectorFromString("_features")
        guard WKPreferences.responds(to: selector),
              let features = WKPreferences.perform(selector)?.takeUnretainedValue() as? [NSObject] else { return nil }
        return features.first {
            $0.responds(to: NSSelectorFromString("key"))
                && $0.value(forKey: "key") as? String == "PreferPageRenderingUpdatesNear60FPSEnabled"
        }
    }()

    static func configure(_ preferences: WKPreferences) {
        guard let highRefreshFeature else { return }
        // Optional Objective-C dispatch checks the selector and passes a BOOL, not an NSNumber pointer.
        (preferences as AnyObject).setNear60FPSPreference?(false, for: highRefreshFeature)
    }
}

/// Describes the SPI's actual Objective-C signature without a cast or runtime method replacement.
@objc private protocol PageRenderingPreferences {
    @objc(_setEnabled:forFeature:)
    optional func setNear60FPSPreference(_ enabled: Bool, for feature: NSObject)
}
