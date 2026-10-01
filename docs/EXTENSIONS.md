# Extensions

Aero runs Chrome web extensions through `WKWebExtension`. It handles installation, browser integration and selected APIs WebKit lacks. Engine updates arrive with macOS. Safari app extensions are unsupported: their app integration is unavailable to other browsers.

## Architecture

`BrowserExtensions` depends only on `BrowserCore`. The app connects it to `BrowserWebKit` through `PageExtensions`, which supplies page configurations and context menus. `InstalledExtension` records live in `BrowserCore`, persistence in `BrowserStorage`, and UI in `App/Features/Extensions`.

| Type | Owns |
| --- | --- |
| `ExtensionRegistry` | Profile runtimes, package folders, profile removal and focus changes |
| `ProfileExtensions` | One `WKWebExtensionController` per profile, its contexts, status, buttons, commands, menus and tab events |
| `ExtensionHost` | App integration: tabs, main window, prompts, registrations, notifications, downloads, history and search |
| `ExtensionPackage` | CRX3 verification, unpacking, preparation and the compatibility layer's file |
| `ExtensionBridge` | Aero's scheme, `aero-extension:`, which the compatibility layer calls |
| `ExtensionWindow` | Windows an extension opens |
| `OffscreenDocuments`, `IdleMonitor`, `ExtensionEvents` | Hidden extension pages, idle state and event delivery |
| `NativeMessagingHost`, `NativeMessagingConnection` | Chrome's native messaging |
| `WebStore` | The store's update service and install button |

The target is organized by responsibility:

```text
BrowserExtensions/
  Runtime/          Profile controllers, registry, host, tab and window adapters, status, contexts and delegates
  Packaging/        Signed packages, preparation and Chrome Web Store
  Compatibility/    Script assembly, API capability assessment and bridge routing
    Resources/
      Bootstrap.js
      WebKitRuntime.js
      APIs/          One missing browser API per file
  Services/         One file per service, with its routes: events, permissions, management, offscreen documents,
                    native messaging, downloads, idle, clipboard, notifications, history, navigation events,
                    web authorization, power and speech
  Presentation/     Extension windows
```

The app keeps installation coordination, host integration, presentation, settings and notifications in matching feature subfolders. These are folders within the existing targets, not additional packages or runtime dependencies.

## Profiles

Each profile has its own persistent controller and extension storage, sharing its website data store with its pages. Installing an extension in two profiles keeps their data separate. Packages live in `Extensions/<profile UUID>/<package UUID>/`; saved registrations are reconciled on launch. See [Storage](STORAGE.md) for commit, recovery and removal. [Private sign-in pages](OTHER_APPS.md) run without extensions.

## Installing

- **Chrome Web Store.** Paste a store link or extension ID in Settings, or use Add to Aero on the store page. Aero replaces Add to Chrome with Add to Aero. The script runs in an isolated world and accepts only trusted clicks. Aero derives the extension ID and profile from the requesting page, downloads its CRX3 package, and verifies the signature against the key that determines its ID before unpacking.
- **Folder.** Settings › Extensions › Add from folder… imports an unpacked extension. Reload from folder prepares and reviews a new package before activation.

Install and update requests retain their requesting profile, including while a folder picker is open. Preparing a candidate never replaces the active package. Refusing an update leaves the active version unchanged across relaunch.

The review lists requested sites, permissions affecting user data or system access, and unsupported features. Approval grants WebKit permissions and those Aero provides (`clipboardRead`, `downloads`, `history`, `identity`, `identity.email`, `idle`, `management`, `notifications`, `offscreen`, `power`, `privacy`, `search`, `topSites`, `tts`). Optional permissions require a later prompt; `permissions.remove` updates saved grants. Store updates are checked at launch, then once a day as macOS schedules background maintenance, and held for review if they request more access.

## The browser's part

