define("idle", {
    queryState: () => method((detectionIntervalInSeconds) => call("idle/state", { interval: detectionIntervalInSeconds })),
    setDetectionInterval: () => (intervalInSeconds) => { call("idle/interval", { interval: intervalInSeconds }).catch(console.error); },
    onStateChanged: () => deliveredEvent("idle.onStateChanged"),
    IdleState: constants(["active", "idle", "locked"])
});
