import Foundation

/// Strong passwords for new accounts. See docs/PASSWORDS.md › Strong passwords.
public enum PasswordGenerator {
    /// Letters and digits that cannot be mistaken for one another when read aloud or copied by hand.
    private static let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let groups = 3
    private static let groupLength = 6

    /// Three groups of six, joined by hyphens, with lowercase, uppercase and a digit: 20 characters.
    public static func strongPassword() -> String {
        var generator = SystemRandomNumberGenerator()
        return strongPassword(using: &generator)
    }

    public static func strongPassword<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        while true {
            let characters = (0..<groups * groupLength).map { _ in alphabet[Int.random(in: alphabet.indices, using: &generator)] }
            guard characters.contains(where: \.isLowercase), characters.contains(where: \.isUppercase), characters.contains(where: \.isNumber) else { continue }
            return stride(from: 0, to: characters.count, by: groupLength)
                .map { String(characters[$0..<$0 + groupLength]) }
                .joined(separator: "-")
        }
    }
}