- **Tabs.** Extensions see their profile's tabs across spaces. They can open, close, select, move, pin (favorites), duplicate, navigate, reload, zoom, capture snapshots and detect page language. Loading, URL, title, pinning and zoom changes generate events. Hibernated tabs have no live page and load their assigned URL on activation.
- **Windows.** Normal `windows.create` requests open tabs in the main window. Popup requests create a separate window with one extension or website page using the profile's data. New-window links open in browser tabs. Extensions cannot close or minimize the main window or create private windows.
- **Actions.** Buttons and badges appear in the control center, with pinned buttons in the address bar. A click runs the action through WebKit, which runs the extension's handler or loads its popup page, sizes it to the page within Chrome's 800 × 600 points, and asks Aero to present WebKit's own popover, anchored to the button. Aero adds no sizing of its own: the page sets its size. Clicking the button again closes it, which lets WebKit unload the page, so `action.setPopup` takes effect on the next popup. Extension menu items precede Aero's on action buttons and follow WebKit's in page context menus.
- **Shortcuts.** Commands, including `_execute_action`, run after Aero's reserved shortcuts and before the page. Aero and system bindings remain reserved. Settings can override, disable or restore extension shortcuts; overrides live in Aero's shortcut preferences and are removed with the extension.
- **Options.** Options pages open in tabs.
- **New Tab page.** An enabled extension declaring `chrome_url_overrides.newtab` replaces Aero's New Tab page with WebKit's `overrideNewTabPageURL`, the most recently added one when several do; its review says so. `tabs.create` without an address opens it too.
- **Developer tools.** In developer mode (docs/BROWSING.md › Developer mode), backgrounds and extension pages are inspectable and `devtools_page` panels join Web Inspector.

## What Aero adds

`Compatibility/ExtensionCompatibility.swift` assembles the scripts under `Compatibility/Resources`. The result loads before service workers, classic background scripts, extension pages and isolated content scripts. `WebKitRuntime.js` runs in all of them; the missing APIs under `APIs/` run only in extension pages and workers, as Chrome gives content scripts none of them. Main-world scripts and CSS-only content entries receive nothing. Each API is defined on both `browser` and `chrome` only where WebKit has none, so WebKit's own implementation wins when it exists. Modified namespace objects stay referenced because WebKit discards additions when recreating unreferenced namespaces. Before loading a prepared package, Aero refreshes its compatibility file if it differs from the bundled version. No part of the layer depends on a particular extension.

| API | What Aero does |
| --- | --- |
| `offscreen` | One hidden page per extension, in its context, with extension messaging; `reasons` and `justification` are validated |
| `runtime.getContexts` | The background, offscreen document, open popup, and the extension's pages in tabs and windows, with WebKit's tab and window identifiers. The background is listed whenever the extension has one: WebKit starts it on demand and does not report when it stops. A `documentIds` filter is refused: document identifiers are WebKit's own |
| `idle` | Locked while the screen is locked, from the lock that follows the start of watching (macOS reports locking as it happens and has no public query of the current state), idle after the interval without input (at least 15 seconds), with `onStateChanged` |
| `notifications` | macOS notifications with the extension's name, image and up to two buttons; updates merge their options. `getPermissionLevel` and `onPermissionLevelChanged` follow Aero's notification setting in System Settings, checked when Aero becomes active |
| `downloads` | Web, data and blob downloads using profile data; `search`, `cancel`, `show`, `showDefaultFolder`, `erase` and events. Only the downloads the extension started in this session are known |
| `management` | `getSelf` and confirmed `uninstallSelf`; with `management`, the profile's other extensions (`getAll`, `get`), confirmed `setEnabled` and `uninstall`, and their install, uninstall, enable and disable events |
| `permissions` | A request that names a permission Aero provides is validated against the manifest, asked in one prompt and granted whole or not at all, WebKit's part included; `onAdded` and `onRemoved` report Aero's permissions next to WebKit's. Required permissions cannot be removed |
| `history`, `topSites` | The profile's history: search, visits with their transition and referring visit, additions, deletions, `onVisited` and `onVisitRemoved`; most visited pages |
| `search` | Aero's chosen search provider, in the current or a new tab |
| `identity` | `launchWebAuthFlow` in a window of its own, with the provider's popups and `window.opener`, interactive or silent, redirected to `https://<id>.chromiumapp.org/`. No browser account: `getAuthToken` fails and `getAccounts` is empty |
| `power` | System and display keep-awake assertions and user activity, released with the extension |
| `tts` | `AVSpeechSynthesizer`: voices, rate, pitch, volume, language, SSML, queueing and events |
| `webNavigation.onHistoryStateUpdated`, `onReferenceFragmentUpdated`, `onCreatedNavigationTarget` | Main-frame changes of address within a document, and pages a tab opens, as Aero observes them, with URL filters |
| `clipboardRead` | Extension pages granted it read what another app copied at once; WebKit alone waits for the person to confirm a paste. Writing and copying are WebKit's own |
| `requestIdleCallback` | In extension pages and content scripts, which WebKit leaves without it (`NativeBaselineTests`) |
| `tabs.getCurrent` | Nothing in an action popup, as in Chrome; WebKit returns the tab the popup belongs to (`NativeBaselineTests`) |
| `privacy.services` | `passwordSavingEnabled`: turning it off gives the profile's passwords to the extension, turning it on or clearing it gives them back to Aero, with `onChange`. `autofillAddressEnabled` and `autofillCreditCardEnabled` are off and not controllable: Aero fills no addresses or cards |
| `storage.managed` | An empty store: no policy manages Aero |

