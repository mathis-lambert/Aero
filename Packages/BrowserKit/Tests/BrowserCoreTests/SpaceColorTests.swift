import Testing
@testable import BrowserCore

// Color validation and round-trip persistence (docs/SPACES.md): a custom color is chosen in the system color panel,
// which UI tests cannot drive.
@Test func spaceColorsRoundTripThroughTheirStoredValue() {
    let color = SpaceColor(0x0AB3FF)
    #expect(color == SpaceColor(red: 0x0A, green: 0xB3, blue: 0xFF))
    #expect(color.hex == "#0AB3FF")
    #expect(SpaceColor(hex: "#0AB3FF") == color)
    #expect(SpaceColor(hex: "#0ab3ff") == color)
    #expect(SpaceColor(hex: SpaceColor.initial.hex) == .initial)
}

@Test func malformedStoredSpaceColorsAreRejected() {
    for value in ["", "#", "#12345", "#1234567", "#GG0000", "0AB3FF", " #0AB3FF", "#0AB3FF ", "#+1+2+3", "#１２３４５６", "terracotta"] {
        #expect(SpaceColor(hex: value) == nil, "\(value)")
    }
}
