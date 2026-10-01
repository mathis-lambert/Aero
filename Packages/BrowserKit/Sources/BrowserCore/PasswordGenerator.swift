import Foundation

/// Strong passwords for new accounts, in the format of Safari's: three groups of six letters and digits joined by
/// hyphens, 20 characters, with lowercase, uppercase and a digit. See docs/PASSWORDS.md › Strong passwords.
public enum PasswordGenerator {
    /// Letters and digits that cannot be mistaken for one another when read aloud or copied by hand.
    private static let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let groups = 3
    private static let groupLength = 6

    /// From the system's cryptographically secure generator.
    public static func strongPassword() -> String {
        var generator = SystemRandomNumberGenerator()
        while true {
            let characters = (0..<groups * groupLength).map { _ in alphabet[Int.random(in: alphabet.indices, using: &generator)] }
            guard characters.contains(where: \.isLowercase), characters.contains(where: \.isUppercase), characters.contains(where: \.isNumber) else { continue }
            return stride(from: 0, to: characters.count, by: groupLength)
                .map { String(characters[$0..<$0 + groupLength]) }
                .joined(separator: "-")
        }
    }
}
