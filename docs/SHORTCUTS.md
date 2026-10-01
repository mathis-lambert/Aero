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

## Menus

The menu bar follows Safari's arrangement and Apple's menu guidelines: title-case English titles, an ellipsis when
a command asks for more before acting, dividers between groups of related actions and an SF Symbol on each Aero
item. Titles that toggle say what they will do (Show/Hide Sidebar, Add to/Remove from Favorites).

| Menu | Contents |
| --- | --- |
| Aero | Settings…, Quit |
| File | New Tab, Open Location…, Open File…, Command Bar · Close Tab, Close Window · Save As…, Export as PDF… · Import from Another Browser… · Print… |
| Edit | Native editing, Copy Link, Find › Find…, Find Next, Find Previous |
| View | Show/Hide Sidebar · Reload Page, Reload Without Cache, Stop Loading · Zoom In, Zoom Out, Actual Size · Show Downloads, Site Controls, Site Settings… |
| History | Back, Forward · Reopen Closed Tab · Show All History |
| Tabs | Next Tab, Previous Tab · Add to Favorites, Duplicate Tab, Rename Tab… · New Group with Tab, Move to Group ›, Move to Space › · Close Other Tabs, Close Tabs Below |
| Spaces | New Space… · every space, checked when shown, under its profile's name once there are several · Next Space, Previous Space |

Move to Group and Move to Space list their choices as submenus, the same ones as the tab's context menu. From the
command bar or a shortcut, the same moves open a prompt naming the tab, marking where it is now, with the arrows
choosing and Return moving it. Some commands stay out of the menu bar: numbered tabs and recent tabs belong to
the keyboard, profiles and passwords to Settings, and clearing a site's cookies or cache to its controls. Their
shortcuts always go to Aero, since a page could not pass one on to a menu item.

## Context menus

Context menus follow the same rules: sections go from the item itself, to where it is kept, to how it is organized,
then closing or removing it, which comes last and is marked destructive when it deletes something.

| Item | Contents |
| --- | --- |
| Tab or favorite | Copy Link · Duplicate Tab, Rename Tab… · Add to Favorites and Pin Tab for an open tab; Move to Pinned Tabs or Move to Favorites Grid, and Remove from Favorites, for a favorite · New Group with Tab, Move to Group ›, Move to Space › · Close Tab, while its page is open |
| Group | Rename Group…, Collapse or Expand Group · Ungroup, which keeps its tabs pinned |
| Space | Edit Space… · Move Left, Move Right · Delete Space… |
| Reload button | Reload Without Cache · Clear Cookies, Clear Cache · Site Settings… |
| Extension | The extension's own items · Pin or Unpin Extension, Open Extension Options · Extension Settings…, Manage Extensions… · Remove Extension… |
| History entries | Open, Open in New Tab · Copy Link · Delete from History |

## Routing and lifetime

Reserved browser shortcuts run only in the main browser window, outside modal sheets and marked
text composition. Find, the command bar and copy URL default to page-first through native menu handling. Each command can override website precedence with Default, Aero first, or Website first. The optional `priorities` dictionary persists only explicit choices by command ID; restoring defaults clears both binding and priority overrides. Recent-tab gestures always remain with Aero because they require modifier-release handling.
The MRU gesture commits when its configured non-Shift modifiers are released, not a hardcoded
Control key. Opening another window/sheet also ends the gesture on the next keyboard event.
The Settings recorder is a local first responder, not a global event monitor. Escape or changing selection cancels unfinished capture.
Extension commands run after reserved browser shortcuts and before the page. Aero and system bindings remain reserved.
Overrides are stored in `extensionOverrides`, keyed by extension and command, and deleted with the extension.
See [Extensions](EXTENSIONS.md#the-browsers-part).

## Verification

`ShortcutPreferencesTests` covers resolution, shipped defaults without conflicts, recording over a taken
shortcut, explicit choices over defaults, unreadable data kept until Restore defaults, protected native
commands, disable and restore, priority, and key identity. `KeyboardJourneys` drives page interception
against reserved commands, both zoom inputs, sequential and recent tab selection, favorite order,
recording a conflicting shortcut in Settings and website priority; `SidebarJourneys` checks the menus,
context menus and tooltips, and `LocalizationJourney` the French, expanded and right-to-left Settings.
Run them with `Scripts/test.sh full AeroTests/ShortcutPreferencesTests AeroUITests/KeyboardJourneys`.
Physical AZERTY/QWERTY and IME composition should also be checked on those actual input sources;
synthetic events alone do not establish hardware-layout coverage. System/global shortcuts may
be intercepted before Aero receives an event and are not fully discoverable by the recorder.
