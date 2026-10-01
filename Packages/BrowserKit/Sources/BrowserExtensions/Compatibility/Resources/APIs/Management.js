// An extension knows itself; with the management permission, the profile's other extensions too.
define("management", {
    getSelf: () => method(() => call("management/self")),
    uninstallSelf: () => method((options) => call("management/uninstallSelf", options ?? {})),
    getAll: () => method(() => call("management/all")),
    get: () => method((id) => call("management/get", { id })),
    setEnabled: () => method((id, enabled) => call("management/setEnabled", { id, enabled })),
    uninstall: () => method((id, options) => call("management/uninstall", { id, ...(options ?? {}) })),
    onInstalled: () => deliveredEvent("management.onInstalled"),
    onUninstalled: () => deliveredEvent("management.onUninstalled"),
    onEnabled: () => deliveredEvent("management.onEnabled"),
    onDisabled: () => deliveredEvent("management.onDisabled"),
    ExtensionType: constants(["extension", "hosted_app", "packaged_app", "legacy_packaged_app", "theme", "login_screen_extension"]),
    ExtensionInstallType: constants(["admin", "development", "normal", "sideload", "other"])
});
