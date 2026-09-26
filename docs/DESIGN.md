# Design

The chrome is a compact, neutral workspace around the page. The brand (the Gilda Display serif and the dithered wind) appears only on the app icon and on the New Tab page's wind (`docs/CONTROL_BAR.md`): no wordmark, logo, serif, illustration or marketing copy in the chrome.

Tokens and shared components live in `App/Design/BrowserDesign.swift`: `BrowserDesign` (radii, typography, sizes, motion), `BrowserPalette` (colors, read with `@Environment(\.palette)`), the shadow and animation modifiers, `Hairline`, `IconButton`, `ShortcutLabel` and `ProfileBadge`. Promote a value to a token when it is a repeated rule; keep one-off layout values local.

## Tokens

| Element | Rule |
| --- | --- |
| Surfaces | `sidebar` (window ground), `canvas` (page frame, Settings list), `raised` (selection, cards, fields); all opaque, so Reduce Transparency needs nothing more |
| Fills | `hover`, `fill` and `pressed`: ink at 4, 6 and 10% |
| Lines | `line` is the only divider and border, drawn with `Hairline` |
| Accent | Per profile, for identity and selection. `luminous` is its brighter version for light effects on the dark canvas; `light(in:)` picks it or the tint |
| Signal | `miss` for errors and the find bar's no-match border, always with text |
| Typography | System face: 13 pt chrome, 12 pt medium labels, 11 pt captions and keycaps, 22 pt semibold titles, 15 pt control bar field, 9 pt row glyphs |
| Spacing | 4, 8, 12, 16, 24, 32, 48 pt; rows use a 10 pt inset and icon gap |
| Corners | 20 pt window; page 14 pt inside a 6 pt inset; floating sidebar 8 pt inside a 12 pt inset; 12 pt cards and fields; 8 pt controls; 4 pt keycaps |
| Hover | Every borderless button takes `hover` under the pointer and `pressed` while pressed, through `QuietButtonStyle` |
| Shadows | `floatShadow` for the revealed sidebar and the find bar, `panelShadow` for the control bar and Settings. No others |
| Motion | One 0.28 s spring through `browserAnimation(value:)`, dropped with Reduce Motion. Nothing animates while idle |
| Icons | SF Symbols; site favicons for websites |

## Layout

- The website fills the rounded page frame from its top edge; there is no top bar or native toolbar.
- The sidebar's first row holds the window controls (standard AppKit buttons created through public API), sidebar toggle, back, forward and reload; the second holds the current address. Then one page per profile with pinned tiles, New Tab and the tab list, and a footer with the downloads button, the profiles and a button to add one (`docs/PROFILES.md`).
- The hidden sidebar reappears over the page when the pointer reaches the left edge; its hover area includes its margin so it does not close on the way in.
- The find bar floats over the page's top trailing corner; a miss shows text, the `miss` border and a short shake.
- Settings is its own window: a category list (General, Tabs, Profiles) and cards of working options only. Language changes apply at the next launch, and say so.

## Tooltips and keycaps

`.tooltip(_:shortcut:)` replaces the system help tag on every chrome control: a small `raised` plate with a `line` border and the float shadow, the label, and the command's keycaps when it has a shortcut. It appears 0.5 s after the pointer rests on the control, then follows it at once to a neighbour for a moment, like the system's. It lives in its own borderless panel, so the sidebar or the window edge never clips it, and it takes the window's appearance. The pointer leaving, a click, a key or a scroll hides it. Only a hovered control has a timer; nothing runs otherwise.

`Keycaps` draws a shortcut as keys: one cap per modifier and key, in the system face at 11 pt medium, on a `raised` face with a hairline border and a darker bottom edge. Shortcuts come from the command catalog (`BrowserCommand.shortcut`), so a tooltip, the control bar and the menu always agree. Special keys use their symbols (↵, ⇥, ⌫) and Escape reads "esc".

Failure modes:

1. A tooltip stays after the pointer leaves, after a click, a key, a scroll, or when the window closes or the app goes to the background.
2. Tooltips flicker while the pointer crosses a row of buttons, or every neighbour waits the full delay again.
3. A tooltip is clipped by the sidebar or leaves the screen.
4. A tooltip takes the wrong appearance, or two show at once.
5. A shortcut shown differs from its menu item.

Verification: E2E `testTooltipsShowLabelAndShortcut` (hovering the sidebar toggle shows its label and keys, a click hides it; 1, 5). Appearance and clipping are checked from its screenshot.

## App icon

`App/Resources/AppIcon.icon` is the system icon: a Gilda Display capital A filled with the dithered wind. `swift Scripts/generate-app-icon.swift <GildaDisplay-Regular.ttf>` regenerates it and the twenty alternates in `App/Resources/AppIcons` (font not stored here).

Settings › General offers Automatic (the system icon, which follows the appearance) or an alternate. `AppIcon` puts the alternate on the app bundle, as the Finder's Get Info does, so the Finder, the Dock, Launchpad and Spotlight show it even while Aero is closed; Automatic removes it. At launch Aero sets it again if an update or a build replaced the bundle. Aero is not sandboxed, which this needs; the build strips the icon file before signing, since `codesign` rejects it.

Failure modes:

1. A saved variant no longer exists: fall back to Automatic.
2. A bundled icon is missing or unreadable, or the bundle is not writable: keep the system icon.
3. Choosing Automatic leaves the previous variant in the Dock.
4. The choice is lost after relaunch, or applied too early and overwritten.
5. Test runs change the real preference.

6. An update or a rebuild drops the icon, or a development build fails to sign because of it.

Verification: E2E `AppearanceE2ETests` (theme and variant survive a relaunch, the icon file appears on the bundle and Automatic removes it; test preferences are namespaced). How the Finder and the Dock draw it is checked by eye.
