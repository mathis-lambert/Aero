import BrowserCore
import Testing

// Failure modes: accepting truncated or oversized IDs, uppercase letters, digits or non-ASCII
// graphemes would disagree with the IDs derived from Chrome public keys and stored in profiles.
@Test(arguments: [String(repeating: "a", count: 32), String(repeating: "p", count: 32), "abcdefghijklmnopabcdefghijklmnop"])
func extensionIdentifiersUseTheChromeAlphabet(_ identifier: String) {
    #expect(InstalledExtension.isValidIdentifier(identifier))
}

@Test(arguments: ["", String(repeating: "a", count: 31), String(repeating: "a", count: 33),
                  String(repeating: "A", count: 32), String(repeating: "0", count: 32),
                  String(repeating: "q", count: 32), String(repeating: "a\u{301}", count: 32)])
func malformedExtensionIdentifiersAreRejected(_ identifier: String) {
    #expect(!InstalledExtension.isValidIdentifier(identifier))
}
