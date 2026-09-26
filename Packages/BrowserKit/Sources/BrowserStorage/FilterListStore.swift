import BrowserCore
import Foundation

/// The filter lists ad blocking last downloaded, one file each. A file is replaced only by a
/// complete list, atomically, and one that no longer reads as a list is ignored.
public actor FilterListStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func list(named name: String) -> FilterList? {
        guard let file = file(named: name), let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return FilterList(text: text)
    }

    public func save(_ list: FilterList, named name: String) throws {
        guard let file = file(named: name) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(list.text.utf8).write(to: file, options: .atomic)
    }

    /// Names are the app's own identifiers; anything but letters and digits is refused.
    private func file(named name: String) -> URL? {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return directory.appendingPathComponent(name, isDirectory: false).appendingPathExtension("txt")
    }
}
