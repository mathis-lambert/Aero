import Foundation

/// Read-only Apple events, requested by the import button, never by source discovery. A system process keeps
/// OSA off the UI thread; fixed code and separate arguments keep tab titles and URLs out of executable code.
enum DiaAutomation {
    enum Failure: Error { case denied, notRunning, unavailable }

    static func read(application: URL) async throws -> Data {
        let process = Process()
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw Failure.unavailable
            }
            defer { try? FileManager.default.removeItem(at: file) }
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close() }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", script, application.path]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 35, execute: deadline)
            defer { deadline.cancel() }
            if Task.isCancelled { process.terminate() }
            process.waitUntilExit()
            try Task.checkCancellation()
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8 * 1024 * 1024 else { throw Failure.unavailable }
            let data = try Data(contentsOf: file)
            guard process.terminationStatus == 0 else {
                let error = String(decoding: data, as: UTF8.self)
                if error.contains("-1743") { throw Failure.denied }
                if error.contains("DIA_NOT_RUNNING") { throw Failure.notRunning }
                throw Failure.unavailable
            }
            return data
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
            if process.isRunning { process.terminate() }
        }
    }

    // Only the fields documented in Dia.sdef. False means either an open tab or a folder tab: leave both behind.
    static let script = #"""
    function run(argv) {
        const app = Application(argv[0]);
        if (!app.running()) throw Error("DIA_NOT_RUNNING");
        const windows = app.windows();
        if (!windows.length) throw Error("DIA_NO_WINDOW");
        const profiles = windows[0].profiles();
        if (profiles.length > 100) throw Error("DIA_TOO_LARGE");
        let count = 0;
        const spaces = profiles.map(function(profile) {
            const tabs = profile.tabs().map(function(tab) {
                const value = tab.properties();
                if (typeof value.ispinned !== "boolean") throw Error("DIA_UNSUPPORTED");
                if (!value.ispinned) return null;
                if (++count > 10000) throw Error("DIA_TOO_LARGE");
                const url = value.url;
                if (url && url.length > 8192) throw Error("DIA_TOO_LARGE");
                return { title: String(value.title || "").slice(0, 1024), url: url || null, pinned: true };
            }).filter(function(tab) { return tab !== null; });
            return { name: profile.name().slice(0, 1024), index: profile.index(), tabs: tabs };
        });
        return JSON.stringify({ spaces: spaces });
    }
    """#
}
