import Foundation
import WebKit

/// Whether an extension runs as it should, and what it cannot do in Aero.
public struct ExtensionStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running
        /// Its background could not start, so most of it does nothing; `reason` is its own error.
        case failed(reason: String)
    }

    public let state: State
    /// Errors its scripts reported, most recent last.
    public let errors: [String]
    public let unavailableFeatures: [ExtensionFeature]

    private static let maximumErrors = 20

    @MainActor
    init(context: WKWebExtensionContext) {
        let manifestErrors = Set(context.webExtension.errors.map(\.localizedDescription))
        let reported = context.errors.filter { !manifestErrors.contains($0.localizedDescription) }
        let failed = reported.contains { error in
            let error = error as NSError
            return error.domain == WKWebExtensionContext.errorDomain && error.code == WKWebExtensionContext.Error.backgroundContentFailedToLoad.rawValue
        }
        let messages = reported.compactMap { error -> String? in
            let error = error as NSError
            return error.domain == WKWebExtensionContext.errorDomain ? nil : error.localizedDescription
        }
        errors = Array(messages.suffix(Self.maximumErrors))
        state = failed ? .failed(reason: messages.last ?? "") : .running
        unavailableFeatures = ExtensionCapabilities.unavailableFeatures(of: context.webExtension.manifest)
    }
}
