# Extensions

Aero runs Chrome and Safari web extensions on WebKit's own engine, `WKWebExtension`, the one Safari uses. The browser's part is what WebKit leaves to it: installing, telling extensions about tabs and the window, asking for permissions, and showing an extension's button and popup.

## Profiles

Each profile has its own extensions: its own `WKWebExtensionController`, persistent under the profile's identifier, with the profile's website data store. An extension installed twice keeps two separate sets of data, so a work and a personal password manager never meet. Registrations belong to the profile; immutable packages live in `Extensions/<profile UUID>/<package UUID>/` under Storage. A profile's controller reconciles saved extensions on launch; controllers also attach to the profile's pages. See [Storage](STORAGE.md) for commit, recovery and removal behavior.

## Installing

- **Chrome Web Store.** On an extension's page in the store, Aero puts its own Add to Aero button in place of the store's grey Add to Chrome; nothing else of the page changes. The button's script runs in Aero's own script world, which the page cannot post to, and only a click by the person counts; the extension installed is read from the tab's address, never from the page. Aero downloads the CRX3 package from the store's update service, checks that its signature was made with the key the extension's identifier derives from, and unpacks it.
- **Folder.** Settings › Extensions › Add from folder… loads an unpacked extension, for developers. Reload prepares the folder again and asks for approval before changing the active package.

Install and update requests retain their requesting profile, including while a folder picker is open. Preparing a candidate never replaces the active package. Refusing an update leaves the active version unchanged across relaunch. Installing shows what the extension asks for: its permissions, and the sites it may read and change. Accepting grants them; optional permissions are asked for when the extension requests them. The Web Store's extensions are checked for updates once a day; an update that asks for more is held until the person accepts it.

## Button, popup and options

An extension's button shows in the control center, and pinned ones in the address bar. Clicking one runs its action or opens its popup, WebKit's own popover anchored to the button. Its options page opens in a tab. Its badge shows on the button.

## What WebKit lacks

WebKit's engine covers most of the extension APIs. Where one that extensions commonly reach for is missing, Aero adds, before the extension's own scripts, a declaration that is **inert**: it is defined only when WebKit has none, so WebKit's own takes over the day it exists, and it never pretends to do what Aero cannot.

| API | Declared as |
| --- | --- |
| `webNavigation` events WebKit lacks, such as `onHistoryStateUpdated` and `onTabReplaced` | events that never fire |
| `privacy.services` settings | settings that are off and cannot be changed: Aero has no built-in password saving or autofill to turn off |
| `notifications` | calls that show nothing, and events that never fire |
| `storage.managed` | an empty store: no policy manages Aero |

Nothing else is added to a package: the script goes first in the service worker, through a small worker that imports it and then the extension's own, and first in each of the extension's pages. The files are changed only after the package's signature has been checked, and only by adding.

## Native messaging

An extension may talk to an app on the Mac, as in Chrome: a password manager to its desktop app, a clipper to a notes app. Apps register the way they do for Chrome, with a host manifest named after the host in `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` or `/Library/Google/Chrome/NativeMessagingHosts/`: its name, the program to run, `"type": "stdio"`, and the extensions allowed to reach it as `chrome-extension://<identifier>/` origins. Aero reads the same files and speaks the same protocol: the program runs with the extension's origin as its argument, and each message is a 4-byte length in native byte order followed by UTF-8 JSON. `connectNative` keeps the program running until either side disconnects; `sendNativeMessage` runs it for one message and its reply. The extension needs the `nativeMessaging` permission, granted at installation like the others.

An unpacked extension whose manifest has a `key` takes the identifier that key gives, as in Chrome, so a host can allow it.

Incoming messages are limited to 1 MiB; queued outgoing frames to 4 MiB per connection. Pipe reads and ordered writes run off the main thread. Invalid frames and queue overflow close the connection with an error; disconnecting or unloading an extension terminates its hosts. Message contents are never logged.

## Limits

- Extensions that depend on APIs WebKit lacks and Aero does not declare (side panel, offscreen documents, bookmarks, identity) run without those parts.
- iCloud Passwords reaches Apple's helper by native messaging, like any extension. macOS ends the helper when Aero starts it, notarized or not; browsers that run it carry the web browser entitlement Apple grants on request (`com.apple.developer.web-browser.public-key-credential`, the passkeys one), which Aero is waiting for.
