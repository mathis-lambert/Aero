import AppKit
@testable import Aero
import Testing

// Failure mode: the onboarding's titles fall back to the system face because macOS did not register the bundled
// face from Info.plist's `ATSApplicationFontsPath`.
@MainActor
@Test func theBrandFaceIsRegisteredWithTheApp() {
    #expect(NSFont(name: "GildaDisplay-Regular", size: 12) != nil)
}
