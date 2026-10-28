import AppKit
import BrowserCore
import Darwin
import Foundation
import Observation
import SwiftTerm

/// A terminal tab's shell (docs/TERMINAL.md): the live resource behind a tab whose record is an address. It starts the
/// first time the tab shows and runs while the tab exists, shown or not; the tab's address keeps the folder it was
/// last in, so after a relaunch a new shell starts there.
@MainActor @Observable
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    private(set) var isRunning = false
    @ObservationIgnored let view: LocalProcessTerminalView
    @ObservationIgnored private let onTitle: (String) -> Void
    @ObservationIgnored private var directory: URL

    init(directory: URL, onTitle: @escaping (String) -> Void) {
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        self.directory = directory
        self.onTitle = onTitle
        super.init()
        view.processDelegate = self
        view.optionAsMetaKey = false
        start()
    }

    /// Starts the person's login shell in the folder it was last in, or again after it ended.
    func start() {
        guard !isRunning else { return }
        let shell = Self.loginShell
        let folder = FileManager.default.fileExists(atPath: directory.path) ? directory : FileManager.default.homeDirectoryForCurrentUser
        isRunning = true
        view.startProcess(executable: shell, args: [], environment: Self.environment(shell: shell),
                          execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: folder.path)
    }

    /// Ends the shell and what it runs.
    func end() {
        guard isRunning else { return }
        isRunning = false
        view.terminate()
    }

    /// The folder the shell is in now, as macOS reports it for its process.
    var currentDirectory: URL {
        let pid = view.process.shellPid
        guard isRunning, pid > 0 else { return directory }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return directory }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        guard !path.isEmpty else { return directory }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        return directory
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        MainActor.assumeIsolated { onTitle(title) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory), url.isFileURL else { return }
        MainActor.assumeIsolated { self.directory = url }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated { isRunning = false }
    }

    // MARK: Shell

    /// The shell the person chose for their account.
    private static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell, let path = String(validatingCString: shell),
           FileManager.default.isExecutableFile(atPath: path) { return path }
        return "/bin/zsh"
    }

    /// The person's language and region, as a POSIX locale names them.
    private static var localeName: String {
        let language = Locale.current.language
        guard let code = language.languageCode?.identifier, let region = language.region?.identifier else { return "en_US" }
        return "\(code)_\(region)"
    }

    /// What a terminal on this Mac gives its shell, without Aero's own settings: the login shell sets the rest.
    private static func environment(shell: String) -> [String] {
        let inherited = ProcessInfo.processInfo.environment
        var variables = [
            "TERM=xterm-256color", "COLORTERM=truecolor", "TERM_PROGRAM=Aero", "SHELL=\(shell)",
            "LANG=\(Self.localeName).UTF-8",
        ]
        let passed = ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING"]
        variables += passed.compactMap { key in inherited[key].map { "\(key)=\($0)" } }
        return variables
    }
}

/// The shells of a window's terminal tabs, by tab (docs/TERMINAL.md). One owner, so a shell outlives the views that
/// show it and ends with its tab.
@MainActor
final class TerminalSessions {
    private var sessions: [UUID: TerminalSession] = [:]

    /// The tab's shell, started in `directory` the first time it is asked for.
    func session(for tabID: UUID, in directory: URL, onTitle: @escaping (String) -> Void) -> TerminalSession {
        if let session = sessions[tabID] { return session }
        let session = TerminalSession(directory: directory, onTitle: onTitle)
        sessions[tabID] = session
        return session
    }

    func existing(_ tabID: UUID) -> TerminalSession? { sessions[tabID] }

    /// Ends the shells of tabs that no longer exist.
    func keep(only tabIDs: Set<UUID>) {
        for (id, session) in sessions where !tabIDs.contains(id) {
            session.end()
            sessions[id] = nil
        }
    }

    /// The folder each running shell is in, by tab.
    var directories: [UUID: URL] { sessions.mapValues(\.currentDirectory) }

    isolated deinit {
        for session in sessions.values { session.end() }
    }
}

extension InternalPage {
    /// A terminal tab's address, keeping the folder its shell was last in.
    static func terminal(in directory: URL) -> URL {
        var components = URLComponents(url: InternalPage.terminal.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "dir", value: directory.path)]
        return components?.url ?? InternalPage.terminal.url
    }

    /// The folder a terminal tab's address keeps, or the home folder.
    static func terminalDirectory(of url: URL) -> URL {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "dir" }?.value
        guard let path, path.hasPrefix("/") else { return FileManager.default.homeDirectoryForCurrentUser }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
