import AppKit
import Observation
import Sparkle
import SwiftUI

/// Application-owned adapter for Sparkle (docs/UPDATES.md). Sparkle owns the checks, downloads, verification and
/// installation, and its windows show an update the person asks for; this adapter picks the feed of the channel the
/// person chose, follows what Sparkle does, so Settings and the sidebar can say it, and shows updates found on schedule
/// gently, in the sidebar, rather than in a window over the page. No timers or downloads of its own.
@MainActor @Observable
// Sparkle's standard user driver lives on the main thread and calls its delegate there.
final class AppUpdater: NSObject, SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    /// What Sparkle is doing, or found last.
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        /// Found; not downloaded yet.
        case available(version: String)
        /// Downloaded and waiting: it installs when Aero quits, or now with a restart.
        case ready(version: String)
        case failed(String)

        /// The version of the update found or downloaded.
        var pendingVersion: String? {
            switch self {
            case .available(let version), .ready(let version): version
            default: nil
            }
        }

        var isReady: Bool { if case .ready = self { true } else { false } }
    }

    /// Nightlies have their own feed: one per main commit, it is rewritten too often to share the stable one.
    private static let nightlyFeed = "https://getaero.app/updates/nightly.xml"

    let configuration: UpdateConfiguration
    private(set) var status = Status.idle
    private(set) var canCheck = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyDownloads = false
    private(set) var lastCheck: Date?
    private(set) var startupError: String?
    /// Sparkle is quitting Aero to install an update and open it again.
    private(set) var isRelaunching = false
    /// The version the sidebar's reminder was closed for: it comes back for a newer one only.
    private(set) var dismissedVersion: String?
    @ObservationIgnored private let preferences: BrowserPreferences
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// Sparkle's way to install a downloaded update now, restarting Aero.
    @ObservationIgnored private var installNow: (() -> Void)?

    init(isTestRun: Bool, preferences: BrowserPreferences) {
        configuration = UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:], isTestRun: isTestRun)
        self.preferences = preferences
        super.init()
    }

    var channel: UpdateChannel { preferences.updateChannel }

    /// The update the sidebar reminds of: found or ready, and not dismissed.
    var reminder: Status? {
        status.pendingVersion.flatMap { $0 == dismissedVersion ? nil : status }
    }

    func start() {
        guard configuration == .enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
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

    /// A downloaded update installs now, restarting Aero. Otherwise this checks in Sparkle's window: what it finds,
    /// a found update the sidebar reminds of included, it shows with its notes, to install.
    func check() {
        if status.isReady, let installNow { return installNow() }
        guard canCheck else { return }
        status = .checking
        controller?.checkForUpdates(nil)
    }

    func dismissReminder() {
        dismissedVersion = status.pendingVersion
    }

    /// The feed changes at once; the next check reads it, and one runs now in the background. A steadier channel
    /// offers nothing older than this build: it takes over with its next newer release. An update already downloaded
    /// still installs on quit, so it stays offered.
    func setChannel(_ channel: UpdateChannel) {
        guard channel != preferences.updateChannel else { return }
        preferences.updateChannel = channel
        if status.isReady { return }
        status = .idle
        guard let updater = controller?.updater, canCheck else { return }
        updater.resetUpdateCycle()
        updater.checkForUpdatesInBackground()
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

    /// Sparkle can retry a relaunch after applicationShouldTerminate cancels it.
    func cancelRelaunch() { isRelaunching = false }

    // MARK: SPUUpdaterDelegate

    /// Stable and beta read Sparkle's default feed, from Info.plist or its `SUFeedURL` preference, which a release
    /// validation can point at a local fixture (docs/UPDATES.md › Validation).
    func feedURLString(for updater: SPUUpdater) -> String? {
        preferences.updateChannel == .nightly ? Self.nightlyFeed : nil
    }

    /// Betas are in the stable feed's beta channel; Sparkle offers them only here.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        preferences.updateChannel == .beta ? ["beta"] : []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        found(item, ready: false)
    }

    /// A skipped version is no longer offered, by Sparkle or here.
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip { status = .idle }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        installNow = immediateInstallationBlock
        found(item, ready: true)
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        isRelaunching = true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        isRelaunching = false
        // Not finding an update is not a failure; Sparkle reports it here too.
        let error = error as NSError
        guard !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)) else { return }
        if case .checking = status { status = .failed(error.localizedDescription) }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // A check that ended without a word, such as one the person cancelled in Sparkle's window, leaves nothing to say.
        if case .checking = status, error == nil { status = .idle }
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// An update found on schedule waits in the sidebar instead of a window over the page.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        found(update, ready: state.stage == .downloaded || state.stage == .installing)
    }

    /// Shown in Sparkle's window: the reminder has done its work.
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        dismissedVersion = update.displayVersionString
    }

    /// A downloaded update stays ready: hearing of it again as found does not take Restart away.
    private func found(_ item: SUAppcastItem, ready: Bool) {
        let version = item.displayVersionString
        if ready { status = .ready(version: version) } else if !status.isReady { status = .available(version: version) }
    }
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
