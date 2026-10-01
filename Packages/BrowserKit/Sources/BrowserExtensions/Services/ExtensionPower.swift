import Foundation
import IOKit.pwr_mgt

/// Owns one system assertion per extension; unloading always releases it.
@MainActor
final class ExtensionPower {
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "The system could not change its power assertion." }
    }

    private var assertions: [String: IOPMAssertionID] = [:]
    private var activity: [String: IOPMAssertionID] = [:]

    isolated deinit {
        for assertion in assertions.values { IOPMAssertionRelease(assertion) }
        for assertion in activity.values { IOPMAssertionRelease(assertion) }
    }

    func request(_ level: String, for identifier: String) throws {
        let kind: String
        switch level {
        case "system": kind = kIOPMAssertionTypePreventUserIdleSystemSleep
        case "display": kind = kIOPMAssertionTypePreventUserIdleDisplaySleep
        default: throw ExtensionBridge.Failure.invalidRequest
        }
        var assertion: IOPMAssertionID = 0
        guard IOPMAssertionCreateWithName(kind as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Aero extension \(identifier)" as CFString, &assertion) == kIOReturnSuccess else { throw Failure.unavailable }
        release(identifier)
        assertions[identifier] = assertion
    }

    func release(_ identifier: String) {
        if let assertion = assertions.removeValue(forKey: identifier) { IOPMAssertionRelease(assertion) }
    }

    func close(_ identifier: String) {
        release(identifier)
        if let assertion = activity.removeValue(forKey: identifier) { IOPMAssertionRelease(assertion) }
    }

    func reportActivity(for identifier: String) throws {
        var assertion = activity[identifier] ?? 0
        guard IOPMAssertionDeclareUserActivity("Aero extension activity" as CFString, kIOPMUserActiveLocal, &assertion) == kIOReturnSuccess else {
            throw Failure.unavailable
        }
        activity[identifier] = assertion
    }
}

extension ProfileExtensions {
    func powerRequest(_ action: String, _ body: [String: Any], of extensionID: String) throws -> Any? {
        try require("power", of: extensionID)
        switch action {
        case "request":
            guard let level = body["level"] as? String else { throw ExtensionBridge.Failure.invalidRequest }
            try power.request(level, for: extensionID)
        case "release": power.release(extensionID)
        case "activity": try power.reportActivity(for: extensionID)
        default: throw ExtensionBridge.Failure.unknownRequest
        }
        return nil
    }
}
