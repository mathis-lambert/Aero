import Foundation

/// Any sRGB color, stored as `#RRGGBB`. The app offers its presets; any other value is a custom color.
public struct SpaceColor: Hashable, Sendable {
    /// The color of a new session's first space.
    public static let initial = SpaceColor(0xB35236)

    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A `0xRRGGBB` literal.
    public init(_ rgb: UInt32) {
        self.init(red: UInt8(truncatingIfNeeded: rgb >> 16), green: UInt8(truncatingIfNeeded: rgb >> 8), blue: UInt8(truncatingIfNeeded: rgb))
    }

    /// Exactly `#` and six hexadecimal digits, in either case.
    public init?(hex: String) {
        let digits = hex.dropFirst()
        guard hex.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit), digits.allSatisfy(\.isASCII),
              let rgb = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb)
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

/// Organization only. Website identity comes from profileID.
public struct BrowserSpace: Identifiable, Equatable, Sendable {
    public static let maximumNameLength = 40
    public let id: UUID
    public package(set) var profileID: UUID
    public var name: String
    public var color: SpaceColor
    public var emoji: String?
    public package(set) var groups: [TabGroup] = []

    public init(id: UUID = UUID(), profileID: UUID, name: String = "Main", color: SpaceColor = .initial, emoji: String? = nil) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.color = color
        self.emoji = emoji
    }

    /// The single emoji `text` holds, ignoring surrounding spaces, or `nil`. Sequences (flags, skin
    /// tones, families, keycaps) count as one; digits and symbols that only have an emoji form with
    /// a variation selector need it.
    public static func emoji(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = value.unicodeScalars
        guard value.count == 1, let first = scalars.first, first.properties.isEmoji, !first.properties.isEmojiModifier else { return nil }
        return scalars.contains(where: \.properties.isEmojiPresentation) || scalars.count > 1 ? value : nil
    }
}
