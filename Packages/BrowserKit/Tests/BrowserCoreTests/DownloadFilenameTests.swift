import Testing
@testable import BrowserCore

// Failure modes 1 and 2 in docs/BROWSING.md › Downloads.

private let fallback = "Download"

private func name(_ suggested: String, taken: Set<String> = []) -> String {
    DownloadFilename.available(suggested: suggested, fallback: fallback) { taken.contains($0) }
}

@Test func suggestedNamesCannotEscapeOrHide() {
    #expect(name("../../evil.csv") == "evil.csv")
    #expect(name("folder/b:c.txt") == "b-c.txt")
    #expect(name(".hidden") == "hidden")
    #expect(name("   ") == fallback)
    #expect(name("") == fallback)
    #expect(name("...") == fallback)
}

@Test func existingFilesAreNeverOverwritten() {
    #expect(name("report.csv", taken: ["report.csv"]) == "report 2.csv")
    #expect(name("report.csv", taken: ["report.csv", "report 2.csv"]) == "report 3.csv")
    #expect(name("README", taken: ["README"]) == "README 2")
}

@Test func longNamesKeepTheirExtensionWithinTheFileSystemLimit() {
    let long = String(repeating: "é", count: 300) + ".pdf"
    let result = name(long)
    #expect(result.hasSuffix(".pdf"))
    #expect(result.utf8.count <= DownloadFilename.maximumByteCount)
    let numbered = name(long, taken: [result])
    #expect(numbered.hasSuffix(" 2.pdf"))
    #expect(numbered.utf8.count <= DownloadFilename.maximumByteCount)
}
