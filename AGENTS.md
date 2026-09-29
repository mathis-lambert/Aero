# Aero contributor instructions

## Product and scope

Build a lightweight, native macOS browser for Apple Silicon using WebKit. Prioritize responsive navigation, low idle energy use, controlled memory usage, reliable sessions, and useful features. Use Arc as a reference for navigation and Raycast as a reference for keyboard command discovery.

- Use recent stable Apple tooling and APIs. Pin the actual toolchain and minimum macOS version in project configuration when scaffolding; do not leave builds dependent on an unspecified "latest" version.
- Do not add Intel support or compatibility layers for old OS versions without a product requirement.
- Prefer Apple frameworks. Justify external dependencies through a concrete benefit, maintenance cost, and runtime impact.
- The neighboring Search repository is a reference, not this application's architecture or runtime dependency. Review any reused code and retain required license notices.

## Working principles

- Choose the smallest maintainable implementation that satisfies the requested behavior.
- Deliver coherent changes; do not artificially split authorized work into tiny approval stages.
- Keep APIs small, ownership explicit, and names descriptive. Avoid speculative frameworks, generic service layers, global event buses, and singleton-based dependency lookup.
- Inspect existing code before adding an abstraction. Extract shared code when there is a real shared responsibility, not a hypothetical future consumer.
- Preserve unrelated work. Report changes, focused validation, and material limitations accurately.
- Use `uv`, not `pip`, if Python tooling is needed.

## Repository layout and module boundaries

Use an Xcode application project and one local Swift package. This is a responsibility map, not a requirement to create empty folders or a fixed number of files.

```text
App/
  Application/          # Startup, dependency assembly, windows, session coordination
  Commands/             # Menus, command dispatch, and keyboard routing
  Features/             # UI and presentation behavior grouped by feature
  Design/               # Shared visual tokens, motion, and reusable UI components
  Resources/            # Application assets and string catalogs
Packages/BrowserKit/
  Package.swift
  Sources/
    BrowserCore/        # Models, navigation rules, command definitions
    BrowserWebKit/      # WebKit integration and loaded page lifecycle
    BrowserStorage/     # Application persistence
  Tests/                # Tests for each package target
Tests/                  # App unit tests, UI journeys, fixtures and test plans (docs/TESTING.md)
Configuration/          # Build settings, property lists, entitlements
Scripts/                # Development tools: test runner, memory measurement, icon and filter list generation, notarized release; never run by the app
docs/                   # Project documentation and specifications
```

- `BrowserCore` may use Foundation but must not depend on SwiftUI, AppKit, WebKit, or a persistence framework.
- `BrowserWebKit` and `BrowserStorage` depend on `BrowserCore`, not on each other or on the application.
- The application assembles these components and coordinates their interactions.
- `BrowserWebKit` owns website data stores; `BrowserStorage` owns browser records such as history and session metadata. Do not copy or manipulate WebKit's internal storage files.
- Keep feature-specific views, presentation models, and helpers together under `App/Features/<Feature>/`. Do not create global `Views`, `ViewModels`, or `Helpers` dumping grounds.
- Keep the design system in the application. Do not create a package per feature.
- Use module boundaries to enforce dependency direction. Add another target only when a concrete boundary warrants it.
- Default to `internal` visibility. Use `package` for access between targets in the local package where appropriate; expose `public` APIs only when the application needs them.

## State and ownership

- Separate durable browser records, live runtime resources, and transient presentation state.
- A tab is a stable record, not a `WKWebView`. Tabs must be representable and restorable without loading their pages.
- Give loaded pages an explicit owner outside SwiftUI view reconstruction. Updating a view must not reload, recreate, or discard a page unintentionally.
- Keep shared session state separate from window-local selection, focus, panels, and layout. Do not make one global browser object responsible for every feature.
- Distinguish profiles from spaces: profiles own browsing identity and isolation; spaces organize tabs and refer to a profile. Multiple spaces may use the same profile.
- Use stable identifiers and one authoritative mutation path for each piece of state. Do not mirror mutable state across unrelated models.
- Handle stale callbacks: a closed tab, replaced navigation, or deleted profile must not be resurrected by a late asynchronous result.

## Swift conventions and concurrency

