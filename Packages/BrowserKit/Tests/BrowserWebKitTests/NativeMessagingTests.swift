import Foundation
import Testing
@testable import BrowserWebKit

// Failure modes 1–4, 7 and 8 in docs/EXTENSIONS.md › Native messaging. The echo host passes every frame
// back, which is the protocol's round trip.

private let extensionID = String(repeating: "a", count: 32)

private func folder(with manifests: [String: String]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aero-hosts-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, text) in manifests { try Data(text.utf8).write(to: folder.appendingPathComponent("\(name).json")) }
    return folder
}

private func manifest(name: String = "app.test.echo", path: String = "/bin/cat", type: String = "stdio", origin: String = "chrome-extension://\(extensionID)/") -> String {
    #"{"name": "\#(name)", "path": "\#(path)", "type": "\#(type)", "allowed_origins": ["\#(origin)"]}"#
}

@Test func aHostIsFoundOnlyWhenItsManifestIsValidAndListsTheExtension() throws {
    let folders = [try folder(with: [
        "app.test.echo": manifest(),
        "app.test.relative": manifest(name: "app.test.relative", path: "bin/cat"),
        "app.test.socket": manifest(name: "app.test.socket", type: "socket"),
        "app.test.broken": "{ not json",
        "app.test.other": manifest(name: "app.test.other", origin: "chrome-extension://\(String(repeating: "b", count: 32))/")
    ])]
    let host = try #require(NativeMessagingHost.named("app.test.echo", in: folders))
    #expect(host.allows(extensionID: extensionID))
    #expect(NativeMessagingHost.named("app.test.relative", in: folders) == nil)
    #expect(NativeMessagingHost.named("app.test.socket", in: folders) == nil)
    #expect(NativeMessagingHost.named("app.test.broken", in: folders) == nil)
    #expect(NativeMessagingHost.named("app.test.other", in: folders)?.allows(extensionID: extensionID) == false)
    for name in ["../app.test.echo", "App.Test.Echo", "", "app/test"] {
        #expect(NativeMessagingHost.named(name, in: folders) == nil, "\(name) is not a host name")
    }
}

@Test func framesSurviveBeingSplitOrJoined() throws {
    let first = try NativeMessage.frame(["cmd": 14])
    let second = try NativeMessage.frame(["text": "é"])
    #expect(first.prefix(4) == withUnsafeBytes(of: UInt32(first.count - 4)) { Data($0) }, "A native-order length comes first")
    var reader = NativeMessage.Reader()
    let joined = first + second
    #expect(try reader.append(joined.prefix(3)).isEmpty)
    let messages = try reader.append(joined.dropFirst(3))
    #expect(messages.count == 2)
    #expect((messages.last as? [String: String])?["text"] == "é")
}

@Test func anOversizedFrameIsRefused() {
    var reader = NativeMessage.Reader()
    let length = UInt32(NativeMessage.maximumIncomingLength + 1)
    #expect(throws: NativeMessage.Failure.tooLarge) { try reader.append(withUnsafeBytes(of: length) { Data($0) }) }
}

/// A program that ignores the origin it is given and echoes its input.
private func echoProgram() throws -> String {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("aero-echo-\(UUID().uuidString)")
    try Data("#!/bin/sh\nexec /bin/cat\n".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    return file.path
}

@MainActor
@Test func aConnectionEchoesAndItsProgramEndsWithIt() async throws {
    let host = try #require(NativeMessagingHost.named("app.test.echo", in: [try folder(with: ["app.test.echo": manifest(path: try echoProgram())])]))
    var received: [Any] = []
    var closed = false
    let connection = try NativeMessagingConnection(host: host, extensionID: extensionID, onMessage: { received.append($0) }, onClose: { closed = true })
    try connection.send(["ping": 1])
    for _ in 0..<50 where received.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    #expect((received.first as? [String: Int])?["ping"] == 1)
    connection.close()
    for _ in 0..<50 where connection.isRunning { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!connection.isRunning, "Closing the port ends the program")
    #expect(!closed, "Closing from Aero does not report back")
}

@MainActor
@Test func aProgramThatExitsCloses() async throws {
    let host = try #require(NativeMessagingHost.named("app.test.exits", in: [try folder(with: ["app.test.exits": manifest(name: "app.test.exits", path: "/usr/bin/true")])]))
    var closed = false
    let connection = try NativeMessagingConnection(host: host, extensionID: extensionID, onMessage: { _ in }, onClose: { closed = true })
    for _ in 0..<50 where !closed { try await Task.sleep(for: .milliseconds(20)) }
    #expect(closed, "A one-shot message to it then answers with an error instead of waiting")
    #expect(!connection.isRunning)
}

@MainActor
@Test func aMessageNoOneReadsClosesInsteadOfEndingAero() async throws {
    // Still running, but gone from the other end of the pipe, as a program is the moment macOS kills it.
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("aero-deaf-\(UUID().uuidString)")
    try Data("#!/bin/sh\nexec 0<&-\nexec /bin/sleep 5\n".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    let host = try #require(NativeMessagingHost.named("app.test.deaf", in: [try folder(with: ["app.test.deaf": manifest(name: "app.test.deaf", path: file.path)])]))
    var closed = false
    let connection = try NativeMessagingConnection(host: host, extensionID: extensionID, onMessage: { _ in }, onClose: { closed = true })
    try await Task.sleep(for: .milliseconds(200))
    try? connection.send(["ping": 1])
    #expect(closed, "The connection ends and reports it")
    for _ in 0..<50 where connection.isRunning { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!connection.isRunning)
}
