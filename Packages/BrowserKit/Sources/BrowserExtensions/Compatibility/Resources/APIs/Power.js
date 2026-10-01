define("power", {
    requestKeepAwake: () => method((level) => call("power/request", {level})),
    releaseKeepAwake: () => method(() => call("power/release")),
    reportActivity: () => method(() => call("power/activity"))
});