- Use Swift 6 language mode and strict concurrency checking. Follow Swift API naming conventions and use English identifiers and technical documentation.
- Prefer value types for records and explicit enums for mutually exclusive states. Use reference types where identity or resource ownership is required.
- Use `@State` for local view state and `@Observable` for shared observable presentation models. Do not add a view model to every view by convention.
- Isolate UI state and WebKit objects to `@MainActor`. Keep blocking I/O and expensive processing out of rendering and main-actor interaction paths; `async` alone does not move work off the main actor.
- Use structured concurrency where possible. Give long-lived tasks an owner, cancellation behavior, and teardown path. Remove observers and script handlers when their owner ends.
- Do not silence isolation errors with unchecked conformance or unsafe isolation escapes without a documented, verified invariant.
- Pass dependencies explicitly. Introduce protocols for meaningful boundaries or test substitution, not for every concrete type.
- Handle actionable errors explicitly. Avoid force unwraps and silent `try?` on user-data operations; document intentional best-effort behavior.

## Internationalization

- Put user-visible text in String Catalogs (`.xcstrings`), including menu items, command titles, tooltips, accessibility labels, empty states, and errors.
- Use native localization APIs such as SwiftUI localized text and `String(localized:)`. Resolve strings through the owning resource bundle; package resources use `Bundle.module` when configured.
- Keep catalogs with their owning app or target. Do not move display strings into `BrowserCore` solely to centralize localization; core identifiers and errors must remain independent of translated text.
- Use complete messages with interpolation and catalog plural variations. Do not concatenate translated sentence fragments or implement plural rules manually.
- Use locale-aware format styles for dates, numbers, sizes, and durations.
- Keep persisted identifiers, command IDs, and preference keys independent of display language. Search commands by their localized titles and relevant localized aliases.
- Support longer translations, Unicode input, and right-to-left layout through flexible sizing and semantic leading/trailing alignment.
- Treat keyboard layout separately from language. Validate accented input, AZERTY/QWERTY, and input-method composition when touching text or shortcuts.
- Validate changed UI with an expanded pseudolocalization or longer translation and right-to-left layout where relevant. Do not claim a language is supported merely because its catalog exists.

## Design system and accessibility

- Use SF Symbols for interface icons and site favicons for website identity. Avoid adding an icon library without a demonstrated gap.
- Keep shared semantic colors, spacing, typography, and motion in `App/Design`. Extract components for repeated behavior; do not wrap every native control.
- Prefer native controls, system typography, and semantic colors. Respect appearance, contrast, accessibility labels, keyboard focus, and VoiceOver.
- Use SwiftUI transitions and spring animations; use AppKit/Core Animation only for a concrete interaction requirement.
- Keep transitions interruptible and gestures responsive. Respect Reduce Motion and Reduce Transparency. Do not run decorative animations while idle.
- Distinguish native UI smoothness from web-content frame rates. Do not claim 120 fps support based only on the display's refresh rate.

## Commands and keyboard interaction

- Maintain a central command catalog with stable IDs, localized presentation, default shortcuts, and contextual availability.
- Menus, buttons, the control bar, and keyboard shortcuts must invoke the same action implementation.
- Route actions to the active window, pane, and focus context. Keep the dispatcher thin; feature owners implement behavior.
- Use native menus and the responder chain for standard editing commands. Restrict custom key interception to interactions that need it, such as an MRU tab switcher.
- Do not intercept ordinary text entry, IME composition, or page shortcuts indiscriminately.
- Keep user shortcut overrides separate from defaults. Detect conflicting bindings in the same context and show effective shortcuts consistently.
- Test focus routing, command availability, Escape dismissal, and Ctrl-Tab selection/commit behavior when changing them.

## Performance, WebKit, and user data

- Create pages lazily. Bound caches and retained snapshots; cancel obsolete work and avoid unnecessary polling.
- Before unloading a page, account for unsaved input, active media/capture, downloads, and other state that cannot safely be restored. Do not promise lossless restoration of arbitrary web application state.
- Keep profile website data and browser-owned records isolated. Private browsing must not enter persistent history or session restoration.
- Configure a page's data store before creation. Changing a tab's profile requires an explicit transition, not relabeling a live page.
- Use public APIs by default. Do not copy private WebKit workarounds from Search without documenting the need and compatibility consequences. Accepted private API exceptions are the picture in picture preference (`docs/SITE_CONTROLS.md`) and WebKit's high-refresh rendering preference (`docs/PERFORMANCE.md`).
- Validate origins and payloads at JavaScript/native bridges. Scope site permissions and never log credentials, cookies, or sensitive page contents.
- Prefer integration with Apple's credential facilities over building another password vault. Keychain storage alone does not imply Apple Passwords AutoFill integration. Passwords are the documented exception, because no Apple facility fills a third-party WebKit browser (`docs/PASSWORDS.md`); passkeys go through AuthenticationServices.
- Version persisted formats and use atomic writes or transactions. The SQLite baseline is the compatibility boundary: append ordered migrations for future changes; never edit shipped migrations or silently reset incompatible data. No legacy JSON reader or importer. Preserve unreadable data for explicit recovery. See `docs/STORAGE.md`.
- Keep development and test data separate from real browsing data, including WebKit stores and settings.
- Evaluate memory across the app and its WebKit processes. Measure representative idle, navigation, many-tab, and media scenarios before making performance claims.
- Preserve WebKit's available Ultra HD/media capabilities. Verify actual playback quality per service and hardware; WebKit use alone does not prove Safari-equivalent DRM support.

