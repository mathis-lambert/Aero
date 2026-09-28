import Foundation
import Testing
@testable import BrowserCore

// docs/PASSWORDS.md › Failure modes 2, 9, 11 and 18.

private let suffixes = PublicSuffixList(rules: """
    // A few rules from the real list, including wildcards, exceptions and private domains.
    com
    uk
    co.uk
    io
    github.io
    *.ck
    !www.ck
    """)

private func origin(_ text: String) throws -> SiteOrigin { try #require(URL(string: text).flatMap(SiteOrigin.init(url:))) }

private func login(_ text: String, user: String = "alice", used: TimeInterval? = nil) throws -> SavedLogin {
    SavedLogin(profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, origin: try origin(text), username: user,
               lastUsed: used.map(Date.init(timeIntervalSince1970:)))
}

@Test func registrableDomainsFollowThePublicSuffixList() {
    #expect(suffixes.registrableDomain(of: "accounts.example.com") == "example.com")
    #expect(suffixes.registrableDomain(of: "example.com") == "example.com")
    #expect(suffixes.registrableDomain(of: "www.bbc.co.uk") == "bbc.co.uk")
    #expect(suffixes.registrableDomain(of: "alice.github.io") == "alice.github.io")
    #expect(suffixes.registrableDomain(of: "a.b.alice.github.io") == "alice.github.io")
    #expect(suffixes.registrableDomain(of: "shop.example.ck") == "shop.example.ck")
    #expect(suffixes.registrableDomain(of: "www.ck") == "www.ck")
    // A suffix itself, a bare label and addresses have no registrable domain.
    #expect(suffixes.registrableDomain(of: "co.uk") == nil)
    #expect(suffixes.registrableDomain(of: "github.io") == nil)
    #expect(suffixes.registrableDomain(of: "localhost") == nil)
    #expect(suffixes.registrableDomain(of: "127.0.0.1") == nil)
    #expect(suffixes.registrableDomain(of: "[::1]") == nil)
    // Case and a trailing dot do not change the site.
    #expect(suffixes.registrableDomain(of: "Accounts.Example.COM.") == "example.com")
}

@Test func loginsAreOfferedOnlyOnTheirSite() throws {
    let saved = try [
        login("https://example.com", user: "exact", used: 1),
        login("https://accounts.example.com", user: "sub", used: 3),
        login("https://example.org", user: "other"),
        login("https://bob.github.io", user: "bob"),
        login("http://legacy.example.com", user: "http", used: 2)
    ]
    let offered = LoginMatching.candidates(saved, for: try origin("https://example.com"), suffixes: suffixes)
    // The exact origin first, then the rest of the site by last use; HTTP logins may go to HTTPS.
    #expect(offered.map(\.username) == ["exact", "sub", "http"])
    let sibling = LoginMatching.candidates(saved, for: try origin("https://alice.github.io"), suffixes: suffixes)
    #expect(sibling.isEmpty)
    // Never an HTTPS login over HTTP.
    let plain = LoginMatching.candidates(saved, for: try origin("http://example.com"), suffixes: suffixes)
    #expect(plain.map(\.username) == ["http"])
}

@Test func hostsWithoutASiteMatchOnlyThemselves() throws {
    let saved = try [login("http://localhost:8080", user: "a"), login("http://localhost:9090", user: "b"), login("http://127.0.0.1:8080", user: "c")]
    let offered = LoginMatching.candidates(saved, for: try origin("http://localhost:8080"), suffixes: suffixes)
    #expect(offered.map(\.username) == ["a", "b"])
}

@Test func ipv6OriginRoundTrips() throws {
    let site = try origin("http://[::1]:8080")
    #expect(site.rawValue == "http://[::1]:8080")
    #expect(SiteOrigin(rawValue: site.rawValue) == site)
    #expect(LoginMatching.candidates([try login("http://[::1]:8080")], for: site, suffixes: suffixes).count == 1)
}

@Test func strongPasswordsAreGroupedMixedAndUnique() {
    var seen = Set<String>()
    for _ in 0..<200 {
        let password = PasswordGenerator.strongPassword()
        let groups = password.split(separator: "-", omittingEmptySubsequences: false)
        #expect(groups.count == 3 && groups.allSatisfy { $0.count == 6 }, "\(password)")
        #expect(password.contains(where: \.isNumber) && password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase), "\(password)")
        #expect(password.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) })
        seen.insert(password)
    }
    #expect(seen.count == 200)
}

@Test func csvReadsWhatBrowsersAndPasswordManagersWrite() throws {
    let chrome = "\u{FEFF}name,url,username,password,note\r\nexample.com,https://example.com/login,alice,\"p,a\"\"ss\",\r\n"
        + "Multi,https://é.example.com/,\"bob\",\"line\nbreak\",\"note, too\"\r\n"
        + "App,android://abc@com.example/,carol,secret,\r\n"
        + "Empty,https://example.org/,dave,,\r\n"
    let parsed = LoginCSV.parse(chrome)
    #expect(parsed.logins == [
        LoginRecord(origin: try origin("https://example.com"), username: "alice", password: "p,a\"ss"),
        LoginRecord(origin: try origin("https://xn--9ca.example.com"), username: "bob", password: "line\nbreak")
    ])
    #expect(parsed.skipped == 2)

    let safari = "Title,URL,Username,Password,Notes,OTPAuth\nSite,https://example.net:8443/a,Élodie,mot de passe,,\n"
    #expect(LoginCSV.parse(safari).logins == [LoginRecord(origin: try origin("https://example.net:8443"), username: "Élodie", password: "mot de passe")])

    // Without a url and password column the file is not a password export.
    #expect(LoginCSV.parse("a,b\n1,2\n").logins.isEmpty)
}

@Test func csvExportReadsBackUnchanged() throws {
    let records = [
        LoginRecord(origin: try origin("https://example.com"), username: "a,b", password: "q\"uote\nnew line"),
        LoginRecord(origin: try origin("http://localhost:8080"), username: "", password: "élan")
    ]
    let text = LoginCSV.export(records)
    #expect(text.hasPrefix("name,url,username,password,note\n"))
    #expect(LoginCSV.parse(text).logins == records)
}
