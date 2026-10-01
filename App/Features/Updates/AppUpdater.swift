import AppKit
import Observation
import Sparkle
import SwiftUI

/// Application-owned adapter for Sparkle's native UI and preferences. No independent timers,
/// downloads or install state: Sparkle owns those, and the app delegate owns termination.
@MainActor @Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    let configuration: UpdateConfiguration
    private(set) var canCheck = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyDownloads = false
    private(set) var lastCheck: Date?
    private(set) var startupError: String?
    /// Sparkle is quitting Aero to install an update and open it again.
    private(set) var isRelaunching = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(isTestRun: Bool) {
        configuration = UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:], isTestRun: isTestRun)
        super.init()
    }

    func start() {
        guard configuration == .enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        // KVO bridges Sparkle's authoritative properties into SwiftUI observation. Callbacks read
        // them on the main actor rather than transferring Objective-C KVO payloads across actors.
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.lastUpdateCheckDate) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
        ]
        do { try updater.start() }
        catch { startupError = error.localizedDescription }
        refresh()
    }

    func check() {
        guard canCheck else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
        refresh()
    }

    private func refresh() {
        guard let updater = controller?.updater else { return }
        canCheck = startupError == nil && updater.canCheckForUpdates
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        lastCheck = updater.lastUpdateCheckDate
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        isRelaunching = true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        isRelaunching = false
    }

    /// Sparkle can retry a relaunch after applicationShouldTerminate cancels it.
    func cancelRelaunch() { isRelaunching = false }
}

extension BrowserModel {
    /// An update never silently discards live website work: before Sparkle restarts Aero, the window asks. A normal
    /// quit keeps its own flow.
    func confirmUpdateRelaunch() async -> Bool {
        guard updater.isRelaunching else { return true }
        // A prompt cannot show while the browser rearranges itself; the relaunch waits for the next attempt.
        guard !isChangingStructure else {
            updater.cancelRelaunch()
            return false
        }
        showMainWindow()
        let message = downloads.activeCount > 0
            ? Text("Downloads are still running. Restarting will cancel them. Save any work on websites before continuing.")
            : Text("Your tabs will reopen, but unsaved work on websites and active calls may be lost. Save your work before continuing.")
        let confirmed = await withCheckedContinuation { continuation in
            present(.confirmation(Confirmation(id: "updateRelaunch", title: Text("Restart Aero to update?"), message: message,
                                               confirmTitle: "Restart", identifier: "updates.confirmRestart", inSettings: false,
                                               confirm: { continuation.resume(returning: true) },
                                               cancel: { continuation.resume(returning: false) })))
        }
        if !confirmed { updater.cancelRelaunch() }
        return confirmed
    }
}