Some events are defined but never fire, because what they report never happens in Aero: `runtime.onUpdateAvailable` and `onRestartRequired` (an accepted update applies at once), `webNavigation.onTabReplaced` (a tab keeps its identifier), `identity.onSignInChanged` (no browser account), `notifications.onShowSettings`, `downloads.onDeterminingFilename` (Aero chooses the file name) and `storage.managed.onChanged`.

The bridge accepts JSON at `aero-extension://aero/<service>/<request>`. Only extension configurations carry its handler. Requests are attributed to the calling view's context, must match its origin, and require the relevant permission. Each request also names the events its context listens for, so an event it causes, such as `permissions.onAdded`, reaches it before its next wait. Each listening context waits up to 25 seconds for events, with at most 64 queued. Suspended backgrounds are started with `loadBackgroundContent`. Cancellation, timeouts and unloading release only the corresponding wait. Losing a permission, or unloading, ends what it allowed: keep-awake assertions, speech, authorization windows, the offscreen document, idle watching, notifications and tracked downloads.

Package preparation adds the compatibility file, a worker wrapper and HTML script tags, and prepends hooks to classic backgrounds and isolated content scripts. Store signatures are verified before these changes. Refreshing a prepared package updates the generated layer and missing manifest hooks; extension scripts remain unchanged. Uninstall unloads the context, which discards session storage, then deletes local and synchronized storage before committing registry removal.

WebKit dispatches events through the `browser` and `chrome` globals, so the layer keeps them as fixed accessors. An extension may still assign them, or redefine them with `Object.defineProperty`, `Object.defineProperties`, `Reflect.defineProperty` or `__defineGetter__`, as polyfills and wrappers that hide the APIs from other code do: scripts then read the replacement for as long as it exposes WebKit's own `runtime`, and the native namespace otherwise. Redefining does not throw. Message delivery, synchronous responses, asynchronous callbacks and promised responses use WebKit directly; Aero does not duplicate that dispatcher. Added APIs support promises and callbacks. A failed callback reads its error through `browser.runtime.lastError` or `chrome.runtime.lastError`; the native globals are restored before returning to WebKit. WebKit's read-only host getter prevents adding that error to an unwrapped runtime object cached before the callback. Promise refusals remain the complete error path for such consumers.

## Navigation between websites and extension pages

