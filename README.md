# Aero

A lightweight native macOS browser built with SwiftUI, AppKit and WebKit. Apple Silicon, macOS 26.0 or newer, no external runtime dependencies.

## Build from source

Use Xcode 27.0 (27A266a), including its Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`), on an Apple Silicon Mac. No Apple developer account is required.

Open `Aero.xcodeproj`, select **Aero Dev**, then Run. Or:

```sh
Scripts/build.sh run                         # Debug
Scripts/build.sh run --configuration Release # Optimized, still Aero Dev
Scripts/build.sh dmg                         # Local Release DMG
Scripts/test.sh [unit|smoke|full|performance]  # See docs/TESTING.md
```

Build products and logs go to `build/` (ignored by Git). UI tests require a logged-in GUI session; they use isolated data and ephemeral website stores. Dev, nightly, beta and stable each keep separate data. Cloning a release tag still builds Aero Dev by default.

See [Build and release](docs/BUILD_AND_RELEASE.md) for the complete toolchain, channel, signing, tag and GitHub Actions policy.

## Features

- Spaces with independent tabs and favorites, switched from the sidebar or with a two-finger swipe. Spaces share cookies, history and extensions when assigned to the same profile.
- One control bar for addresses, searches and commands, on the New Tab page and over tabs (⌘L, ⌘K), with the chosen engine's suggestions.
- Favorites that stay when closed, as tiles or in groups; tabs dragged anywhere in the sidebar, a full tab context menu, reopen closed tabs, recent-tab switching (⌃Tab).
- Transactional SQLite state, versioned schema migrations and explicit recovery ([Storage](docs/STORAGE.md)), session restoration without loading pages, and tab hibernation ([Performance](docs/PERFORMANCE.md)).
- History in a browser tab (`aero://history`, ⌘Y) with full-text search.
- Find in page, downloads, popups, favicons ([Browsing](docs/BROWSING.md)).
- Site controls: copy link, share, certificate, site data and permissions, ad and tracker blocking, automatic picture in picture ([Site Controls](docs/SITE_CONTROLS.md)).
- A first-launch onboarding that imports spaces, favorites, history and passwords from Arc, Chrome, Dia, Brave, Edge, Vivaldi or Safari; open tabs are never imported ([Onboarding](docs/ONBOARDING.md)).
- Passwords per profile in the macOS keychain: saved after sign-in, filled on request, strong passwords for new accounts, import from Chrome, Arc, Dia, Brave, Edge, Vivaldi or CSV, and CSV export; passkeys through macOS in builds signed with Apple's browser entitlement ([Passwords](docs/PASSWORDS.md)).
- Chrome and Safari web extensions per profile, from the Chrome Web Store or a folder, with native messaging to the apps they pair with ([Extensions](docs/EXTENSIONS.md)).
- Settings › Storage: what Aero keeps on this Mac, item by item, with cleaning for caches, site data and history, and a full reset ([Storage](docs/STORAGE.md)).
- Light, dark and system appearance, alternate app icons, English and French.

Not implemented yet: separate popup windows.

## Documentation

- [Browsing](docs/BROWSING.md): navigation behavior and limits.
- [Testing](docs/TESTING.md): unit tests, journeys, plans and fixtures.
- [Profiles and spaces](docs/SPACES.md): ownership, settings and identity transitions.
- [Storage](docs/STORAGE.md): locations, schema changes and recovery.
- [Performance](docs/PERFORMANCE.md): page budgets, hibernation and measurement commands.
- [Shortcuts](docs/SHORTCUTS.md): defaults, overrides and keyboard routing.
- [Site controls](docs/SITE_CONTROLS.md): permissions, blocking and picture in picture.
- [Extensions](docs/EXTENSIONS.md): installation, WebKit limits and native messaging.
- [Design](docs/DESIGN.md) and [contributor rules](AGENTS.md).
