import BrowserExtensions
import Foundation
import UserNotifications

/// Routes macOS notification responses to their extension. Test runs never touch the person's notification settings:
/// for them notifications are turned off, as the person could have chosen.
@MainActor
final class ExtensionNotifications: NSObject, UNUserNotificationCenterDelegate {
    enum Failure: LocalizedError {
        case notAllowed

        var errorDescription: String? { "Notifications are turned off for Aero." }
    }

    nonisolated private static let buttonAction = "button-"
    nonisolated private static let profileKey = "profile", extensionKey = "extension", identifierKey = "identifier"

    weak var browser: BrowserModel?
    private let isTestRun: Bool
    private var categories: Set<String> = []

    init(isTestRun: Bool) {
        self.isTestRun = isTestRun
        super.init()
        if !isTestRun { UNUserNotificationCenter.current().delegate = self }
    }

    func show(_ notification: ExtensionNotification) async throws {
        guard !isTestRun else { throw Failure.notAllowed }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw Failure.notAllowed }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.extensionName
        content.body = notification.message
        content.threadIdentifier = notification.extensionID
        content.userInfo = [Self.profileKey: notification.profileID.uuidString, Self.extensionKey: notification.extensionID,
                            Self.identifierKey: notification.identifier]
        content.categoryIdentifier = await category(for: notification.buttons)
        if let image = notification.image, let attachment = try? attachment(copying: image) { content.attachments = [attachment] }
        let request = UNNotificationRequest(identifier: Self.requestIdentifier(notification.identifier, notification.extensionID, notification.profileID),
                                            content: content, trigger: nil)
        try await center.add(request)
    }

    func isAllowed() async -> Bool {
        guard !isTestRun else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus != .denied
    }

    func remove(_ identifier: String, of extensionID: String, inProfile profileID: UUID) {
        guard !isTestRun else { return }
        let request = Self.requestIdentifier(identifier, extensionID, profileID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [request])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [request])
    }

    func shown(of extensionID: String, inProfile profileID: UUID) async -> Set<String> {
        guard !isTestRun else { return [] }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        return Set(delivered.compactMap { notification in
            let info = notification.request.content.userInfo
            guard info[Self.extensionKey] as? String == extensionID, info[Self.profileKey] as? String == profileID.uuidString else { return nil }
            return info[Self.identifierKey] as? String
        })
    }

    private static func requestIdentifier(_ identifier: String, _ extensionID: String, _ profileID: UUID) -> String {
        "\(profileID.uuidString)/\(extensionID)/\(identifier)"
    }

    /// The system moves an attachment's file into its own store: it gets a copy, never the package's file.
    private func attachment(copying file: URL) throws -> UNNotificationAttachment {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(file.pathExtension)")
        try FileManager.default.copyItem(at: file, to: copy)
        return try UNNotificationAttachment(identifier: "image", url: copy)
    }

    /// A category per set of button titles, registered once, which also reports dismissals.
    private func category(for buttons: [String]) async -> String {
        let identifier = "extension:" + buttons.joined(separator: "\u{1F}")
        guard !categories.contains(identifier) else { return identifier }
        categories.insert(identifier)
        let actions = buttons.enumerated().map { UNNotificationAction(identifier: Self.buttonAction + String($0.offset), title: $0.element) }
        let category = UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: [], options: [.customDismissAction])
        let center = UNUserNotificationCenter.current()
        let registered = await center.notificationCategories()
        center.setNotificationCategories(registered.union([category]))
        return identifier
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let profile = (info[Self.profileKey] as? String).flatMap(UUID.init(uuidString:)), let extensionID = info[Self.extensionKey] as? String,
              let identifier = info[Self.identifierKey] as? String else { return }
        let action = response.actionIdentifier
        let reply: ProfileExtensions.NotificationResponse
        if action == UNNotificationDismissActionIdentifier { reply = .dismissed }
        else if action.hasPrefix(Self.buttonAction), let index = Int(action.dropFirst(Self.buttonAction.count)) { reply = .button(index) }
        else { reply = .clicked }
        await MainActor.run {
            browser?.extensions.extensionsIfMade(for: profile)?.notification(identifier, of: extensionID, didReceive: reply)
        }
    }
}