## Adding or changing a feature

1. Identify its state owner and module boundary; reuse existing navigation and page lifecycle behavior.
2. Put feature UI and presentation behavior together. Add only the core rules, WebKit integration, or storage changes the feature needs.
3. Register user actions in the command system and provide localized, accessible presentation.
4. Define relevant cancellation, failure and restoration behavior. Avoid stale events and duplicate side effects.
5. Verify behavior at the lowest level that can observe it, under the testing policy below, and inspect affected native interactions. Measure performance when the change affects page lifetime, rendering, caches, or background work.

## Validation and project status

- Test each behavior once, at the lowest level that can observe it (docs/TESTING.md). Unit tests (Swift Testing) cover rules with many cases or failure modes: in the package for its modules, in `Tests/AeroTests` for the app's own. Before writing such code, list its failure modes and write the tests that exercise them. Never test views, trivial values or the implementation's shape.
- UI journeys (XCUITest) cover only what needs the real app: WebKit, focus and keyboard routing, menus, windows, drag and drop, persistence across launches. Extend the journey that already goes there before adding one; seed the state it does not verify; wait for conditions, not time; keep each journey under four minutes.
- Every UI run retains its `.xcresult` with the relevant screenshots and a manifest of the exact command, revision, environment and fixtures.
- Prioritize profile isolation, tab lifecycle, session recovery, command routing, and prevention of user-data loss.
- Run the smallest relevant plan: `unit` after each change, `smoke` while developing, `full` before a commit or pull request, plus the application build when changing shared APIs or integration. Report exactly what ran and what remains unverified.
- The application is `Aero.xcodeproj`, with shared `Aero Dev`, `Aero Nightly`, `Aero Beta` and `Aero` schemes and a local `Packages/BrowserKit` package. Use Xcode 27.0 (27A266a) with its Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`; build-time only), Apple Swift 6.4, Swift 6 language mode, macOS 26.0+, and arm64.
- Build: `Scripts/build.sh build`; `run` launches Aero Dev, `dmg` packages a local optimized build. Both Debug and Release use the dev identity. Toolchain requirements are checked by the script and Xcode build phase.
- Package tests: `swift test --package-path Packages/BrowserKit`. Live WebKit tests need access to macOS WebKit services. In a restricted execution environment, use writable compiler caches and disclose any environment-related limits.
- Tests: `Scripts/test.sh [unit|smoke|full|performance] [test-identifier…]` runs the package tests and the matching plan of `Tests/Plans` with Aero Dev; journeys require a logged-in GUI session. It retains a unique `.xcresult` and reproduction manifest in `/tmp`. `AERO_TEST_DATA` isolates records and makes website stores ephemeral. See `docs/TESTING.md`.
- Distribution: follow `docs/BUILD_AND_RELEASE.md`. `Scripts/distribute.sh <tag-at-HEAD>` prepares signed, notarized DMGs from a clean checkout; GitHub Actions publishes them. Signing secrets belong to the `distribution` environment. Never add personal signing settings to source builds.
- Performance: tab hibernation, signposts, the launch test and `Scripts/measure-memory.swift` are described in `docs/PERFORMANCE.md`.
- Current scope: one main window, multiple spaces per profile, English/French catalogs, transactional SQLite browser state with forward migrations and recovery (`docs/STORAGE.md`), logically profile-scoped SQLite history (`docs/STORAGE.md`), session-only downloads, and a native light/dark/system appearance. Dev, nightly, beta and stable bundle IDs/data locations are separate, independently of compiler optimization. Extensions run per profile on WebKit's engine, with inert declarations for the APIs it lacks (`docs/EXTENSIONS.md`). What is not implemented yet is listed in the README.
- Aero is distributed outside the Mac App Store and is not sandboxed: the app icon choice writes to its own bundle. Website content stays in WebKit's sandboxed processes. The update channel and future multi-window behavior remain open.
- Keep this file concise and current. Put detailed feature specifications in `docs/`; add nested `AGENTS.md` files only for genuinely different local requirements.
