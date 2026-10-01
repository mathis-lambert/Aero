const speechEvents = deliveredEvent("tts.onEvent");
const speechCallbacks = new Map();
let nextSpeechRequest = 0;
const terminalSpeechEvents = new Set(["end", "interrupted", "cancelled", "error"]);
const receiveSpeech = (requestID, event) => {
    const callback = speechCallbacks.get(requestID);
    if (terminalSpeechEvents.has(event.type)) {
        speechCallbacks.delete(requestID);
        if (speechCallbacks.size === 0) speechEvents.removeListener(receiveSpeech);
    }
    callback?.(event);
};
define("tts", {
    speak: () => method(async (text, options = {}) => {
        if (typeof text !== "string" || !options || typeof options !== "object" || Array.isArray(options)) throw new Error("Invalid speech request.");
        if (options.onEvent !== undefined && typeof options.onEvent !== "function") throw new Error("onEvent must be a function.");
        const requestID = `${api.runtime.id}:${Date.now()}:${++nextSpeechRequest}`;
        const {onEvent, ...settings} = options;
        if (onEvent) {
            speechCallbacks.set(requestID, onEvent);
            speechEvents.addListener(receiveSpeech);
        }
        try { await call("tts/speak", {text, options: settings, requestID}); }
        catch (error) {
            speechCallbacks.delete(requestID);
            if (speechCallbacks.size === 0) speechEvents.removeListener(receiveSpeech);
            throw error;
        }
    }),
    stop: () => method(() => call("tts/stop")),
    pause: () => method(() => call("tts/pause")),
    resume: () => method(() => call("tts/resume")),
    isSpeaking: () => method(() => call("tts/speaking")),
    getVoices: () => method(() => call("tts/voices")),
    onVoicesChanged: () => deliveredEvent("tts.onVoicesChanged"),
    EventType: constants(["start", "end", "word", "sentence", "marker", "interrupted", "cancelled", "error", "pause", "resume"])
});
