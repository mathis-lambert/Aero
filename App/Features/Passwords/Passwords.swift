import AppKit
import BrowserCore
import BrowserStorage
import BrowserWebKit
import Foundation
import LocalAuthentication
import Observation

/// The account list under a focused sign-in field. See docs/PASSWORDS.md › Filling.
struct PasswordPicker: Identifiable {
    let id = UUID()
    let tabID: UUID
    let frame: PasswordFrame
    let field: PasswordField
    /// Where the field is in the page, in points; `nil` for a frame that could not say.
    let placement: CGRect?
    let logins: [SavedLogin]
    /// Offered on new-password fields.
    let suggestion: String?
}

/// A submitted credential waiting for the person's answer, attached to its tab. See docs/PASSWORDS.md › Saving.
struct PasswordOffer: Identifiable {
    let id = UUID()
    let tabID: UUID
    let profileID: UUID
    let record: LoginRecord
    let isUpdate: Bool
}

/// Filling and saving passwords for the browser window. Passwords stay in the keychain: this holds
/// one pending credential and the list on screen, nothing else.
@MainActor @Observable
final class Passwords {
    /// How long a field may lose focus before its list closes: a click on the list takes focus from the page.
    private static let dismissDelay = Duration.milliseconds(250)
    private static let usernameStepLifetime: TimeInterval = 5 * 60

    private struct UsernameStep {
        let username: String
        let origin: SiteOrigin
        let profileID: UUID
        let submittedAt: Date
    }

    let store: PasswordStore
    private let testing: Bool
    private(set) var suffixes: PublicSuffixList?
    var picker: PasswordPicker?
    var offer: PasswordOffer?
    private(set) var isSavingOffer = false
    /// The pointer is over the list, which keeps it open while the page loses focus to a click on it.
    @ObservationIgnored private var isPointerInPicker = false
    /// A keychain error shown in the browser window until dismissed.
    var failure: String?
    /// Until when showing and exporting passwords needs no new authentication.
    @ObservationIgnored var authorizedUntil: Date?
    @ObservationIgnored private var pickerRequest = 0
    @ObservationIgnored private var pickerTabID: UUID?
    @ObservationIgnored private var pickerBlurred = false
    @ObservationIgnored private var submissionRequest = 0
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private var usernameSteps: [UUID: UsernameStep] = [:]

    init(testNamespace: String?) {
        let bundle = Bundle.main.bundleIdentifier ?? "app.getaero.browser"
        store = PasswordStore(namespace: testNamespace.map { "\(bundle).tests.\($0)" } ?? bundle, testing: testNamespace != nil)
        testing = testNamespace != nil
    }

    /// Loads the Public Suffix List off the main actor; until then only exact origins match.
    func start() async {
        let testing = testing, store = store
        if testing { try? await store.removeItemsOfOtherTestRuns() }
        suffixes = await Task.detached(priority: .utility) {
            guard let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return PublicSuffixList(rules: text)
        }.value
    }

    // MARK: - Filling

    /// The saved logins the frame may be offered, and a strong password for a new-password field.
    /// `isShown` is asked again once the keychain answers: the tab may have been left meanwhile.
    func fieldFocused(_ field: PasswordField, placement: CGRect?, in frame: PasswordFrame, tabID: UUID, profileID: UUID, isShown: @escaping @MainActor () -> Bool) {
        dismissal?.cancel()
        pickerRequest += 1
        pickerTabID = tabID
        pickerBlurred = false
        picker = nil
        isPointerInPicker = false
        let request = pickerRequest
        Task {
            let logins = field == .newPassword ? [] : await candidates(for: frame.origin, profileID: profileID)
            guard request == pickerRequest, isShown() else { return }
            let suggestion = field == .newPassword ? PasswordGenerator.strongPassword() : nil
            picker = logins.isEmpty && suggestion == nil ? nil
                : PasswordPicker(tabID: tabID, frame: frame, field: field, placement: placement, logins: logins, suggestion: suggestion)
            if picker == nil { pickerTabID = nil }
        }
    }

