import AppKit
import BrowserCore
import BrowserStorage
import BrowserWebKit
import Foundation

/// Page reports and window answers, applied only while their tab still exists. See docs/PASSWORDS.md.
extension BrowserModel {
    func page(_ tabID: UUID, passwordForm event: PasswordFormEvent, in frame: PasswordFrame) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }), let profileID = profileID(of: tab) else { return }
        switch event {
        case .focused(let field, let placement):
            // Only the tab in front, and only a page that may have logins: never a browser page.
            guard tabID == window.selectedTabID, NavigationInput.isWebURL(tab.url) else { return }
            passwords.fieldFocused(field, placement: placement, in: frame, tabID: tabID, profileID: profileID) { [weak self] in
                self?.window.selectedTabID == tabID
            }
        case .blurred:
            passwords.fieldBlurred(tabID: tabID)
        case .typed:
            passwords.fieldTyped(tabID: tabID)
        case .usernameSubmitted(let username):
            guard tabID == window.selectedTabID,
                  decision(for: .savePasswords, at: frame.origin, profileID: profileID) != .block else { return }
            passwords.usernameSubmitted(username, tabID: tabID, profileID: profileID, origin: frame.origin)
        case .submitted(let username, let password):
            guard tabID == window.selectedTabID,
                  decision(for: .savePasswords, at: frame.origin, profileID: profileID) != .block else { return }
            passwords.submitted(LoginRecord(origin: frame.origin, username: username, password: password), tabID: tabID, profileID: profileID) { [weak self] in
                guard let self, self.window.selectedTabID == tabID,
                      let current = self.session.tabs.first(where: { $0.id == tabID }) else { return false }
                return self.profileID(of: current) == profileID
            }
        }
    }

    /// The offer's answer. Never for this site is the site's Save passwords decision, like any other permission.
    func answerPasswordOffer(_ answer: PasswordOfferAnswer) {
        guard let offer = passwords.offer, !passwords.isSavingOffer else { return }
        switch answer {
        case .save: Task { await passwords.acceptOffer() }
        case .never:
            passwords.offer = nil
            guard !isChangingStructure else { return }
            session.setDecision(.block, for: .savePasswords, at: offer.record.origin, profileID: offer.profileID)
            persist()
        case .notNow: passwords.offer = nil
        }
    }

    func fillPassword(_ login: SavedLogin) {
        guard let page = currentPage, passwords.picker?.tabID == window.selectedTabID else { return }
        Task { await passwords.fill(login, into: page) }
    }

    func fillSuggestedPassword() {
        guard let page = currentPage, passwords.picker?.tabID == window.selectedTabID else { return }
        Task { await passwords.fillSuggestion(into: page) }
    }

    /// Imports a Chromium browser's passwords into `profileID`; its never-save sites become Block decisions.
    func importPasswords(from source: ChromiumProfile, into profileID: UUID) async -> PasswordImportResult {
        do {
            let imported = try await Task.detached(priority: .userInitiated) { try ChromiumLogins.read(source) }.value
            var result = await passwords.save(imported.logins, into: profileID)
            result.skipped += imported.skipped
            if !imported.neverSaved.isEmpty, !isChangingStructure, session.profiles.contains(where: { $0.id == profileID }) {
                for origin in imported.neverSaved { session.setDecision(.block, for: .savePasswords, at: origin, profileID: profileID) }
                persist()
            }
            return result
        } catch ChromiumImportError.keyUnavailable {
            return PasswordImportResult(failure: String(localized: "macOS did not allow Aero to read \(source.browser.name)’s passwords."))
        } catch {
            return PasswordImportResult(failure: String(localized: "\(source.browser.name)’s passwords could not be read."))
        }
    }
}

enum PasswordOfferAnswer { case save, never, notNow }

/// What an import did, for Settings to report.
struct PasswordImportResult: Equatable {
    var added = 0
    var present = 0
    var skipped = 0
    var failure: String?
}

extension Passwords {
    /// Saves imported logins without replacing a different saved password.
    func save(_ logins: [LoginRecord], into profileID: UUID) async -> PasswordImportResult {
        var result = PasswordImportResult()
        for login in logins {
            do {
                switch try await store.save(login, profileID: profileID, replacing: false) {
                case .added: result.added += 1
                case .unchanged, .kept, .updated: result.present += 1
                }
            } catch {
                result.failure = Passwords.message(for: error)
                return result
            }
        }
        return result
    }

    /// What the window and Settings say when the keychain fails, never an empty list instead.
    static func message(for error: any Error) -> String {
        switch error as? PasswordStoreError {
        case .locked: String(localized: "The keychain is locked. Unlock your Mac, then try again.")
        case .denied: String(localized: "Access to the keychain was not allowed.")
        case .duplicate: String(localized: "This account already has a saved password for this site.")
        case .deletedProfile: String(localized: "This profile was deleted before its passwords could be saved.")
        default: String(localized: "The keychain could not be used. Try again.")
        }
    }
}
