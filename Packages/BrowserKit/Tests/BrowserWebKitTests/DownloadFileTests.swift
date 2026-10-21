import Foundation
import Testing
import WebKit
@testable import BrowserWebKit

// Failure modes of acting on a downloaded file: a rename replaces another file, moves the file out of Downloads, or
// refuses a change of case as a taken name; a file already gone keeps its download listed when moved to the Trash.
// Needs access to macOS WebKit services.
@MainActor
@Test func renamingAFileNeverReplacesAnotherAndTrashingAMissingOneDelists() async throws {
    let server = try HistoryPageServer(response: """
        HTTP/1.1 200 OK\r
        Content-Type: application/octet-stream\r
        Content-Disposition: attachment; filename="report.txt"\r
        Content-Length: 5\r
        Connection: close\r
        \r
        hello
        """)
    let downloads = makeTestDownloads()
    defer { try? FileManager.default.removeItem(at: downloads.directory) }
    let download = await downloads.start(URLRequest(url: server.url), in: .nonPersistent(), filename: nil)
    let deadline = ContinuousClock.now + .seconds(10)
    while download.state == .downloading, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    try #require(download.state == .finished)
    let folder = downloads.directory
    let other = folder.appending(path: "taken.txt")
    try Data("keep".utf8).write(to: other)

    #expect(throws: DownloadRenameError.nameTaken) { try downloads.rename(download, to: "taken.txt") }
    #expect(try String(contentsOf: other, encoding: .utf8) == "keep")
    #expect(throws: DownloadRenameError.invalidName) { try downloads.rename(download, to: " .. ") }

    try downloads.rename(download, to: "../notes.txt")
    #expect(download.destination == folder.appending(path: "notes.txt"), "It stays in Downloads")
    #expect(try String(contentsOf: folder.appending(path: "notes.txt"), encoding: .utf8) == "hello")
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "report.txt").path))

    try downloads.rename(download, to: "Notes.txt")
    #expect(download.filename == "Notes.txt")
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("Notes.txt"))

    try FileManager.default.removeItem(at: folder.appending(path: "Notes.txt"))
    #expect(throws: DownloadRenameError.fileMissing) { try downloads.rename(download, to: "again.txt") }
    try downloads.moveToTrash(download)
    #expect(downloads.downloads.isEmpty)
}
