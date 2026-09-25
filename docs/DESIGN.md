# Browser appearance

## Direction

The browser is a compact, neutral workspace. Keep the page as the main surface, with a narrow sidebar and a rounded content frame. The brand (the Gilda Display serif and the dithered wind, `docs/IDENTITY.md`) lives on the app icon and brand surfaces: the chrome and the New Tab page carry no wordmark, logo, serif, illustration or marketing copy.

The chrome's tokens and shared components live in `App/Design/BrowserDesign.swift`: `BrowserDesign` (radii, typography, sizes, motion), `BrowserPalette` (colors and fills), the shadow and animation modifiers, `Hairline`, `IconButton`, `ShortcutLabel` and `ProfileBadge`. Features use them instead of literals. There is no external UI or icon dependency.

## Foundations

| Element | Guideline |
| --- | --- |
| Surfaces | `sidebar` (window ground), `canvas` (page frame, Settings list), `raised` (selection, cards, fields); all opaque |
| Fills | `hover`, `fill` and `pressed`: ink at 4, 6 and 10%, over any surface |
| Lines | `line` (ink at 11% light, 15% dark) is the only divider and border; drawn with `Hairline` |
| Accent | Selected per profile; use sparingly for identity and selection |
| Typography | System face only: 13 pt chrome, 12 pt medium labels, 11 pt captions and monospaced keycaps, 22 pt semibold page titles, 17 pt large search fields, 9 pt row glyphs |
| Spacing | 4, 8, 12, 16, 24, 32, 48 pt; rows use a 10 pt inset and icon gap, large search fields a 14 pt glyph gap |
| Corners | 20 pt window and Settings window; 14 pt page inside a 6 pt inset; 8 pt floating sidebar inside a 12 pt inset; 12 pt cards and search fields; 8 pt controls; 4 pt keycaps |
| Shadows | `floatShadow` for the revealed sidebar and the find bar; `paletteShadow` for the command palette, the New Tab field and the Settings window. No others |
| Signal | `miss` (orange-red) for errors and the find bar's no-match border, always with text |
| Sidebar | 224 pt; window controls and navigation share a 52 pt header |
| Page frame | Full-height website with a 6 pt outer inset; no top bar |
| Navigation rows | 32–34 pt; selection visible without relying on color alone |
| Icons | SF Symbols from 9 pt row glyphs to 18 pt field glyphs; localized accessibility names |

Promote values to shared tokens when they form a repeated visual rule. Keep one-off layout values local. Do not wrap every native control in a design-system abstraction.

## Browser layout

- New Tab is the default empty surface. It contains a centered address/search field and a submit action. No separate Home destination, hero text, date, wordmark, or suggested-site list.
- Command-T selects the new-tab surface and focuses its input. Command-L edits the current URL, or focuses the input when no web page is active. Command-K opens the command palette.
- Let the website fill the rounded page surface from its top edge. Keep window controls, sidebar toggle, back, forward, and reload aligned on the sidebar's first row; place the current address on its second row.
- Create standard AppKit window buttons in the sidebar header using its public API, with native close, minimize, fullscreen and Option-click zoom actions; do not add a native toolbar over the content or move private titlebar views. The sidebar has a fixed mode and a hidden mode: hovering at the left window edge temporarily reveals it over the page. Give this floating panel a 12 pt outer margin, 8 pt radius, subtle border and shadow, and a short spring entrance/exit. Its hover area includes the margin so moving into it never closes the panel. The keyboard shortcut switches the fixed mode. No button overlays the page while the sidebar is hidden.
- The sidebar contains pinned pages, the profile switcher, a New Tab action, and the tab list. Pinned pages use a compact grid. Rows and pinned tiles show the site favicon; the site initial or a globe symbol stands in until one is known.
- A Downloads section appears at the bottom of the sidebar only while the session has downloads.
- The find bar floats over the top trailing corner of the page; a miss is shown with text, the `miss` border and a short shake (no shake with Reduce Motion).
- Dragging a tab shows an insertion line above the drop target; an empty pinned grid opens into a dashed tile while a tab hovers it.
- Do not fill empty sidebar space with instructions, counters, branding, or a settings gear. Settings are available through the standard application menu and Command-comma.
- Maintain the rounded page frame and small outer insets. The sidebar toggle remains available in both layouts.

