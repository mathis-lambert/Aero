# Design

Aero uses compact, neutral chrome around the page. The Gilda Display mark and dithered wind belong to the app icon, New Tab and the onboarding; the chrome uses system typography and SF Symbols, with favicons for websites. The onboarding's titles use Gilda Display (bundled in `Resources/Fonts` under the SIL Open Font License) on its paper and ink colors (`App/Design/BrandDesign.swift`); its controls, text and previews keep the chrome's own type, colors and components. See [Onboarding](ONBOARDING.md).

The DMG installation window uses the same light paper, ink and Gilda Display identity.
Its artwork and Finder layout live in `Scripts/DMG`; see [Build and release](BUILD_AND_RELEASE.md#installer-window).

## Shared components

Tokens and reusable components live in `App/Design`. `BrowserDesign` owns shared dimensions, typography and motion; `BrowserPalette` owns semantic colors. Keep one-off layout values local rather than turning them into tokens. Source definitions are authoritative for numeric values.

Use semantic surfaces, one consistent hairline border, and visible hover/pressed states. Space color identifies organization; error states need text as well as color. Selection must be exposed to accessibility. Respect longer translations, RTL, Reduce Transparency and the shared `browserReduceMotion` policy. See [Performance](PERFORMANCE.md) for animation scheduling.

## Layout

The website fills the page frame without a top toolbar. The sidebar groups navigation, address, space identity, favorites and tabs; its footer centers the space switcher. Dragging its edge resizes or folds it, saving width only at the end. Window resizing clamps display width without changing the preference. A hidden sidebar can be revealed from the leading edge. The window's own close, minimize and full-screen group sits in the sidebar header, or in the onboarding's, because only AppKit's group gives its shared hover symbols and inactive look; `WindowControls` alone moves it into the latest header shown, hides it in the titlebar when no header shows it, and returns it to AppKit around full-screen transitions.

Settings uses native sidebar navigation and back/forward history. Profiles and Spaces are separate sections with list-to-detail navigation. Inline edits commit automatically; destructive actions and identity changes require explicit confirmation. See [Spaces](SPACES.md).

## Prompts

Every question uses the shared `Prompt` presentation, over the window where it was asked (the browser or Settings), with one card surface, a concise title, optional explanation and trailing actions; a confirmation before an irreversible action is a `Confirmation`. No system alert or confirmation dialog is used. Return confirms, Escape or clicking outside cancels. The underlying window must not receive input. Replacing a pending extension prompt must resolve its request rather than leave a caller waiting. System file, print and certificate panels remain native sheets.

## Tooltips and keycaps

Use `.tooltip(_:shortcut:)` for chrome controls and `Keycaps` for bindings from the shared shortcut resolver. Tooltips must not clip against the sidebar or capture input; leaving, clicking, typing, scrolling or deactivating the window dismisses them. Only the hovered control schedules a delay.

## Text entry

Browser-owned text fields disable automatic correction. Web pages retain WebKit's own text-input behavior and their `autocorrect` and `autocapitalize` attributes.

## App icon

`App/Resources/AppIcon.icon` contains the adaptive system icon. Regenerate it and the alternates with:

```sh
swift Scripts/generate-app-icon.swift <GildaDisplay-Regular.ttf>
```

The font is not stored in the repository. Settings previews use bundled artwork, never the current custom bundle icon. Automatic removes the custom icon; the system draws the running Dock icon in every icon style, and Aero draws the artwork of its own appearance only when it differs from the system's. Alternate icons write to Aero's own bundle, requiring an unsandboxed app. The build removes the custom icon before signing. Missing artwork or an unwritable bundle must leave the system icon usable.
