import AppKit
import BrowserCore
import BrowserStorage
import Foundation
import Observation

/// The onboarding's steps, in order. See docs/ONBOARDING.md › Steps.
enum OnboardingStep: String, CaseIterable {
    case welcome, source, choice, importing, gettingAround, defaultBrowser, ready

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Saved in preferences so a relaunch resumes where the person was.
struct OnboardingProgress: Equatable {
    static let version = 1
    var step: OnboardingStep
    var completed: Bool
}

/// The first launch's state. The browser owns it while it runs; its step is the only thing saved.
@MainActor @Observable
final class OnboardingModel {
    /// The first launch, or only its import steps for someone already using Aero, which saves no progress.
    enum Mode { case firstLaunch, importOnly }

    @ObservationIgnored unowned let browser: BrowserModel
    let mode: Mode
    private(set) var step: OnboardingStep
    /// Forward or back, for the plate's transition.
    private(set) var movesForward = true
    private(set) var sources: [ImportSource] = []
    /// `nil` is Start fresh.
    var selectedSourceID: String?
    var choice = ImportChoice()
    /// What each source holds, read once in the background when it is selected.
    private(set) var previews: [String: [ImportedProfile]] = [:]
    private(set) var readingSourceID: String?
    private(set) var readFailure: String?
    private(set) var outcome: ImportOutcome?
    private(set) var isImporting = false
    private(set) var triedShortcuts: Set<BrowserCommand> = []
    private(set) var lastTried: BrowserCommand?
    private(set) var recentTabTries = 0
    private(set) var isDefaultBrowser = false
    /// Finished or skipped; its view may still be leaving.
    private(set) var hasEnded = false
    /// Changes when a step's shape or an interaction should move the wind.
    private(set) var windEvent = 0
    /// Where plate rows and icons are, in the onboarding's coordinate space: flights and ripples start there.
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?

    init(browser: BrowserModel, step: OnboardingStep, mode: Mode = .firstLaunch) {
        self.browser = browser
        self.step = step
        self.mode = mode
        refreshSources()
        isDefaultBrowser = Self.isDefault
    }

    isolated deinit {
        readTask?.cancel()
        importTask?.cancel()
    }

    var source: ImportSource? { sources.first { $0.id == selectedSourceID } }
    var preview: [ImportedProfile]? { selectedSourceID.flatMap { previews[$0] } }
    var needsFullDiskAccess: Bool { source.map { $0.kind == .safari && !$0.isReadable } ?? false }
    var steps: [OnboardingStep] { mode == .importOnly ? [.source, .choice, .importing] : OnboardingStep.allCases }
    var isLastStep: Bool { step == steps.last }

    func refreshSources() {
        sources = browser.importSources()
        if let selectedSourceID, !sources.contains(where: { $0.id == selectedSourceID }) { self.selectedSourceID = nil }
        if selectedSourceID == nil, step == .welcome || step == .source { selectedSourceID = sources.first(where: \.isReadable)?.id }
        if let source { read(source) }
    }

    func select(_ sourceID: String?) {
        guard selectedSourceID != sourceID else { return }
        selectedSourceID = sourceID
        readFailure = nil
        if let source { read(source) }
        windEvent += 1
    }

    /// ↑ and ↓ in the source list, Start fresh last.
    func selectNeighbor(_ offset: Int) {
        let ids: [String?] = sources.map(\.id) + [nil]
        guard let index = ids.firstIndex(where: { $0 == selectedSourceID }) else { return }
        select(ids[(index + offset + ids.count) % ids.count])
    }

    /// Reads the source once, off the main actor; a result for a source no longer selected is kept for later.
    private func read(_ source: ImportSource) {
        guard source.isReadable, previews[source.id] == nil, readingSourceID != source.id else { return }
        readTask?.cancel()
        readingSourceID = source.id
        readTask = Task { [weak self, browser] in
            do {
                let profiles = try await browser.readImport(source)
                guard !Task.isCancelled else { return }
                self?.previews[source.id] = profiles
            } catch {
                guard !Task.isCancelled else { return }
                if self?.selectedSourceID == source.id {
                    self?.readFailure = String(localized: "\(source.name)’s data could not be read. Quit \(source.name) and try again.")
                }
            }
            if self?.readingSourceID == source.id { self?.readingSourceID = nil }
        }
    }

