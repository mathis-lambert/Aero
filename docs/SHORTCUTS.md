# Keyboard shortcuts

Aero keeps one command catalog (`BrowserCommand` plus the app's localized presentation and defaults),
one set of user overrides, and one resolved map. Menus, keyboard routing, tooltips and the command
bar read that map. Standard macOS editing, window and application commands remain native; Aero
rejects assignments that would shadow their known combinations. Website/global conflicts cannot
be enumerated reliably.

## Defaults

The macOS Safari/Chrome baseline supplies tab creation/closing, address focus, search, history,
reload, printing and zoom. Two intentional Aero conventions are Command-S for the sidebar
(instead of Save) and Control-Tab for **recent** tabs. Option-Command-Left/Right follows sidebar
order. Numbered tabs include favorites first, then groups (including collapsed groups), loose
pinned tabs and open tabs; Command-9 selects the last one.

| Action | Default |
| --- | --- |
| New tab / address / command bar | Command-T / Command-L / Command-K |
| Close / reopen tab | Command-W / Shift-Command-T |
| Back / forward | Command-[ / Command-] |
| Reload / reload without cache | Command-R / Shift-Command-R |
| Stop loading | Command-period; Escape when no browser dismissal or native text edit takes priority |
| Find / next / previous | Command-F / Command-G / Shift-Command-G |
| Zoom in / out / reset | Command-plus (also equals) / Command-minus / Command-0 |
| Sidebar / favorite | Command-S / Command-D |
| Downloads / history | Shift-Command-J / Command-Y |
| Print / copy URL | Command-P / Shift-Command-C |
| Next / previous in sidebar order | Option-Command-Right / Option-Command-Left |
| Next / previous space | Control-Command-Right / Control-Command-Left |
| Recent / reverse recent | Control-Tab / Shift-Control-Tab |
| Tabs 1–8 / last | Command-1…8 / Command-9 |

Other catalog actions can be assigned without a default binding. Zoom is live-page state, not a persistent site setting.

## Persistence and resolution

`browser.shortcuts` in the app's UserDefaults holds a Codable JSON document:

```json
{
  "version": 1,
  "overrides": {
    "toggleSidebar": [{ "key": "b", "modifiers": 9 }],
    "newTab": []
  }
}
```

The modifier bits are Command=1, Option=2, Control=4, Shift=8. Keys are lowercase menu characters,
including native control/function characters for Tab and arrows; display symbols are not stored.
Capture uses the current input layout, preserving Shift for letters but treating Shift required
to produce punctuation/digits as part of that character. Plus/equals have one normalized identity.

- Missing command: inherit the current catalog default.
- Empty list: explicitly disabled, including future defaults.
- A one-element list: the explicit user binding instead of the catalog default. Version 1 accepts one canonical binding per command; plus/equals are equivalent spellings of one binding.
- Stable command IDs and unknown entries survive edits. Translations never affect identity.
- Explicit bindings resolve before defaults. Conflicting defaults stay inactive and Settings
  names the winning command. Duplicate saved overrides are resolved in catalog order and reported.
- Replacing an assignment removes only the conflicting binding from the previous command and
  stores that result explicitly, so it cannot reappear after relaunch.
- Restoring one command removes its override. Restoring all clears overrides after confirmation.
- Unreadable or unsupported-version bytes are retained, editing is blocked, and built-in defaults
  remain usable. Explicit reset saves the original bytes under `browser.shortcuts.recovery` first.
- Each edit encodes and replaces one complete preferences value. There is no migration framework
  or persisted copy of defaults. Future format changes must explicitly convert supported versions before replacing the blob; unknown versions remain preserved and blocked.

## Routing and lifetime

Reserved browser shortcuts run only in the main browser window, outside modal sheets and marked
text composition. Find, the command bar and copy URL default to page-first through native menu handling. Each command can override website precedence with Default, Aero first, or Website first. The optional `priorities` dictionary persists only explicit choices by command ID; restoring defaults clears both binding and priority overrides. Recent-tab gestures always remain with Aero because they require modifier-release handling.
The MRU gesture commits when its configured non-Shift modifiers are released, not a hardcoded
Control key. Opening another window/sheet also ends the gesture on the next keyboard event.
The Settings recorder is a local first responder, not a global event monitor. Escape or changing selection cancels unfinished capture.

## Verification

The focused `ShortcutE2ETests` exercise page interception vs reserved commands, both plus/equals
zoom inputs, sequential vs recent tab selection, favorite order, conflicting capture, protected
native commands, explicit disable/reset, relaunch, default/override collisions, unreadable preference preservation, and expanded French/RTL Settings. Existing browsing tests
cover page-first routing; the tooltip test checks that the sidebar now advertises Command-S.

Run with `Scripts/run-e2e.sh AeroUITests/ShortcutE2ETests` and retain its result bundle and manifest.
Physical AZERTY/QWERTY and IME composition should also be checked on those actual input sources;
synthetic events alone do not establish hardware-layout coverage. System/global shortcuts may
be intercepted before Aero receives an event and are not fully discoverable by the recorder.
