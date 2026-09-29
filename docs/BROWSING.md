# Browsing

## Control bar

The same address, search and command field appears on New Tab and over a page. ⌘L replaces the current page; ⌘K opens results in a new tab. On New Tab, both focus its existing field.

Results are ordered: address/search, engine suggestions, current-space tabs, profile history, commands. Return opens the selected result; Escape dismisses the overlay or clears New Tab. Commands use the same dispatcher as menus and shortcuts; see [Shortcuts](SHORTCUTS.md).

Suggestions use an ephemeral session without profile cookies or credentials. Address-like input is never sent. Requests are delayed until typing pauses and canceled when the query changes. Local history publishes independently of network responses.

## Favorites and open tabs

Each space has a favorites grid, pinned favorites with optional groups, and ordinary tabs. New Tab is a permanent selectable row.

- Closing a favorite releases its page but retains its record. Favorites start closed after relaunch. Removing an open favorite turns it into an ordinary tab; removing a closed favorite deletes it.
- Closing an ordinary tab removes it; Reopen Closed Tab restores it.
- Dragging reorganizes tabs within the space. The insertion marker is the committed destination; canceling leaves the order unchanged. External drags export URLs; incoming files, text and tabs from other spaces are rejected.
- Move to Space preserves a live page within the same profile. Crossing profiles requires confirmation and a new page identity; see [Spaces](SPACES.md).
- Ungroup preserves the group's favorites. Custom names persist independently of website titles.

## History

History (`aero://history`, ⌘Y) is a native tab, reused within its space. Internal pages create no WebKit page and cannot be opened by websites. Web navigation commands are unavailable on them.

Visits are recorded on document commits and address changes, excluding reloads and hibernation restores. Relaunching and loading a restored URL counts as a visit. Titles update existing entries. Search matches title/address words and prefixes without case or diacritics. Clear and delete apply only to the current profile. Storage, retry and retention rules are in [Storage](STORAGE.md).

## Favicons

Icons are fetched anonymously, downsampled off the main actor and cached by profile and host. Restored tabs can show cached icons without loading their pages. Memory retains at most 256 icons and their derived selection colors. SVG is unsupported; App Transport Security blocks nonlocal plain-HTTP icon requests.

## Popups

Popups use WebKit's supplied configuration and open in the opener's space, preserving `window.opener`, messaging and OAuth. Only script-opened tabs may close themselves. Loaded popup relationships prevent hibernation. Separate popup windows are not supported. A popup or link for another scheme is handled as in [Other apps](OTHER_APPS.md) › Links to other apps.

## Find and downloads

Find searches the selected page with wrapping, case-insensitive matching. Escape restores page focus; switching tabs closes it. Results report presence, not a count. Page-first shortcuts let web editors handle their own find.

Downloads use sanitized unique filenames in Downloads, with quarantine and source metadata. Closing a tab does not cancel them. The downloads popover supports cancel, retry, Show in Finder and clearing inactive entries. The list lasts only for the session; tests write inside their isolated data directory.

## Quitting

⌘Q asks for confirmation unless disabled in Settings. Return or a second ⌘Q confirms; Escape cancels. Dock quit, logout and restart do not prompt. Normal quit drains accepted storage work; see [Storage](STORAGE.md).

## Testing

`BrowsingJourneys`, `KeyboardJourneys` and `SidebarJourneys` drive these behaviors against local pages; `SidebarTabsTests` covers tab order and drop targets. See [Testing](TESTING.md) for fixtures and plans, and [Performance](PERFORMANCE.md) for measurements. Physical haptics, device permissions and external service compatibility need manual checks.
