import Foundation

/// An app's native messaging host, registered the way Chrome reads it.
/// See docs/EXTENSIONS.md › Native messaging.
public struct NativeMessagingHost: Sendable {
    /// Where apps put their manifests for Chrome, for the person first, then for the Mac.
    public static let chromeFolders = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true),
        URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts", isDirectory: true)
    ]

    let program: URL
    let allowedOrigins: Set<String>

    /// The host `name` declares in the first folder that has a valid manifest for it. Names are
    /// Chrome's: lowercase letters, digits, dots and underscores, so none can reach another folder.
    static func named(_ name: String, in folders: [URL]) -> NativeMessagingHost? {
        guard !name.isEmpty, name.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "_" }) else { return nil }
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  manifest["name"] as? String == name, manifest["type"] as? String == "stdio",
                  let path = manifest["path"] as? String, path.hasPrefix("/"),
                  let origins = manifest["allowed_origins"] as? [String] else { continue }
            return NativeMessagingHost(program: URL(fileURLWithPath: path), allowedOrigins: Set(origins))
        }
        return nil
    }

    static func origin(of extensionID: String) -> String { "chrome-extension://\(extensionID)/" }

    func allows(extensionID: String) -> Bool { allowedOrigins.contains(Self.origin(of: extensionID)) }
}

/// Chrome's framing: a 4-byte length in native byte order, then UTF-8 JSON.
enum NativeMessage {
    enum Failure: Error, Equatable { case tooLarge, invalid, closed }

    /// Chrome's limit for a message from the program.
    static let maximumIncomingLength = 1024 * 1024

    static func frame(_ message: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject([message]) else { throw Failure.invalid }
        let body = try JSONSerialization.data(withJSONObject: message, options: .fragmentsAllowed)
        return withUnsafeBytes(of: UInt32(body.count)) { Data($0) } + body
    }

    /// Collects the program's output into whole messages, however it arrives.
    struct Reader {
        private var buffer = Data()

        mutating func append(_ data: Data) throws -> [Any] {
            buffer.append(data)
            var messages: [Any] = []
            while buffer.count >= 4 {
                let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                guard length <= NativeMessage.maximumIncomingLength else { throw Failure.tooLarge }
                guard buffer.count >= 4 + length else { break }
                let body = buffer.subdata(in: buffer.startIndex + 4..<buffer.startIndex + 4 + length)
                buffer.removeSubrange(buffer.startIndex..<buffer.startIndex + 4 + length)
                messages.append(try JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed))
            }
            return messages
        }
    }
}

/// A running host program for one extension. Its output is read off the main thread; messages and
/// its end are delivered on it. Messages are never logged.
@MainActor
final class NativeMessagingConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private static let maximumPendingBytes = 4 * 1024 * 1024
    private var pendingBytes = 0
    private var isClosed = false
    private let writer = DispatchQueue(label: "Aero.NativeMessaging.writer", qos: .utility)
    private var reader = NativeMessage.Reader()
    private var onMessage: ((Any) -> Void)?
    private var onClose: (() -> Void)?

    var isRunning: Bool { process.isRunning }

    init(host: NativeMessagingHost, extensionID: String, onMessage: @escaping (Any) -> Void, onClose: @escaping () -> Void) throws {
        self.onMessage = onMessage
        self.onClose = onClose
        process.executableURL = host.program
        process.arguments = [NativeMessagingHost.origin(of: extensionID)]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A write to a program that stopped reading fails instead of ending Aero with SIGPIPE.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish() } }
        }
        try process.run()
        // Only the child reads stdin and writes stdout. Keeping these ends open in Aero
        // would hide EOF and broken-pipe errors when the host stops reading.
        do {
            try input.fileHandleForReading.close()
            try output.fileHandleForWriting.close()
        } catch {
            close()
            throw error
        }
    }

    isolated deinit { close() }

    func send(_ message: Any) throws {
        guard !isClosed, process.isRunning else { throw NativeMessage.Failure.closed }
        let frame = try NativeMessage.frame(message)
        guard frame.count <= Self.maximumPendingBytes - pendingBytes else {
            finish()
            throw NativeMessage.Failure.tooLarge
        }
        pendingBytes += frame.count
        let handle = input.fileHandleForWriting
        // A host that stops reading must not block the UI. The serial queue preserves message order.
        writer.async { [weak self] in
            do {
                try handle.write(contentsOf: frame)
                DispatchQueue.main.async { self?.pendingBytes -= frame.count }
            } catch {
                DispatchQueue.main.async {
                    self?.pendingBytes -= frame.count
                    self?.finish()
                }
            }
        }
    }

    /// Ends the program from Aero's side, which reports nothing back.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        onMessage = nil
        onClose = nil
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        do {
            for message in try reader.append(data) { onMessage?(message) }
        } catch {
            finish()
        }
    }

    private func finish() {
        let onClose = self.onClose
        close()
        onClose?()
    }
}
