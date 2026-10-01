import AppKit
import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// What a password manager extension needs from the browser on a website's sign-in form, checked with a controlled
// example: its isolated content script runs in the page with idle callbacks, sees the fields and reaches the worker; its
// exposed page loads in a frame over the field and reaches the worker; a script it adds to the page runs there.
// The worker reports what arrived in its button title. Needs access to macOS WebKit services.
@MainActor
@Test func aPasswordManagerExampleAttachesToASignInForm() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aero-form-fill-\(UUID().uuidString)")
    let source = folder.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let files = [
        "manifest.json": """
            {"manifest_version": 3, "name": "Form fill fixture", "version": "1", "action": {"default_title": "waiting"},
             "background": {"service_worker": "worker.js"}, "permissions": ["storage"], "host_permissions": ["http://127.0.0.1/*"],
             "content_scripts": [{"matches": ["http://127.0.0.1/*"], "js": ["content.js"], "all_frames": true, "run_at": "document_end"}],
             "web_accessible_resources": [{"resources": ["dropdown.html", "dropdown.js", "page.js"], "matches": ["http://127.0.0.1/*"]}]}
            """,
        "worker.js": """
            const heard = {};
            chrome.runtime.onMessage.addListener((message, sender, reply) => {
                Object.assign(heard, message);
                if (message.dropdown) heard.dropdownFromTab = typeof sender.tab?.id === "number";
                if (message.content) heard.contentFromTab = typeof sender.tab?.id === "number";
                chrome.action.setTitle({ title: JSON.stringify(heard) });
                reply({ received: true });
            });
            """,
        "content.js": """
            if (window === window.top) {
                const field = document.querySelector("input[type=password]");
                const frame = document.createElement("iframe");
                frame.src = chrome.runtime.getURL("dropdown.html");
                field.after(frame);
                const script = document.createElement("script");
                script.src = chrome.runtime.getURL("page.js");
                document.documentElement.append(script);
                requestIdleCallback(() => {
                    chrome.runtime.sendMessage({ content: true, field: !!field, idle: true }).then((answer) => {
                        setTimeout(() => chrome.runtime.sendMessage({ pageScript: document.documentElement.dataset.pageScript ?? "missing",
                                                                      answered: answer?.received === true }), 500);
                    });
                });
            }
            """,
        "dropdown.html": "<!doctype html><html><head><meta charset='utf-8'></head><body>Accounts<script src='dropdown.js'></script></body></html>",
        "dropdown.js": "chrome.runtime.sendMessage({ dropdown: true, storage: typeof chrome.storage?.local?.get === 'function' });",
        "page.js": "document.documentElement.dataset.pageScript = 'ran';"
    ]
    for (name, contents) in files { try Data(contents.utf8).write(to: source.appendingPathComponent(name)) }
    let site = try AuthorizationServer(response: """
        HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\
        <!doctype html><html><body><form><input type="email" autocomplete="username"><input type="password" autocomplete="current-password"></form></body></html>
        """)

    let store = WKWebsiteDataStore.nonPersistent()
    let host = TestHost()
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    host.mainWindow = window
    defer { window.close() }
    let registry = ExtensionRegistry(folder: folder.appendingPathComponent("packages"), nativeHostFolders: [], ephemeral: true) { _ in store }
    registry.host = host
    let profileID = UUID()
    let extensions = registry.extensions(for: profileID)
    let candidate = try await extensions.prepare(folder: source)
    var record = InstalledExtension(id: candidate.identifier, version: "1", source: .folder(source),
                                    grantedPermissions: candidate.permissions, grantedSites: candidate.sites)
    record.packageID = candidate.packageID
    host.records = [record]
    try await extensions.load(record)
    defer { try? extensions.unload(record.id) }

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = store
    registry.configure(configuration, forProfile: profileID)
    let page = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
    window.contentView = page
    window.orderFront(nil)
    let tab = BrowserTab(spaceID: UUID(), url: site.url)
    host.browserTabs = [tab]
    host.selectedTabID = tab.id
    host.views[tab.id] = page
    extensions.didOpenTab(tab.id)
    page.load(URLRequest(url: site.url))

    let expected: [String: Any] = ["content": true, "field": true, "idle": true, "contentFromTab": true, "dropdown": true,
                                   "storage": true, "dropdownFromTab": true, "pageScript": "ran", "answered": true]
    let deadline = ContinuousClock.now + .seconds(20)
    var heard: [String: Any] = [:]
    while ContinuousClock.now < deadline {
        let title = extensions.action(for: record.id)?.label ?? ""
        heard = (try? JSONSerialization.jsonObject(with: Data(title.utf8))) as? [String: Any] ?? [:]
        if expected.allSatisfy({ heard[$0.key] != nil }) { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    for (key, value) in expected {
        #expect(heard[key] as? NSObject == value as? NSObject, "\(key): \(heard[key] ?? "nothing")")
    }
}
