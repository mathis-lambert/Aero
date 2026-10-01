import AppKit
import BrowserCore
import Foundation
import Observation
import WebKit

extension ProfileExtensions {
    // MARK: - Idle

    func startListeningForIdle(_ extensionID: String) {
        idleStates[extensionID] = idle.state(forInterval: idleIntervals[extensionID] ?? IdleMonitor.defaultInterval)
        updateIdleInterest()
    }

    /// The detection intervals of the extensions listening for `idle.onStateChanged`.
    var idleInterest: [Int] {
        contexts.keys.filter { events.names(for: $0).contains(Self.idleEvent) && providedGrants[$0]?.contains("idle") == true }
            .map { idleIntervals[$0] ?? IdleMonitor.defaultInterval }
    }

    func updateIdleInterest() { registry?.updateIdleInterest() }

    func idleStateDidChange() {
        for extensionID in contexts.keys where events.names(for: extensionID).contains(Self.idleEvent) {
            let state = idle.state(forInterval: idleIntervals[extensionID] ?? IdleMonitor.defaultInterval)
            guard idleStates[extensionID] != state else { continue }
            idleStates[extensionID] = state
            deliver(Self.idleEvent, [state.rawValue], to: extensionID)
        }
    }

    func idleRequest(_ action: String, _ body: [String: Any], of extensionID: String) throws -> Any? {
        try require("idle", of: extensionID)
        // Chrome refuses a state query below the minimum interval and raises a smaller detection interval to it.
        guard let number = body["interval"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue <= Double(Int32.max) else { throw ExtensionBridge.Failure.invalidRequest }
        switch action {
        case "state":
            guard number.intValue >= IdleMonitor.minimumInterval else { throw ExtensionBridge.Failure.invalidRequest }
            return idle.state(forInterval: number.intValue).rawValue
        case "interval":
            idleIntervals[extensionID] = max(number.intValue, IdleMonitor.minimumInterval)
            updateIdleInterest()
            return nil
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }
}