## App icon

`App/Resources/AppIcon.icon` is an Icon Composer document with one flat layer (no glass): a Gilda Display capital A filled with the brand's dithered wind, `aero-blue` dots on `paper` in light and `#8a93ff` on night in dark. The system supplies the mask and highlights. Regenerate every icon with `swift Scripts/generate-app-icon.swift <GildaDisplay-Regular.ttf>` (font from Google Fonts, SIL Open Font License; not stored here): it writes the two system layers and the twenty alternates in `App/Resources/AppIcons` (the A in nine palettes, the feather in eleven) in one pass. The brand direction, including the feather variant, lives in the Aero design system and `docs/IDENTITY.md`.

### Choosing an icon

Settings › General offers the app icon: **Automatic** (the system icon, papier in light and nuit in dark) or one of the twenty alternates in `App/Resources/AppIcons`; the A on paper and on night is the system icon itself, so it is not repeated as an alternate. The choice replaces the Dock icon once the session has loaded at launch, and immediately when changed, drawn on the macOS icon grid (an 824 pt rounded square on a 1024 pt canvas). macOS does not let a sandboxed app change its Finder or Launchpad icon, so those keep the system icon; the setting says so. The picker renders its thumbnails away from the main actor while it is shown and keeps none afterwards.

Failure modes:

1. The saved choice names a variant that no longer exists: fall back to Automatic without crashing.
2. A bundled icon file is missing or unreadable: keep the system icon.
3. Choosing Automatic leaves the previous variant in the Dock.
4. The choice is lost after relaunch, or applied before the application is ready and then overwritten.
5. Test runs change the icon stored for real use.

Verification: E2E `testAppearanceChoicesPersistAcrossLaunches` (select the dark theme and a variant, relaunch, both still selected; Automatic restores the default selection). Tests namespace preferences, so a test choice never reaches real settings (5). The Dock image itself is not asserted by UI tests.

## Settings

Use a compact dedicated settings window with a left category list and right detail pane. A close button at the top left replaces the native window controls. Categories are General (language, appearance, app icon), Tabs (hibernation), and Profiles. Display only working options; do not add placeholder account, sync, privacy, or extension pages.

Group related options in `raised` cards with a `line` border; the category list sits on `canvas` and marks the selection with `raised`, like the tab list. Appearance offers light/dark/system choices. Language offers the system default, English, and French; changes are applied on the next launch, with an explicit message. This uses per-app localization preferences instead of runtime bundle replacement.

## Interaction and accessibility

- Selected tabs and settings categories use the raised surface. Hover and press use the `hover` and `pressed` fills.
- Profile identity includes its name as well as color.
- The command palette offers every available command of the central catalog, filtered by title as you type, after the typed address or search. It supports arrows, Return, and Escape. Menus and shortcuts invoke the same command handlers, scoped to the focused browser scene.
- Show one thin loading indicator and a clear recovery action on navigation failure.
- Use the shared 0.28-second spring for shell transitions, through `browserAnimation(value:)`, which drops it with Reduce Motion. Nothing animates while idle.
- Keep WebKit pages stable while SwiftUI changes. Visual transitions must not reload websites.
- Prefer semantic controls and real keyboard focus. Opaque surfaces inherently accommodate reduced transparency. Check contrast, VoiceOver, and long labels when changing components.

## Internationalization

English is the source language; French is included in String Catalogs. Use complete localized messages, locale-aware formatting, and leading/trailing layout. Persisted IDs are language independent. Test both appearances, longer translations, and RTL layout when affected.

## Feature placement and validation

Feature UI belongs in `App/Features/<Feature>`. Shared controls and tokens belong in `App/Design`. Onboarding and import are future independent features using normal browser operations; neither is part of this batch.

Visual checks do not establish sustained 120 Hz rendering, battery savings, full accessibility compliance, or Ultra HD/DRM compatibility. Validate each before making a claim.
