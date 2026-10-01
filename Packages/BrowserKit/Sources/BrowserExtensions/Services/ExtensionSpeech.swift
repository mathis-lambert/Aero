import AVFAudio
import Foundation
import Synchronization

/// A profile's speech queue. Native callbacks carry identities and scalar event data across actors.
@MainActor
final class ExtensionSpeech: NSObject, AVSpeechSynthesizerDelegate {
    nonisolated static let eventTypes = ["start", "end", "word", "interrupted", "cancelled", "pause", "resume"]
    private static let maximumQueueLength = 256

    enum Failure: LocalizedError {
        case unavailableVoice, queueFull
        var errorDescription: String? {
            switch self {
            case .unavailableVoice: "No speech voice supports this request."
            case .queueFull: "The speech queue is full."
            }
        }
    }

    struct Request {
        let token = UUID()
        let extensionID: String
        let requestID: String
        let utterance: AVSpeechUtterance
        let desiredEvents: Set<String>?
        let enqueue: Bool

        init(_ body: [String: Any], extensionID: String) throws {
            guard let text = body["text"] as? String, text.utf16.count <= 32768,
                  let requestID = body["requestID"] as? String, !requestID.isEmpty else { throw ExtensionBridge.Failure.invalidRequest }
            if body["options"] != nil, !(body["options"] is [String: Any]) { throw ExtensionBridge.Failure.invalidRequest }
            let options = body["options"] as? [String: Any] ?? [:]
            func number(_ key: String, within range: ClosedRange<Double>, default fallback: Double) throws -> Float {
                guard let value = options[key] else { return Float(fallback) }
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, range.contains(number.doubleValue) else { throw ExtensionBridge.Failure.invalidRequest }
                return Float(number.doubleValue)
            }
            func string(_ key: String) throws -> String? {
                guard let value = options[key] else { return nil }
                guard let text = value as? String else { throw ExtensionBridge.Failure.invalidRequest }
                return text
            }
            func strings(_ key: String) throws -> Set<String>? {
                guard let value = options[key] else { return nil }
                guard let list = value as? [String] else { throw ExtensionBridge.Failure.invalidRequest }
                return Set(list)
            }
            if let engine = try string("extensionId"), !engine.isEmpty { throw Failure.unavailableVoice }
            if let required = try strings("requiredEventTypes"), !required.isSubset(of: Set(ExtensionSpeech.eventTypes)) { throw Failure.unavailableVoice }
            desiredEvents = try strings("desiredEventTypes")
            if let desiredEvents, !desiredEvents.isSubset(of: Set(Self.allEventTypes)) { throw ExtensionBridge.Failure.invalidRequest }
            let voiceName = try string("voiceName"), language = try string("lang")
            let voice: AVSpeechSynthesisVoice?
            if let voiceName, !voiceName.isEmpty {
                voice = AVSpeechSynthesisVoice.speechVoices().first { $0.name == voiceName && (language == nil || $0.language == language) }
                guard voice != nil else { throw Failure.unavailableVoice }
            } else if let language, !language.isEmpty {
                voice = AVSpeechSynthesisVoice(language: language)
                guard voice != nil else { throw Failure.unavailableVoice }
            } else { voice = nil }
            let utterance: AVSpeechUtterance
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<?xml") {
                guard let ssml = AVSpeechUtterance(ssmlRepresentation: text) else { throw ExtensionBridge.Failure.invalidRequest }
                utterance = ssml
            } else { utterance = AVSpeechUtterance(string: text) }
            utterance.voice = voice
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate,
                AVSpeechUtteranceDefaultSpeechRate * (try number("rate", within: 0.1...10, default: 1))))
            utterance.pitchMultiplier = max(0.5, try number("pitch", within: 0...2, default: 1))
            utterance.volume = try number("volume", within: 0...1, default: 1)
            if let value = options["enqueue"] {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw ExtensionBridge.Failure.invalidRequest }
            }
            enqueue = options["enqueue"] as? Bool ?? false
            self.extensionID = extensionID
            self.requestID = requestID
            self.utterance = utterance
        }

        private static let allEventTypes = ["start", "end", "word", "sentence", "marker", "interrupted", "cancelled", "error", "pause", "resume"]
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var current: Request?
    private var pending: [Request] = []
    // Delegate callbacks may arrive outside the main actor. Snapshot the request token
    // before crossing actors so a queued callback cannot identify a later utterance.
    nonisolated private let activeUtterances = Mutex<[ObjectIdentifier: UUID]>([:])
    var onEvent: ((String, String, [String: Any]) -> Void)?
    var onVoicesChanged: (() -> Void)?
    private var voiceObserver: (any NSObjectProtocol)?
    var isSpeaking: Bool { current != nil }

    override init() {
        super.init()
        synthesizer.delegate = self
        voiceObserver = NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onVoicesChanged?() }
        }
    }

    isolated deinit {
        if let voiceObserver { NotificationCenter.default.removeObserver(voiceObserver) }
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    static func voices() -> [[String: Any]] {
        AVSpeechSynthesisVoice.speechVoices().map { ["voiceName": $0.name, "lang": $0.language, "remote": false, "eventTypes": eventTypes] }
    }

    func speak(_ request: Request) throws {
        if !request.enqueue { stop() }
        guard pending.count < Self.maximumQueueLength else { throw Failure.queueFull }
        pending.append(request)
        startNext()
    }

    func pause() { synthesizer.pauseSpeaking(at: .immediate) }
    func resume() { synthesizer.continueSpeaking() }

    func stop() {
        let stopped = current
        current = nil
        let cancelled = pending
        pending.removeAll()
        activeUtterances.withLock { $0.removeAll() }
        synthesizer.stopSpeaking(at: .immediate)
        if let stopped { emit("interrupted", for: stopped) }
        for request in cancelled { emit("cancelled", for: request) }
    }

    func close(_ extensionID: String) {
        let cancelled = pending.filter { $0.extensionID == extensionID }
        pending.removeAll { $0.extensionID == extensionID }
        for request in cancelled { emit("cancelled", for: request) }
        if let stopped = current, stopped.extensionID == extensionID {
            current = nil
            _ = activeUtterances.withLock { $0.removeValue(forKey: ObjectIdentifier(stopped.utterance)) }
            synthesizer.stopSpeaking(at: .immediate)
            emit("interrupted", for: stopped)
            startNext()
        }
    }

    private func startNext() {
        guard current == nil, !pending.isEmpty else { return }
        current = pending.removeFirst()
        if let current {
            if current.utterance.speechString.isEmpty {
                emit("start", for: current)
                emit("end", for: current)
                self.current = nil
                startNext()
            } else {
                activeUtterances.withLock { $0[ObjectIdentifier(current.utterance)] = current.token }
                synthesizer.speak(current.utterance)
            }
        }
    }

    private func emit(_ type: String, for request: Request, index: Int = 0, length: Int? = nil) {
        let final = ["end", "interrupted", "cancelled", "error"].contains(type)
        guard final || request.desiredEvents == nil || request.desiredEvents?.contains(type) == true else { return }
        var event: [String: Any] = ["type": type, "charIndex": index]
        if let length { event["length"] = length }
        onEvent?(request.extensionID, request.requestID, event)
    }

    private func received(_ type: String, token: UUID, index: Int = 0, length: Int? = nil) {
        guard let current, current.token == token else { return }
        emit(type, for: current, index: type == "end" ? current.utterance.speechString.utf16.count : index, length: length)
        if type == "end" || type == "interrupted" {
            _ = activeUtterances.withLock { $0.removeValue(forKey: ObjectIdentifier(current.utterance)) }
            self.current = nil
            startNext()
        }
    }

    nonisolated private func receive(_ type: String, utterance: AVSpeechUtterance, index: Int = 0, length: Int? = nil) {
        guard let token = activeUtterances.withLock({ $0[ObjectIdentifier(utterance)] }) else { return }
        Task { @MainActor [weak self] in self?.received(type, token: token, index: index, length: length) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { receive("start", utterance: utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { receive("end", utterance: utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { receive("interrupted", utterance: utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) { receive("pause", utterance: utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) { receive("resume", utterance: utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        receive("word", utterance: utterance, index: range.location, length: range.length)
    }
}

extension ProfileExtensions {
    func speechService() -> ExtensionSpeech {
        if let speech { return speech }
        let speech = ExtensionSpeech()
        speech.onEvent = { [weak self] id, requestID, event in self?.deliver("tts.onEvent", [requestID, event], to: id) }
        speech.onVoicesChanged = { [weak self] in
            guard let self else { return }
            for id in self.contexts.keys where self.providedGrants[id]?.contains("tts") == true { self.deliver("tts.onVoicesChanged", [], to: id) }
        }
        self.speech = speech
        return speech
    }

    /// Ends the extension's speech, and the queue with the last extension that may speak.
    func closeSpeech(of extensionID: String) {
        speech?.close(extensionID)
        if !providedGrants.contains(where: { $0.key != extensionID && $0.value.contains("tts") }) { speech = nil }
    }

    func speechRequest(_ action: String, _ body: [String: Any], of extensionID: String) throws -> Any? {
        try require("tts", of: extensionID)
        switch action {
        case "speak": try speechService().speak(.init(body, extensionID: extensionID))
        case "stop": speech?.stop()
        case "pause": speech?.pause()
        case "resume": speech?.resume()
        case "speaking": return speech?.isSpeaking == true
        case "voices": return ExtensionSpeech.voices()
        default: throw ExtensionBridge.Failure.unknownRequest
        }
        return nil
    }
}
