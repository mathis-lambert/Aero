import Foundation
import Testing
@testable import BrowserCore

// Failure modes 1–5 in docs/SITE_CONTROLS.md › Ad and tracker blocking. Patterns are checked by what
// they match, through the same regular expression grammar WebKit reads.

private func rules(_ list: String) -> FilterRules { FilterRules(list: list) }

private func only(_ line: String, _ stage: FilterRules.Stage = .networkBlock) -> ContentRule? {
    let converted = rules(line)
    guard converted.count == 1 else { return nil }
    return converted[stage].first
}

private func matches(_ rule: ContentRule?, _ url: String) -> Bool {
    guard let trigger = rule?.trigger,
          let regex = try? NSRegularExpression(pattern: trigger.urlFilter, options: trigger.urlFilterIsCaseSensitive == true ? [] : .caseInsensitive)
    else { return false }
    return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
}

@Test func domainAnchorsMatchTheDomainAndItsSubdomainsOnly() {
    let rule = only("||ads.example^")
    #expect(matches(rule, "https://ads.example/banner.js"))
    #expect(matches(rule, "http://cdn.eu.ads.example/x"))
    #expect(matches(rule, "https://ads.example:8443/"))
    #expect(!matches(rule, "https://notads.example/"))
    #expect(!matches(rule, "https://ads.example.org/"))
    #expect(!matches(rule, "https://ads.examples/"))
    #expect(!matches(rule, "https://site.test/?u=https://ads.example/"))
}

@Test func anchorsWildcardsAndSeparatorsKeepTheirMeaning() {
    let start = only("|https://tracker.test/pixel")
    #expect(matches(start, "https://tracker.test/pixel.gif"))
    #expect(!matches(start, "https://site.test/?next=https://tracker.test/pixel"))

    let end = only("/ad.js|")
    #expect(matches(end, "https://site.test/static/ad.js"))
    #expect(!matches(end, "https://site.test/static/ad.js?v=2"))

    let wildcard = only("/banner/*/ad.")
    #expect(matches(wildcard, "https://site.test/banner/728/ad.png"))
    #expect(!matches(wildcard, "https://site.test/banner-ad.png"))

    let separated = only("/ads^")
    #expect(matches(separated, "https://site.test/ads?id=1"))
    #expect(matches(separated, "https://site.test/ads"))
    #expect(!matches(separated, "https://site.test/adsense.js"))

    let literal = only("-ad.gif?")
    #expect(matches(literal, "https://site.test/x-ad.gif?1"))
    #expect(!matches(literal, "https://site.test/x-adXgif"))
}

@Test func caseMattersOnlyWhenAsked() {
    #expect(matches(only("/BannerAd."), "https://site.test/bannerad.png"))
    let exact = only("/BannerAd.$match-case")
    #expect(matches(exact, "https://site.test/BannerAd.png"))
    #expect(!matches(exact, "https://site.test/bannerad.png"))
}

@Test func optionsBecomeTriggerFields() {
    let rule = only("||ads.example^$third-party,script,image,domain=news.test|blog.test")
    #expect(rule?.trigger.loadType == ["third-party"])
    #expect(rule?.trigger.resourceType == ["script", "image"])
    #expect(rule?.trigger.ifDomain == ["*news.test", "*blog.test"])
    #expect(rule?.action == ContentRule.Action(type: .block))

    #expect(only("||cdn.test^$~third-party")?.trigger.loadType == ["first-party"])
    #expect(only("||cdn.test^$domain=~shop.test")?.trigger.unlessDomain == ["*shop.test"])
    #expect(only("||cdn.test^$xmlhttprequest,subdocument,stylesheet")?.trigger.resourceType == ["fetch", "document", "style-sheet"])
    let exceptScripts = only("||cdn.test^$~script")?.trigger.resourceType
    #expect(exceptScripts?.contains("script") == false)
    #expect(exceptScripts?.contains("image") == true)
}

@Test func unsupportedSyntaxIsSkippedRatherThanMisread() {
    let skipped = [
        "/^https?:\\/\\/[a-z]{8}\\.com\\//$script",
        "example.com#?#.ad:-abp-has(.label)",
        "example.com#$#abort-on-property-read ads",
        "example.com#%#window.ads = []",
        "example.com##+js(nobab)",
        "##.ad:has-text(Sponsored)",
        "example.*##.banner",
        "||cdn.test^$redirect=noop.js",
        "||cdn.test^$csp=script-src 'none'",
        "||cdn.test^$removeparam=utm_source",
        "||cdn.test^$domain=a.test|~b.a.test",
        "||cdn.test^$object",
        "||cdn.test^$unknownoption",
        "||exämple.test^"
    ]
    for line in skipped {
        let converted = rules(line)
        #expect(converted.count == 0, "\(line) is skipped")
        #expect(converted.skippedCount == 1, "\(line) is counted as skipped")
    }
    let noise = rules("[Adblock Plus 2.0]\n! Title: EasyList\n\n   \n")
    #expect(noise.count == 0 && noise.skippedCount == 0, "Headers, comments and blank lines are not rules")
}

