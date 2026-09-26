import Foundation
import WebKit

/// What a profile's store holds for a site. WebKit groups records by site (the registrable
/// domain), so a host's data includes its parent domain's and its sibling subdomains'.
public enum SiteDataKind: Sendable {
    case cookies, cache, all

    @MainActor fileprivate var types: Set<String> {
        switch self {
        case .cookies: [WKWebsiteDataTypeCookies]
        case .cache: Self.cacheTypes
        case .all: WKWebsiteDataStore.allWebsiteDataTypes()
        }
    }

    fileprivate static let cacheTypes: Set = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
}

public struct SiteDataUsage: Equatable, Sendable {
    public let cookies: Int
    /// Storage other than cookies and caches: local storage, databases, service workers.
    public let storesOtherData: Bool
}

extension WebPageRegistry {
    public func siteDataUsage(for host: String, profileID: UUID) async -> SiteDataUsage {
        let store = dataStore(for: profileID)
        let records = await Self.records(of: host, types: SiteDataKind.all.types, in: store)
        let sites = records.map(\.displayName)
        let cookies = await store.httpCookieStore.allCookies().filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return sites.contains { Self.site($0, contains: domain) }
        }
        let otherTypes = SiteDataKind.all.types.subtracting(SiteDataKind.cacheTypes).subtracting([WKWebsiteDataTypeCookies])
        return SiteDataUsage(cookies: cookies.count, storesOtherData: records.contains { !$0.dataTypes.isDisjoint(with: otherTypes) })
    }

    public func removeSiteData(_ kind: SiteDataKind, for host: String, profileID: UUID) async {
        let store = dataStore(for: profileID)
        let records = await Self.records(of: host, types: kind.types, in: store)
        guard !records.isEmpty else { return }
        await store.removeData(ofTypes: kind.types, for: records)
    }

    private static func records(of host: String, types: Set<String>, in store: WKWebsiteDataStore) async -> [WKWebsiteDataRecord] {
        let host = host.lowercased()
        return await store.dataRecords(ofTypes: types).filter { site($0.displayName, contains: host) }
    }

    private static func site(_ site: String, contains host: String) -> Bool {
        let site = site.lowercased()
        return host == site || host.hasSuffix("." + site)
    }
}
