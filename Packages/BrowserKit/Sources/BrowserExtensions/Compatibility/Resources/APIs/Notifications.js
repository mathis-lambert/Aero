define("notifications", {
    create: () => method((first, second) => typeof first === "string"
        ? call("notifications/create", { id: first, options: second ?? {} })
        : call("notifications/create", { id: "", options: first ?? {} })),
    update: () => method((id, options) => call("notifications/update", { id, options: options ?? {} })),
    clear: () => method((id) => call("notifications/clear", { id })),
    getAll: () => method(() => call("notifications/all")),
    getPermissionLevel: () => method(() => call("notifications/permissionLevel")),
    onClicked: () => deliveredEvent("notifications.onClicked"),
    onClosed: () => deliveredEvent("notifications.onClosed"),
    onButtonClicked: () => deliveredEvent("notifications.onButtonClicked"),
    onPermissionLevelChanged: () => deliveredEvent("notifications.onPermissionLevelChanged"),
    // Chrome shows no settings button in notifications on macOS.
    onShowSettings: inertEvent,
    TemplateType: constants(["basic", "image", "list", "progress"]),
    PermissionLevel: constants(["granted", "denied"])
});
