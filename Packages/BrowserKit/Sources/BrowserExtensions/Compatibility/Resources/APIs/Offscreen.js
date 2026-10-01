define("offscreen", {
    createDocument: () => method((parameters) => call("offscreen/create", {
        url: absolute(parameters?.url ?? ""), reasons: parameters?.reasons ?? [], justification: parameters?.justification ?? ""
    })),
    closeDocument: () => method(() => call("offscreen/close")),
    hasDocument: () => method(() => call("offscreen/has")),
    Reason: constants(["testing", "audio_playback", "iframe_scripting", "dom_scraping", "blobs", "dom_parser", "user_media", "display_media",
        "web_rtc", "clipboard", "local_storage", "workers", "battery_status", "match_media", "geolocation"])
});
