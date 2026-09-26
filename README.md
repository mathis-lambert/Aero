# Aero

A lightweight native macOS browser built with SwiftUI, AppKit and WebKit. Apple Silicon, macOS 27.0 or newer, no external runtime dependencies.

## Build and test

Xcode 27.0 (27A266a) with its Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`), Swift 6.4.

```sh
xcodebuild -project Aero.xcodeproj -scheme Aero -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/aero-derived build

swift test --package-path Packages/BrowserKit

Scripts/run-e2e.sh [AeroUITests/<TestClass>…]
```

UI tests need a logged-in GUI session. They use isolated data (`AERO_TEST_DATA`), ephemeral website stores and local fixtures. Debug and Release builds keep separate data (`Application Support/Aero Development` and `Aero`).

## Features

- Profiles, each with its own website store, tabs and history, switched from the sidebar footer or with a two-finger swipe (`docs/PROFILES.md`).
- One control bar for addresses, searches and commands, on the New Tab page and over tabs (⌘L, ⌘K), with the chosen engine's suggestions (`docs/CONTROL_BAR.md`).
- Pinned tabs, drag to reorder and pin, reopen closed tabs, recent-tab switching (⌃Tab).
- Session restoration without loading pages, and tab hibernation (`docs/PERFORMANCE.md`).
- History in a browser tab (`aero://history`, ⌘Y) with full-text search (`docs/HISTORY.md`).
- Find in page, downloads, popups, favicons (`docs/BROWSING.md`).
- Light, dark and system appearance, alternate app icons, English and French.

Not implemented yet: onboarding, import, extensions, credential integration, separate popup windows, editable shortcuts and profile deletion.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | New tab |
| ⌘K | Control bar, results in a new tab; lists every command |
| ⌘L | Control bar on the current address |
| ⌘W / ⇧⌘T | Close / reopen tab |
| ⌃Tab / ⌃⇧Tab | Recent tabs; release Control to choose |
| ⌘[ / ⌘] / ⌘R | Back / forward / reload |
| ⇧⌘S | Toggle sidebar |
| ⌘F / ⌘G / ⇧⌘G | Find in page / next / previous |
| ⌘Y | History |

⌘K, ⇧⌘S, ⌘F, ⌘G and ⇧⌘G reach a focused web page first; the others always stay with the browser.

Contributor conventions are in `AGENTS.md`, appearance rules in `docs/DESIGN.md`. The full design system (brand book, tokens, components, icons) is a standalone site in `docs/design-system`: open its `index.html`, or hand the folder to another tool; `python3 Scripts/build-design-system.py` rebuilds it.
