import Foundation

/// Turns a server-suggested name into a safe, unused file name, the way Finder numbers copies.
public enum DownloadFilename {
    /// APFS limit for one path component.
    public static let maximumByteCount = 255
    private static let maximumNumberedCopies = 9_999

    public static func available(suggested: String, fallback: String, isTaken: (String) -> Bool) -> String {
        let name = sanitized(suggested) ?? sanitized(fallback) ?? UUID().uuidString
        let pathExtension = (name as NSString).pathExtension
        let stem = pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        let fileExtension = pathExtension.isEmpty ? "" : "." + pathExtension
        let original = fit(stem, suffix: fileExtension)
        guard isTaken(original) else { return original }
        for copy in 2...maximumNumberedCopies {
            let candidate = fit(stem, suffix: " \(copy)" + fileExtension)
            if !isTaken(candidate) { return candidate }
        }
        return fit(stem, suffix: " " + UUID().uuidString + fileExtension)
    }

    /// Keeps the last path component, replaces the separators Finder shows as slashes, and drops
    /// control characters and leading dots, which would hide the file.
    private static func sanitized(_ name: String) -> String? {
        let component = name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let cleaned = component
            .replacingOccurrences(of: ":", with: "-")
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
            .drop { $0 == "." }
        return cleaned.isEmpty ? nil : String(cleaned)
    }

    private static func fit(_ stem: String, suffix: String) -> String {
        var stem = stem
        while (stem + suffix).utf8.count > maximumByteCount, !stem.isEmpty { stem.removeLast() }
        return stem + suffix
    }
}
