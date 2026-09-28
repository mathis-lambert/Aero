import Foundation

/// The CSV files browsers and password managers exchange passwords in. See docs/PASSWORDS.md › Import and export.
public enum LoginCSV {
    private static let urlColumns: Set = ["url", "website", "login_uri", "web site", "login url"]
    private static let usernameColumns: Set = ["username", "login", "login_username", "user name", "email"]
    private static let passwordColumns: Set = ["password", "login_password"]

    /// Logins read from `text`, and how many rows lacked a web address or a password. Without a URL
    /// and a password column, the text is not a password export and yields nothing.
    public static func parse(_ text: String) -> (logins: [LoginRecord], skipped: Int) {
        var rows = records(in: text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard !rows.isEmpty else { return ([], 0) }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let url = header.firstIndex(where: urlColumns.contains),
              let password = header.firstIndex(where: passwordColumns.contains) else { return ([], 0) }
        let username = header.firstIndex(where: usernameColumns.contains)
        var logins: [LoginRecord] = [], skipped = 0
        for row in rows where !row.allSatisfy(\.isEmpty) {
            let field = { (index: Int?) -> String in index.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? "" }
            guard let origin = SiteOrigin(address: field(url)), !field(password).isEmpty else { skipped += 1; continue }
            logins.append(LoginRecord(origin: origin, username: field(username), password: field(password)))
        }
        return (logins, skipped)
    }

    /// Chrome's columns, which every importer reads.
    public static func export(_ logins: [LoginRecord]) -> String {
        var text = "name,url,username,password,note\n"
        for login in logins {
            text += [login.origin.host, login.origin.rawValue, login.username, login.password, ""].map(quoted).joined(separator: ",") + "\n"
        }
        return text
    }

    private static func quoted(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// RFC 4180: quoted fields may hold separators, doubled quotes and line breaks; lines end in LF or CRLF.
    private static func records(in text: String) -> [[String]] {
        var records: [[String]] = [], record: [String] = [], field = ""
        var quoted = false, afterQuote = false
        func endField() { record.append(field); field = ""; afterQuote = false }
        func endRecord() { endField(); records.append(record); record = [] }
        var characters = text.makeIterator()
        while let character = characters.next() {
            if quoted {
                if character == "\"" { quoted = false; afterQuote = true } else { field.append(character) }
                continue
            }
            switch character {
            case "\"" where afterQuote: field.append("\""); quoted = true; afterQuote = false
            case "\"" where field.isEmpty: quoted = true
            case ",": endField()
            case "\r\n", "\n", "\r": endRecord()
            default: field.append(character); afterQuote = false
            }
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return records
    }
}
