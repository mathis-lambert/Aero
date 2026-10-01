define("history", {
    search: () => method((query) => call("history/search", query)),
    getVisits: () => method((details) => call("history/visits", details)),
    addUrl: () => method((details) => call("history/add", details)),
    deleteUrl: () => method((details) => call("history/deleteURL", details)),
    deleteRange: () => method((range) => call("history/deleteRange", range)),
    deleteAll: () => method(() => call("history/deleteAll")),
    onVisited: () => deliveredEvent("history.onVisited"),
    onVisitRemoved: () => deliveredEvent("history.onVisitRemoved")
});
define("topSites", {get: () => method(() => call("topSites/get"))});
