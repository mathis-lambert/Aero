# LightBrowser

A native macOS browser foundation built with SwiftUI, AppKit and WebKit. Apple Silicon only; macOS 27.0 or newer. No external runtime dependencies.

## Toolchain

- Xcode 27.0 (27A266a), Apple Swift 6.4; Swift 6 language mode.
- Open `LightBrowser.xcodeproj`, select the shared `LightBrowser` scheme and run on My Mac.
- Development builds are ad-hoc signed and use a separate bundle identifier and data location. Release distribution and notarization are not configured.

## Build and test

```sh
xcodebuild -project LightBrowser.xcodeproj -scheme LightBrowser \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/lightbrowser-derived build

swift test --package-path Packages/BrowserKit

xcodebuild -project LightBrowser.xcodeproj -scheme LightBrowser \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/lightbrowser-derived test
```

UI tests require a logged-in macOS GUI session and permission to control the test application. Tests use isolated session directories and ephemeral website stores.

## Included

- Native browser shell with navigation in the sidebar, a full-height website frame, minimal new-tab page, light/dark/system appearance and profile accents.
- Create, rename and switch profiles, each with its own persistent WebKit website store and tabs.
- Address/search command bar, navigation, pinned tabs, close/reopen, and recent-tab switching.
- Versioned, atomic session persistence with coalesced writes. Restored tabs load only when selected.
- Tab hibernation: idle or over-budget background tabs release their web process and restore their history when selected; tabs with media, capture, full screen or unsent text stay awake. Configurable in Settings › Performance. See `docs/PERFORMANCE.md`.
- English and French UI through String Catalogs; language selection in categorized Settings (applied on next launch).

The shell currently uses one main window and one space per profile. The data model distinguishes profiles and spaces so additional spaces do not require changing the identity model.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | New tab and focus search |
| ⌘K | Command palette |
| ⌘L | Edit the active address |
| ⌘W / ⇧⌘T | Close / reopen tab |
| ⌃Tab / ⌃⇧Tab | Recent-tab cycle; release Control to commit |
| ⌘[ / ⌘] | Back / forward |
| ⌘R | Reload |
| ⇧⌘S | Toggle sidebar |
| ⌘, | Settings |

## Boundaries

`App` owns presentation and coordinates the three local `BrowserKit` targets:

- `BrowserCore`: records and rules, without UI or WebKit imports.
- `BrowserWebKit`: live page ownership and website stores.
- `BrowserStorage`: versioned browser records and atomic persistence.

See `AGENTS.md` for contributor conventions and `docs/DESIGN.md` for appearance guidelines.

## Current limits

This is a browser foundation, not yet a replacement for a daily browser. Onboarding, import, AI, extension support, downloads, credential integration, full popup/authentication flows, user-editable shortcuts, and profile deletion are not implemented. No Ultra HD, DRM, battery, or 120 fps performance claim has been validated.

Session load failures leave the original file untouched and block editing rather than replacing it with an empty session. In the sandbox container, development data lives under `Application Support/LightBrowser Development`; release data uses `LightBrowser`. The `LIGHTBROWSER_TEST_DATA` environment variable supplies a test namespace (its last path component), stored inside the app's temporary directory, and switches website stores to ephemeral mode.