@Test func exceptionsFollowWhatTheyUndo() {
    let converted = rules("""
        @@||good.example^$script
        ||ads.example^
        example.com#@#.promo
        ##.promo
        @@||shop.test^$generichide
        shop.test##.sidebar-ad
        @@||news.test^$elemhide
        @@||partner.test^$document
        """)
    let exception = converted[.networkException].first
    #expect(exception?.action.type == .ignorePreviousRules)
    #expect(exception?.trigger.resourceType == ["script"])
    #expect(matches(exception, "https://cdn.good.example/app.js"))

    #expect(converted[.genericHiding] == [ContentRule(trigger: .init(urlFilter: ".*", unlessDomain: ["*example.com"]), action: .init(type: .cssDisplayNone, selector: ".promo"))])
    #expect(converted[.domainHiding] == [ContentRule(trigger: .init(urlFilter: ".*", ifDomain: ["*shop.test"]), action: .init(type: .cssDisplayNone, selector: ".sidebar-ad"))])
    let genericHide = converted[.genericHideException].first
    #expect(genericHide?.trigger.resourceType == ["document"] && matches(genericHide, "https://www.shop.test/"))
    #expect(matches(converted[.elementHideException].first, "https://news.test/today"))
    let document = converted[.documentException].first
    #expect(document?.trigger.urlFilter == ".*" && document?.trigger.ifTopURL?.count == 1)

}

@Test func domainExceptionsRemoveTheSelectorForThatDomain() {
    let converted = rules("""
        news.test,blog.test##.ad-slot
        news.test#@#.ad-slot
        """)
    #expect(converted[.domainHiding].map(\.trigger.ifDomain) == [["*blog.test"]])
}

@Test func everySelectorIsItsOwnRuleSoAnInvalidOneCostsOnlyItself() {
    let converted = rules("##.ad-one\n##.ad-two, .ad-three\n##div[class^=\"banner-\"]")
    #expect(converted[.genericHiding].map(\.action.selector) == [".ad-one", ".ad-two, .ad-three", "div[class^=\"banner-\"]"])
}

@Test func listsStayWithinTheLimitAndRepeatTheirExceptions() throws {
    let blocks = (0..<10).map { "||ads\($0).example^" }
    let list = (blocks + ["@@||ads3.example^$image", "@@||partner.test^$document", "##.ad"]).joined(separator: "\n")
    let conversion = FilterListConverter.convert([list], maximumRulesPerList: 5)
    let decoded = try conversion.lists.map { try JSONDecoder().decode([ContentRule].self, from: Data($0.utf8)) }
    #expect(decoded.allSatisfy { $0.count <= 5 })
    #expect(decoded.flatMap { $0 }.filter { $0.action.type == .block }.count == 10, "No block is lost")
    for rules in decoded where rules.contains(where: { $0.action.type == .block }) {
        let lastBlock = try #require(rules.lastIndex { $0.action.type == .block })
        let exceptions = rules.indices.filter { rules[$0].action.type == .ignorePreviousRules }
        #expect(exceptions.count == 2 && exceptions.allSatisfy { $0 > lastBlock }, "Each list undoes its own blocks")
    }
    #expect(conversion.ruleCount == 13 && conversion.skippedCount == 0)
}

@Test func encodedRulesUseWebKitKeys() throws {
    let conversion = FilterListConverter.convert(["||ads.example^$third-party,domain=news.test"])
    let json = try #require(conversion.lists.first)
    #expect(json.contains("\"url-filter\""))
    #expect(json.contains("\"load-type\":[\"third-party\"]"))
    #expect(json.contains("\"if-domain\":[\"*news.test\"]"))
    #expect(json.contains("\"type\":\"block\""))
}

@Test func listsAreRecognizedByTheirHeader() {
    #expect(FilterList(text: "[Adblock Plus 2.0]\n! Version: 202609261023\n! Title: EasyList\n||ads.example^")?.version == 202609261023)
    #expect(FilterList(text: "<!doctype html><title>502 Bad Gateway</title>") == nil)
    #expect(FilterList(text: "[Adblock Plus 2.0]\n! Title: No version\n||ads.example^") == nil)
}