A tab's page belongs to either a website configuration or an extension's context, and WebKit cannot change a view's configuration. Crossing between them, when a website opens a resource the extension exposes to it in `web_accessible_resources` or an extension page loads a website, replaces the tab's view with one for the other side. The request is carried over, method and body included when WebKit provides them; a replacement is dropped if a newer navigation started or the tab closed meanwhile. The replaced view's back and forward list and its `window.opener` do not survive: going back from the new page does not return to the previous one. A website return requires native navigation provenance, handles server redirects from a blank page, and refuses traversal and encoded separators. Resources with `use_dynamic_url` and `extension_ids` callers are refused.

## Native messaging and desktop apps

Aero reads Chromium host manifests from Chrome, Chromium, Edge, Brave, Vivaldi and Arc's `NativeMessagingHosts` folders under `~/Library/Application Support`, then Chrome, Chromium and Edge's system folders under `/Library`. A manifest declares the host name, executable, `"type": "stdio"`, and allowed `chrome-extension://<identifier>/` origins. The extension must have `nativeMessaging` permission and appear in the allowlist.

The host receives the extension origin as an argument. Messages use a 4-byte length in native byte order followed by UTF-8 JSON. `connectNative` retains a connection; `sendNativeMessage` exchanges one request and reply.

An unpacked extension whose manifest has a `key` takes the identifier that key gives, as in Chrome, so a host can allow it. Incoming messages are limited to 1 MiB; queued outgoing frames to 4 MiB per connection. Pipe reads and ordered writes run off the main thread. Invalid frames and queue overflow close the connection with an error; disconnecting or unloading an extension terminates its hosts. Message contents are never logged.

Settings shows the last connection result and identifies the app from the outermost bundle containing the host executable.

## Adding compatibility

Start with a controlled Chrome-format fixture that demonstrates a browser API contract Aero fails. Keep its manifest and scripts in the repository. Do not assert the interface, messages or authentication protocol of a published extension, and do not download a moving store version during automated tests. Compatibility is fixed at the level of the browser contract, for every extension: the layer has no code for a particular extension.

- For a missing API, add `Compatibility/Resources/APIs/<API>.js`, using the bootstrap's `define`, `method`, `call`, `deliveredEvent` and `nativeTab` helpers. Preserve native implementations. Add native routing, in the service that owns the resource, only if the API needs an app service, and release what it holds in `revoke`.
- For a WebKit behavior every context needs, change `WebKitRuntime.js`.
- Test the contract with an example extension under `Tests/BrowserExtensionsTests/Fixtures`, or the JavaScriptCore harness when native WebKit is unnecessary. Include teardown and refusal cases where applicable.

Native desktop applications can impose their own browser authorization. Settings shows the connection status of any extension that tried to reach an app; successful native messaging does not bypass an application's signature or allowlist checks.

## Password managers

An extension that runs in every website may fill the profile's passwords in place of Aero (docs/PASSWORDS.md › AutoFill). Adding one offers it in the review, already chosen for a password manager: an extension that declares `privacy`, Chrome's way for a password manager to turn off the browser's own saving. An extension can also take or give back the passwords through `privacy.services.passwordSavingEnabled`, and the person can change the choice in Settings › Passwords.

## Settings

Settings lists the profile's extensions with an enable switch and a menu for pinning, options, reload, details and confirmed removal. Paste a store link or ID to install directly. Details contain errors and retry, desktop integration, unavailable features, granted access and shortcuts. Removal confirmations retain the requesting profile even if the selected profile changes.

## Limits

- WebKit's engine lacks, and Aero does not provide: the side panel, signing in with a browser account (`oauth2`, `getAuthToken`), changing requests as pages make them (`webRequestBlocking`; `declarativeNetRequest` works), replacing the History or Bookmarks page, bookmarks and the reading list, tab groups and sessions, proxy settings, providing voices (`ttsEngine`), capturing tabs, pages or the screen, debugging, privacy settings other than `privacy.services`, site and font settings, clearing browsing data, address bar keywords and push messages. Extensions declaring them run without those parts, and the installation prompt and Settings name them.
- A worker's own pages are not listed by `clients.matchAll()`.
- Muting tabs and reader mode are not reported to extensions.
- The `webNavigation` events Aero adds cover main frames only.
- An event for a suspended background waits until it starts again; one that cannot start loses it.

