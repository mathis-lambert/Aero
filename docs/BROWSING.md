# Browsing

## Control bar

The same address, search and command field appears on New Tab and over a page. ⌘L replaces the current page; ⌘K opens results in a new tab. On New Tab, both focus its existing field.

Results are ordered: address/search, engine suggestions, current-space tabs, profile history, commands. Return opens the selected result; Escape dismisses the overlay or clears New Tab. Commands use the same dispatcher as menus and shortcuts; see [Shortcuts](SHORTCUTS.md).

Suggestions use an ephemeral session without profile cookies or credentials. Address-like input is never sent. Requests are delayed until typing pauses and canceled when the query changes. Local history publishes independently of network responses.

## New Tab

While its field is empty, New Tab shows up to six frequent sites and the last three tabs closed in its space, under the bar. The page opens with a gust rising from below its center, quick at first then slowing: the dots of the crescent pop in and are lit for a moment as its ragged front reaches them, and the bar lights up as it arrives. The shelf rises in at that moment and steps aside as soon as you type; each keystroke sends a ring from the caret that pushes the dots aside and swells them as it passes. The page reads them once as it appears; nothing polls while it stays open.

- Sites come from the profile's last 28 days of history, grouped by host without `www.`. A visit weighs less with age (a week's half-life), more when the address was typed, more near this time of day and on the same kind of day, weekday or weekend. Reloads and one-off visits do not count; the space's favorites are left out, being in the sidebar already. A site opens its dominant page, or its home page when no page dominates; one already open in the space is switched to. The rules are `FrequentSites` in BrowserCore.
- Hide from New Tab, in a site's context menu, is kept per profile in the preferences and forgotten with the profile.
- Down moves from the field to the sites, then to the closed tabs; Left and Right move within a row in the reading direction, Up goes back, Return opens and Escape returns to the field. The field keeps the keyboard focus throughout, so typing simply starts a search; keys during input-method composition stay with the field.

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

Popups use WebKit's supplied configuration, preserving `window.opener`, messaging and OAuth. A `window.open` that asks for a size opens in a window of its own, as in Safari, sized as asked within the visible screen and centered over the browser: it shows the site and its connection, asks its dialogs over itself, records no history, and ends with `window.close()`, its window, or its profile. Its downloads, links for other apps, site permissions and further popups belong to the opener's tab; Aero's password filling does not reach it. Other popups open as tabs in the opener's space. Only script-opened tabs may close themselves. Loaded popup relationships prevent hibernation. A popup or link for another scheme is handled as in [Other apps](OTHER_APPS.md) › Links to other apps.

## Page dialogs

A page's `alert`, `confirm` and `prompt` ask in the window with the shared prompt, titled with the site of the frame that asks, never a name the page gives. A background tab's dialog waits until the tab is shown and no other question is; leaving or closing the tab dismisses it, and a dismissed `confirm` or `prompt` answers as cancelled. From a page's second dialog on, the person can stop its dialogs until it loads another document. Messages are cut at 2,048 characters. A file input opens the system's open panel as a sheet, for files or folders and one or several as the input asks. `PageDialogTests` covers dialogs on WebKit (a page blocked in a dialog cannot be read by accessibility, so no journey shows the prompt); `BrowsingJourneys` the open panel.

## Files

File › Open File… (⌘O), Open With in the Finder, or another app opens web pages, web archives, images, PDFs and text of this Mac in a new tab. A file reads only its own folder; a website never navigates to a file. Files leave no history. File › Save As… (⇧⌘S) saves the page as a web archive, and Export as PDF… the whole page as a PDF.

## Developer mode

Settings › General › Developer mode makes every page, extension background, popup, window and offscreen document inspectable: Inspect Element in the context menu opens Web Inspector, where extensions add their developer tools panels (`devtools_page`). It is off by default, except in development builds, and applies at once to open pages.

## Find and downloads

Find searches the selected page with wrapping, case-insensitive matching. Escape restores page focus; switching tabs closes it. Results report presence, not a count. Page-first shortcuts let web editors handle their own find.

Downloads use sanitized unique filenames in Downloads, with quarantine and source metadata; Finder and the Dock show their progress on the file, as for Safari's. Closing a tab does not cancel them. The downloads popover supports cancel, retry, Show in Finder and clearing inactive entries. The list lasts only for the session; tests write inside their isolated data directory.

## Quitting

⌘Q asks for confirmation unless disabled in Settings. Return or a second ⌘Q confirms; Escape cancels. Dock quit, logout and restart do not prompt. Normal quit drains accepted storage work; see [Storage](STORAGE.md).

## Testing

`BrowsingJourneys`, `KeyboardJourneys` and `SidebarJourneys` drive these behaviors against local pages; `SidebarTabsTests` covers tab order and drop targets. See [Testing](TESTING.md) for fixtures and plans, and [Performance](PERFORMANCE.md) for measurements. Physical haptics, device permissions and external service compatibility need manual checks.
