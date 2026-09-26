# Extensions

Aero runs Chrome and Safari web extensions on WebKit's own engine, `WKWebExtension`, the one Safari uses. The browser's part is what WebKit leaves to it: installing, telling extensions about tabs and the window, asking for permissions, and showing an extension's button and popup.

## Profiles

Each profile has its own extensions: its own `WKWebExtensionController`, persistent under the profile's identifier, with the profile's website data store. An extension installed twice keeps two separate sets of data, so a work and a personal password manager never meet. The installed list is part of the profile in the session; the prepared files live in `Extensions/<profile>/<extension>/` under the app's data folder. A profile's controller is made when its first page is, and holds nothing until an extension is installed.

## Installing

- **Chrome Web Store.** On an extension's page in the store, Aero puts its own Add to Aero button in place of the store's grey Add to Chrome; nothing else of the page changes. The button's script runs in Aero's own script world, which the page cannot post to, and only a click by the person counts; the extension installed is read from the tab's address, never from the page. Aero downloads the CRX3 package from the store's update service, checks that its signature was made with the key the extension's identifier derives from, and unpacks it.
- **Folder.** Settings › Extensions › Add from folder… loads an unpacked extension, for developers. Reload reads the folder again.

Installing shows what the extension asks for: its permissions, and the sites it may read and change. Accepting grants them; optional permissions are asked for when the extension requests them. The Web Store's extensions are checked for updates once a day; an update that asks for more is held until the person accepts it.

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

Every entry is there because an extension of the list below needs it. Nothing else is added to a package: the script goes first in the service worker, through a small worker that imports it and then the extension's own, and first in each of the extension's pages. The files are changed only after the package's signature has been checked, and only by adding.

Checked by loading them in WebKit: Dark Reader and uBlock Origin Lite run as they are; Bitwarden with the extension pages' user agent; Vimium and 1Password with the declarations above; iCloud Passwords starts; its helper, see Limits.

Failure modes:

1. A package whose signature does not match its identifier, or was altered after signing, is installed.
2. An archive entry escapes the extension's folder, or a symbolic link points outside it.
3. Extensions or their data cross profiles.
4. An extension's storage is lost at relaunch because its identifier changed.
5. Pages opened before an installation never run the extension, or a disabled or removed one keeps running.
6. Tabs WebKit is told about go stale: a closed tab stays listed, the active one is wrong, a hibernated tab has a view.
7. An extension opens a tab in another profile, or keeps a closed tab alive.
8. An update or a permission request grants more than the person accepted.
9. The inert script replaces an API WebKit has, is added twice, or breaks a module worker.
10. The popup shows detached from its button, or stays after the window changes.
11. Extension pages identify as an unknown browser and take the wrong code path.
12. A failed download, update or preparation leaves a half-installed extension.
13. A store page, or its own scripts, installs an extension without the person's click, or another one than the page shows.

Verification: E2E `testFolderExtensionRunsInItsProfileOnly` (a fixture extension installed from a folder is reviewed, runs its content script on matching pages, shows pinned with its badge, which its worker sets past an API WebKit lacks, opens its popup, is back after a relaunch, and runs in no other profile; 3, 4, 9). Isolated `ExtensionPackageTests` cover 1, 2 and 9: signatures, altered archives, identifiers, unsafe entries, and the inert script running first, once, without replacing WebKit's own APIs. By construction: 5 (every page of a profile is made with its controller, and unloading a context stops it), 11 (extension pages carry `BrowserPage.userAgentName`), 6 and 7 (tabs come from the session through `WebExtensionHost`, which ignores tabs it no longer has), 8 (a store update is installed only when it asks for nothing more, and grants are exactly what the review showed), 12 (packages are prepared in a staging folder and moved in whole), 13 (the store button's bridge is in Aero's script world, counts only trusted clicks, carries no identifier, and every installation goes through the review). The Chrome Web Store install and its updates are checked by hand, against the real store.

## Native messaging

An extension may talk to an app on the Mac, as in Chrome: a password manager to its desktop app, a clipper to a notes app. Apps register the way they do for Chrome, with a host manifest named after the host in `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` or `/Library/Google/Chrome/NativeMessagingHosts/`: its name, the program to run, `"type": "stdio"`, and the extensions allowed to reach it as `chrome-extension://<identifier>/` origins. Aero reads the same files and speaks the same protocol: the program runs with the extension's origin as its argument, and each message is a 4-byte length in native byte order followed by UTF-8 JSON. `connectNative` keeps the program running until either side disconnects; `sendNativeMessage` runs it for one message and its reply. The extension needs the `nativeMessaging` permission, granted at installation like the others.

An unpacked extension whose manifest has a `key` takes the identifier that key gives, as in Chrome, so a host can allow it.

Failure modes:

1. An extension reaches a host that does not list it, or a host name escapes the manifest folders.
2. A manifest names a relative path, another type than `stdio`, or is not valid JSON, and a program still runs.
3. A host writes more than Chrome's 1 MB per message, or an incomplete frame, and Aero buffers without limit or hangs.
4. A program keeps running after its port disconnects, its extension is disabled or removed, or the app quits.
5. Reading the program's output blocks the main thread.
6. Messages are logged, exposing what a password manager exchanges.
7. A one-shot message whose program exits without replying never answers the extension.
8. A message written to a program that has already ended, such as a helper macOS refuses to run, ends Aero.

Verification: E2E `testFolderExtensionRunsInItsProfileOnly`: the fixture extension, keyed so its identifier is fixed, connects to a fixture host (`/usr/bin/tee`, which copies each frame back) and shows the reply as its badge. Isolated `NativeMessagingTests` cover 1–4, 7 and 8 with an echo program: manifests that are invalid, name another type, a relative path or another extension; host names that are not Chrome's; frames split, joined and oversized; the program ending with its port, a program that exits, and a message sent after it did. By construction: 4's other cases (a disabled or removed extension's programs are ended as it unloads; quitting closes their input, which ends a host as it does in Chrome), 5 (the program's output is read off the main thread), 6 (nothing logs messages).

## Limits

- Extensions that depend on APIs WebKit lacks and Aero does not declare (side panel, offscreen documents, bookmarks, identity) run without those parts.
- iCloud Passwords reaches Apple's helper by native messaging, like any extension. macOS ends the helper when Aero starts it, notarized or not; browsers that run it carry the web browser entitlement Apple grants on request (`com.apple.developer.web-browser.public-key-credential`, the passkeys one), which Aero is waiting for.
