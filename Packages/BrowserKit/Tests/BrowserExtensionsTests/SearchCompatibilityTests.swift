import Testing
@testable import BrowserExtensions

// Failure modes: using a search string as a navigation URL, updating the wrong native tab ID,
// ignoring disposition, or accepting mutually exclusive target options.
@Test func extensionSearchUsesTheSelectedProviderAndNativeTabIDs() async throws {
    let harness = try CompatibilityHarness(manifest: #"{"permissions":["search"]}"#, api: """
        {tabs: {query: async () => [{id: 42}], update: async (id, value) => {globalThis.updated = {id,...value}},
                create: async value => {globalThis.created = value}},
         windows: {create: async value => {globalThis.createdWindow = value}}}
        """)
    harness.run("replies['search/url'] = 'https://provider.test/?q=javascript%3Aexample'; chrome.search.query({text:'javascript:example'})")
    let deadline = ContinuousClock.now + .seconds(2)
    while !harness.bool("globalThis.updated !== undefined"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.bool("updated.id === 42 && updated.url === replies['search/url']"))
    #expect(harness.bool("requests[0].body.text === 'javascript:example'"))
    harness.run("chrome.search.query({text:'example',disposition:'NEW_TAB'})")
    while !harness.bool("globalThis.created !== undefined"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.bool("created.url === replies['search/url'] && created.active === true"))
    harness.run("chrome.search.query({text:'example',tabId:19,disposition:'NEW_TAB'}).catch(() => globalThis.refused = true)")
    while !harness.bool("globalThis.refused === true"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.bool("globalThis.refused === true && requests.length === 2"))
}