    func fieldBlurred(tabID: UUID) {
        guard pickerTabID == tabID else { return }
        pickerRequest += 1
        pickerBlurred = true
        dismissal?.cancel()
        guard picker != nil else { pickerTabID = nil; return }
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: Self.dismissDelay) } catch { return }
            guard let self, !self.isPointerInPicker else { return }
            self.picker = nil
            self.pickerTabID = nil
        }
    }

    /// Typing or Escape in the field: the list closes, including one still being prepared.
    func fieldTyped(tabID: UUID) {
        if pickerTabID == tabID { closePicker() }
    }

    func pickerHoverChanged(_ hovering: Bool, for id: UUID) {
        guard picker?.id == id else { return }
        isPointerInPicker = hovering
        if !hovering && pickerBlurred { closePicker() }
    }

    /// Closes the list when its tab stops being shown or navigates.
    func closePicker(unless tabID: UUID? = nil) {
        guard pickerTabID != tabID else { return }
        pickerRequest += 1
        pickerTabID = nil
        pickerBlurred = false
        picker = nil
        isPointerInPicker = false
    }

    /// A navigation also invalidates a keychain lookup that has not displayed its list yet.
    func pageNavigated(tabID: UUID) {
        if pickerTabID == tabID { closePicker() }
    }

    /// Fills the chosen login into the frame that asked, then records its use.
    func fill(_ login: SavedLogin, into page: BrowserPage) async {
        guard let picker else { return }
        closePicker()
        let request = pickerRequest
        do {
            let password = try await store.password(for: login)
            guard request == pickerRequest else { return }
            if await page.fillLogin(username: login.username, password: password, in: picker.frame) { try await store.markUsed(login) }
        } catch { failure = Self.message(for: error) }
    }

    func fillSuggestion(into page: BrowserPage) async {
        guard let picker, let suggestion = picker.suggestion else { return }
        closePicker()
        _ = await page.fillNewPassword(suggestion, in: picker.frame)
    }

    private func candidates(for origin: SiteOrigin, profileID: UUID) async -> [SavedLogin] {
        do {
            let logins = try await store.logins(profileID: profileID)
            guard let suffixes else { return logins.filter { $0.origin == origin } }
            return LoginMatching.candidates(logins, for: origin, suffixes: suffixes)
        } catch {
            failure = Self.message(for: error)
            return []
        }
    }

    // MARK: - Saving

    /// A username-only step waits in memory for the password step of the same tab, profile and origin.
    func usernameSubmitted(_ username: String, tabID: UUID, profileID: UUID, origin: SiteOrigin) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { usernameSteps.removeValue(forKey: tabID); return }
        usernameSteps[tabID] = UsernameStep(username: username, origin: origin, profileID: profileID, submittedAt: .now)
    }

    /// Offers to save or update what was submitted; an unchanged password only records its use.
    /// `isOpen` is asked again once the keychain answers, so a closed tab never gets an offer.
    func submitted(_ record: LoginRecord, tabID: UUID, profileID: UUID, isOpen: @escaping @MainActor () -> Bool) {
        submissionRequest += 1
        let request = submissionRequest
        offer = nil
        let step = usernameSteps.removeValue(forKey: tabID)
        var record = record
        if let step, record.username.isEmpty, step.origin == record.origin, step.profileID == profileID,
           Date.now.timeIntervalSince(step.submittedAt) <= Self.usernameStepLifetime {
            record = LoginRecord(origin: record.origin, username: step.username, password: record.password)
        }
        Task {
            do {
                let saved = try await store.logins(profileID: profileID).first { $0.origin == record.origin && $0.username == record.username }
                if let saved {
                    if try await store.password(for: saved) == record.password {
                        if request == submissionRequest { try await store.markUsed(saved) }
                        return
                    }
                }
                guard request == submissionRequest, isOpen() else { return }
                offer = PasswordOffer(tabID: tabID, profileID: profileID, record: record, isUpdate: saved != nil)
            } catch {
                if request == submissionRequest { failure = Self.message(for: error) }
            }
        }
    }

    func acceptOffer() async {
        guard let offer, !isSavingOffer else { return }
        isSavingOffer = true
        defer {
            isSavingOffer = false
            if self.offer?.id == offer.id { self.offer = nil }
        }
        do {
            try await store.save(offer.record, profileID: offer.profileID)
            try await store.markUsed(SavedLogin(profileID: offer.profileID, origin: offer.record.origin, username: offer.record.username))
        } catch { failure = Self.message(for: error) }
    }

    /// The tab is gone: its pending credential and list go with it.
    func forget(tabID: UUID) {
        usernameSteps.removeValue(forKey: tabID)
        submissionRequest += 1
        if offer?.tabID == tabID { offer = nil }
        pageNavigated(tabID: tabID)
    }
}


extension Passwords {
    /// How long one authentication shows and exports passwords.
    private static let authorizationWindow: TimeInterval = 5 * 60
    /// How long a copied password stays on the pasteboard.
    private static let pasteboardLifetime = Duration.seconds(60)

    /// The Mac owner's Touch ID or password, remembered for a few minutes. A Mac without any
    /// authentication set has nothing to ask.
    func authorize(reason: String) async -> Bool {
        // E2E credentials live in a separate test keychain namespace and must not require a system prompt.
        if testing { return true }
        if let authorizedUntil, authorizedUntil > .now { return true }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return error?.code == LAError.passcodeNotSet.rawValue }
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true else { return false }
        authorizedUntil = .now.addingTimeInterval(Self.authorizationWindow)
        return true
    }

    /// Copies a password, then removes it from the pasteboard unless something else replaced it.
    func copyToPasteboard(_ password: String) {
        let pasteboard = NSPasteboard.general
        // Kept on this Mac: Universal Clipboard never carries a password to another device.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        pasteboard.setString(password, forType: .string)
        let change = pasteboard.changeCount
        Task {
            try? await Task.sleep(for: Self.pasteboardLifetime)
            if pasteboard.changeCount == change { pasteboard.clearContents() }
        }
    }
}