## Failure modes

1. A declaration replaces WebKit's own API, is missing from `browser` or `chrome`, or disappears when WebKit rebuilds a namespace; an extension replaces or redefines a native global and loses message delivery, or its redefinition throws.
2. A package prepared by an earlier Aero runs an earlier layer, or preparing changes the extension's own files.
3. A context reaches another extension's services, a page reaches the scheme, a permission not granted is served, a combined request is granted in part, or a revoked permission keeps its resources.
4. An event is lost, misrouted or fails to wake a background; unloading leaves a wait pending; an obsolete timeout or cancellation answers a later request.
5. An extension takes a shortcut of Aero or macOS, or a changed shortcut survives the extension's removal.
6. A closed tab is resurrected by a late request, or an extension closes the main window.
7. A callback loses its error, a popup is resized by Aero rather than its page, a dynamic popup URL is ignored, or a connection request cannot open a tab.
8. An extension runs in another profile, or survives its removal or its profile's.

## Verification

| Tests | Covers |
| --- | --- |
| `NativeBaselineTests` | WebKit alone, without the layer: both globals replaced cut a context's listeners off, `runtime` additions are dropped by garbage collection, no idle callbacks, `tabs.getCurrent` returns a tab in the popup, `<all_urls>` reaches other extensions; and what WebKit already does: `_execute_action` presents the popup, unfocused pages write and copy to the clipboard |
| `CompatibilityLayerTests` | JavaScriptCore: missing APIs, globals assigned, redefined or later hidden, retained additions, bridge calls, callbacks, refusals, combined permission requests, context and navigation tab identifiers, URL filters, idle callbacks and layer refresh |
| `ExtensionPackageTests` | CRX3 verification and package preparation |
| `ExtensionEventsTests` | Delivery, background wake-up, queue bounds, unloading and cancellation |
| `ExtensionCompatibilityTests`, `IdleSchedulingTests` | Unsupported declarations and idle scheduling |
| `NativeMessagingTests` | Framing, host lookup and app identification |
| `ExtensionRuntimeTests` | Real WebKit worker and offscreen page: globals replaced and redefined, idle callbacks, retained additions, the `management` inventory, idle, one prompt for Aero's and WebKit's permissions with `onAdded`, undeclared and removed permissions, notification permission level, offscreen messaging, contexts and refusals |
| `ExtensionWindowTests` | `windows.create` sizes and requests, the New Tab page an extension replaces, developer mode |
| `ExtensionPopupTests` | Controlled example: WebKit's popover sized to its page within Chrome's bounds, worker messages, native `action.setPopup`, a tab opened from the popup and teardown |
| `ExtensionFormFillTests` | Controlled password manager example on a sign-in form: isolated content script with idle callbacks, an exposed page framed over the field, a script added to the page, all reaching the worker |
| `ExtensionRemovalTests` | Persistent storage removal before and after unloading, retries and clean reinstallation |
| `ProfileBridgeTests`, `ExtensionSiteAccessTests`, `ExtensionResourcesTests` | Same-ID extensions in two profiles, website grants that never reach other extensions, exposed resources |
| `ExtensionAuthenticationTests`, `SearchCompatibilityTests`, `ExtensionSystemServicesTests` | Web authorization redirects, cancellation, silent mode and opener; search provider; keep-awake, speech and `clipboardRead` |
| `ExtensionHistoryTests`, `HistoryNavigationTests` | History ranges, profile isolation and baseline upgrade; native navigation type and referrer |
| `SiteJourneys.testAnExtensionRunsInItsProfileOnly` | Review, settings, content scripts, actions, popup, worker, connection tab and extension return, native host, profile isolation, rejected update and removal across relaunches |

Shortcut conflicts also have app unit coverage. Authentication with an actual account, desktop authorization, popup windows, notifications, downloads, audible speech and extension-defined context menus need manual checks. Automated fixtures verify Aero's API contracts, not vendor behavior.
