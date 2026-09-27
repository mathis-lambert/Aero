# Aero

A lightweight native macOS browser built with SwiftUI, AppKit and WebKit. Apple Silicon, macOS 26.0 or newer, no external runtime dependencies.

## Build and test

Xcode 27.0 (27A266a) with its Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`), Swift 6.4.

```sh
xcodebuild -project Aero.xcodeproj -scheme Aero -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/aero-derived build

swift test --package-path Packages/BrowserKit

Scripts/run-e2e.sh [AeroUITests/<TestClass>…]
```

UI tests need a logged-in GUI session. They use isolated data (`AERO_TEST_DATA`), ephemeral website stores and local fixtures. Debug and Release builds keep separate data (`Application Support/Aero Development/Storage` and `Aero/Storage`).

`Scripts/release.sh` builds the notarized Release app, signed with Developer ID, into `/tmp/aero-release`. Its notary credentials are stored once in the keychain; the script says how.

## Features

- Spaces with independent tabs and favorites, switched from the sidebar or with a two-finger swipe. Spaces share cookies, history and extensions when assigned to the same profile.
- One control bar for addresses, searches and commands, on the New Tab page and over tabs (⌘L, ⌘K), with the chosen engine's suggestions.
- Favorites that stay when closed, as tiles or in groups; tabs dragged anywhere in the sidebar, a full tab context menu, reopen closed tabs, recent-tab switching (⌃Tab).
- Transactional SQLite state, versioned schema migrations and explicit recovery ([Storage](docs/STORAGE.md)), session restoration without loading pages, and tab hibernation ([Performance](docs/PERFORMANCE.md)).
- History in a browser tab (`aero://history`, ⌘Y) with full-text search.
- Find in page, downloads, popups, favicons ([Browsing](docs/BROWSING.md)).
- Site controls: copy link, share, certificate, site data and permissions, ad and tracker blocking, automatic picture in picture ([Site Controls](docs/SITE_CONTROLS.md)).
- Chrome and Safari web extensions per profile, from the Chrome Web Store or a folder, with native messaging to the apps they pair with ([Extensions](docs/EXTENSIONS.md)).
- Light, dark and system appearance, alternate app icons, English and French.

Not implemented yet: onboarding, import, passkeys, separate popup windows.

## Documentation

- [Browsing](docs/BROWSING.md): navigation behavior, limits and local E2E fixtures.
- [Profiles and spaces](docs/SPACES.md): ownership, settings and identity transitions.
- [Storage](docs/STORAGE.md): locations, schema changes and recovery.
- [Performance](docs/PERFORMANCE.md): page budgets, hibernation and measurement commands.
- [Shortcuts](docs/SHORTCUTS.md): defaults, overrides and keyboard routing.
- [Site controls](docs/SITE_CONTROLS.md): permissions, blocking and picture in picture.
- [Extensions](docs/EXTENSIONS.md): installation, WebKit limits and native messaging.
- [Design](docs/DESIGN.md) and [contributor rules](AGENTS.md).
