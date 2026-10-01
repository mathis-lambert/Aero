define("identity", {
    getRedirectURL: () => (path = "") => `https://${api.runtime.id}.chromiumapp.org/${String(path).replace(/^\//, "")}`,
    launchWebAuthFlow: () => method((details) => call("identity/launch", details)),
    getProfileUserInfo: () => method(() => call("identity/profile")),
    getAccounts: () => method(() => call("identity/accounts")),
    getAuthToken: () => method((details) => call("identity/token", details ?? {})),
    removeCachedAuthToken: () => method((details) => call("identity/removeToken", details ?? {})),
    clearAllCachedAuthTokens: () => method(() => call("identity/clearTokens")),
    onSignInChanged: inertEvent
});
