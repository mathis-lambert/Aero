import BrowserCore
import Foundation

extension BrowserModel {
    func showSettings(_ route: SettingsRoute) {
        window.settingsRoute = route
        window.settingsRequest = UUID()
    }

    func setDeveloperMode(_ enabled: Bool) {
        preferences.developerMode = enabled
        applyDeveloperMode()
    }

    /// Pages and extensions can be inspected from their context menu. See docs/BROWSING.md › Developer mode.
    func applyDeveloperMode() {
        pages.pagesAreInspectable = preferences.developerMode
        extensions.isInspectable = preferences.developerMode
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard !isChangingStructure else { return }
        do { try session.editProfile(id: id, name: name); persist() }
        catch { structureFailure() }
    }

    func renameSpace(_ id: UUID, to name: String) {
        guard !isChangingStructure, let space = session.spaces.first(where: { $0.id == id }) else { return }
        do {
            try session.editSpace(id: id, name: name, profileID: space.profileID, color: space.color, emoji: space.emoji)
            persist()
        } catch { structureFailure() }
    }

    func setSpaceAppearance(_ id: UUID, color: SpaceColor, emoji: String) {
        guard !isChangingStructure, let space = session.spaces.first(where: { $0.id == id }) else { return }
        do {
            try session.editSpace(id: id, name: space.name, profileID: space.profileID, color: color, emoji: emoji.isEmpty ? nil : emoji)
            persist()
        } catch { structureFailure() }
    }
}