    // MARK: - Navigation

    var canContinue: Bool {
        switch step {
        case .source: selectedSourceID == nil || (!needsFullDiskAccess && preview != nil)
        case .importing: !isImporting
        default: true
        }
    }

    func next() {
        guard canContinue, let index = steps.firstIndex(of: step) else { return }
        if isLastStep { finish(); return }
        var target = steps[min(index + 1, steps.count - 1)]
        // Starting fresh has nothing to choose or import.
        if selectedSourceID == nil, target == .choice || target == .importing { if mode == .importOnly { finish(); return }; target = .gettingAround }
        move(to: target, forward: true)
        if target == .importing { startImport() }
    }

    /// Back is also the browser's Back command while the onboarding shows.
    var canGoBack: Bool { !isImporting && (steps.firstIndex(of: step) ?? 0) > 0 }

    func back() {
        guard let index = steps.firstIndex(of: step), index > 0, !isImporting else {
            if mode == .importOnly, !isImporting { finish() }
            return
        }
        var target = steps[index - 1]
        if selectedSourceID == nil, target == .choice || target == .importing { target = .source }
        // The import is not replayed by going back; its result stays.
        if target == .importing { target = .choice }
        move(to: target, forward: false)
    }

    private func move(to target: OnboardingStep, forward: Bool) {
        movesForward = forward
        step = target
        windEvent += 1
        if mode == .firstLaunch { browser.preferences.onboarding = OnboardingProgress(step: target, completed: false) }
    }

    /// Skipping or finishing: the onboarding never shows again for this store.
    func finish() {
        hasEnded = true
        readTask?.cancel()
        importTask?.cancel()
        if mode == .firstLaunch { browser.preferences.onboarding = OnboardingProgress(step: step, completed: true) }
        browser.endOnboarding()
    }

    // MARK: - Import

    private func startImport() {
        guard let source, let profiles = preview, !isImporting else { return }
        isImporting = true
        outcome = ImportOutcome()
        let choice = self.choice
        importTask = Task { [weak self, browser] in
            let result = await browser.applyImport(profiles, from: source, choice: choice) { progress in
                self?.outcome = progress
            }
            guard let self else { return }
            outcome = result
            isImporting = false
            windEvent += 1
        }
    }

    // MARK: - Full Disk Access

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Getting around

    /// The shortcuts the Getting around step teaches.
    static let taughtCommands: Set<BrowserCommand> = [.nextSpace, .previousSpace, .commandPalette, .toggleSidebar, .recentTab]

    /// Commands tried in the Getting around step are shown there instead of acting on the hidden browser.
    func tried(_ command: BrowserCommand) {
        triedShortcuts.insert(command)
        lastTried = lastTried == command && (command == .commandPalette || command == .toggleSidebar) ? nil : command
        if command == .recentTab { recentTabTries += 1 }
        windEvent += 1
    }

    /// What the wind writes in the Getting around step: the last shortcut tried, or the space switched to.
    var lastShortcutSymbol: String {
        switch lastTried {
        case .commandPalette: "⌘K"
        case .toggleSidebar: "⌘S"
        case .recentTab: "⌃⇥"
        case .nextSpace, .previousSpace: browser.space?.name ?? "⌃⌘→"
        default: "⌘"
        }
    }

    // MARK: - Default browser

    static var isDefault: Bool {
        guard let web = URL(string: "https://example.com"), let handler = NSWorkspace.shared.urlForApplication(toOpen: web) else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// macOS asks the person; only its answer, read back from the system, counts.
    func makeDefaultBrowser() async {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
        } catch {}
        isDefaultBrowser = Self.isDefault
        windEvent += 1
    }
}
