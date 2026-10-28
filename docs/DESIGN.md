# Design

Aero uses compact, neutral chrome around the page. The Gilda Display mark and dithered wind belong to the app icon, New Tab and the onboarding; the chrome uses system typography and SF Symbols, with favicons for websites. The onboarding's titles use Gilda Display (bundled in `Resources/Fonts` under the SIL Open Font License) on its paper and ink colors (`App/Design/BrandDesign.swift`); its controls, text and previews keep the chrome's own type, colors and components. See [Onboarding](ONBOARDING.md).

The DMG installation window uses the same light paper, ink and Gilda Display identity.
Its artwork and Finder layout live in `Scripts/DMG`; see [Build and release](BUILD_AND_RELEASE.md#installer-window).

## Shared components

Tokens and reusable components live in `App/Design`. `BrowserDesign` owns shared dimensions, typography and motion; `BrowserPalette` owns semantic colors. Keep one-off layout values local rather than turning them into tokens. Source definitions are authoritative for numeric values.

Use semantic surfaces, one consistent hairline border, and visible hover/pressed states. Space color identifies organization; error states need text as well as color. Selection must be exposed to accessibility. Respect longer translations, RTL, Reduce Transparency and the shared `browserReduceMotion` policy. See [Performance](PERFORMANCE.md) for animation scheduling.

## Glass

The chrome's surfaces are Liquid Glass through one modifier, `browserGlass(_:tint:radius:)` (`App/Design/BrowserGlass.swift`), whose role sets the intensity: the more a surface matters, the more glass it is. No surface applies glass directly.

- **Selection**: the selected tab, the active favorite and the control bar's chosen result are a full lens, responsive to the pointer. The favorite's is tinted with its favicon's color, which also glows behind it (`glassGlow`), so the glass bends that light.
- **Control**: full glass that answers the pointer: the address, a capsule whose buttons light up as circles; the tiles and switches of the site's control center; the history search; the New Tab page's website tiles, tinted with their favicon's color, and its open tabs. A switch that is on is glass colored through with the space's color (**accent**).
- **Tile**: a favorite at rest is clear glass at half strength, still, the window showing through; under the pointer it only brightens, glass coming and going at each pass would flicker over its icon.
- **Hover**: a tab or folder picked with ⌘ or ⇧ is faint clear glass.
- **Container**: an open folder holds its tabs on a pane at a fraction of the glass, so the selected tab stands out on it; a margin keeps two open folders apart.
- **Panel**: what floats over the page is full glass, untinted, so its content reads over any page: the control bar, prompts, the find bar, tooltips, a folder's preview, the password picker and offers, the portrait studio, the page zoom indicator, and the onboarding's cards. The sidebar revealed over the page is glass too (**sidebar**).

The window itself is a little translucent (`WindowBackdrop`): the desktop shows through blurred under the chrome's color at 70 %, tinted by the space's color, which follows a switch of space. A dragged favorite leaves a plain gap; no container groups the tiles, whose glass would then bend their own icons. Settings keeps the system's own forms. With Reduce Transparency every glass surface is opaque with the hairline border, and no glow shows.

## Layout

The website fills the page frame without a top toolbar. The sidebar groups navigation, address, favorites and tabs; its footer centers the space switcher, where the space shown has its icon and name on a neutral pill, and the others are grey icons. The page, raised above the sidebar and the window, casts a soft shadow on every side. Dragging its edge resizes or folds it, saving width only at the end. Window resizing clamps display width without changing the preference. A hidden sidebar can be revealed from the leading edge. The window's own close, minimize and full-screen group sits in the sidebar header, or in the onboarding's, because only AppKit's group gives its shared hover symbols and inactive look; `WindowControls` alone moves it into the latest header shown, hides it in the titlebar when no header shows it, and returns it to AppKit around full-screen transitions.

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
