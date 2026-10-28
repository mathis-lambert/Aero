# Browsing

## Control bar

The same address, search and command field appears on New Tab and over a page. ⌘L replaces the current page; ⌘K opens results in a new tab. On New Tab, both focus its existing field.

Results of every kind mix by one score (`ResultRanking` in BrowserCore, `ControlBarResults` in the app). An address typed in full comes first; otherwise the search row sits among the results, at a fixed score:

- Every word typed must start a word of a result's title, alias or address (host without `www.`, then path), in any order and with words between them: “capture portrait” finds Capture in Portrait Mode. Case, accents and width are ignored. A whole word counts more than its start; a title or host that starts with the whole query more again. A word of three letters or more found inside a word still matches, under the search row.
- An open tab of the space gains a little; the tab shown is not offered. A visited page gains with its visits, reloads left out, and a little with how recent the last one is; pages open in the space leave the history. The history offers its most visited matching pages, however old.
- Engine suggestions are weighed so they always stay under the search row, the closest to the query first.
- Each kind keeps to its share: three tabs, four commands, four visited pages, four suggestions. Equal scores keep this order: tabs, commands, history, the search row, suggestions.

The first row is selected until the arrows or the pointer choose another; results arriving later never move a chosen row. Return opens the selected result; Escape dismisses the overlay or clears New Tab. Commands use the same dispatcher as menus and shortcuts; see [Shortcuts](SHORTCUTS.md). Settings › Shortcuts filters commands with the same matching.

Suggestions use an ephemeral session without profile cookies or credentials. Address-like input is never sent. Requests are delayed until typing pauses and canceled when the query changes. Local history answers at once, without waiting for the pause or the engine; until new results arrive, the previous ones are ranked against the new text.

## New Tab

While its field is empty, New Tab shows up to six frequent sites and the last three tabs closed in its space, under the bar. The page opens with a gust rising from below its center, quick at first then slowing: the dots of the crescent pop in and are lit for a moment as its ragged front reaches them, and the bar lights up as it arrives. The shelf rises in at that moment and steps aside as soon as you type; each keystroke sends a ring from the caret that pushes the dots aside and swells them as it passes. The page reads them once as it appears; nothing polls while it stays open. In a narrow page or pane, sites and closed tabs wrap to further rows, each centered, rather than widen it.

- Sites come from the profile's last 28 days of history, grouped by host without `www.`. A visit weighs less with age (a week's half-life), more when the address was typed, more near this time of day and on the same kind of day, weekday or weekend. Reloads and one-off visits do not count; the space's favorites are left out, being in the sidebar already. A site opens its dominant page, or its home page when no page dominates; one already open in the space is switched to. The rules are `FrequentSites` in BrowserCore.
- Hide from New Tab, in a site's context menu, is kept per profile in the preferences and forgotten with the profile.
- Down moves from the field to the sites, then to the closed tabs; Left and Right move within a row in the reading direction, Up goes back, Return opens and Escape returns to the field. The field keeps the keyboard focus throughout, so typing simply starts a search; keys during input-method composition stay with the field.

## Favorites and open tabs

Each space has a favorites grid, a pinned list of favorites and groups in any order, and ordinary tabs. New Tab is a permanent selectable row.

- Closing a favorite releases its page but retains its record, back on its pinned page. A favorite's pane in a split closes as a view of the split does: it is removed, and Reopen Closed Tab restores it; Close Split View only releases the panes. Favorites start closed after relaunch. Removing an open favorite turns it into an ordinary tab; removing a closed favorite deletes it.
- Closing an ordinary tab removes it; Reopen Closed Tab restores it.
- Dragging reorganizes tabs. The insertion marker is the committed destination; canceling leaves the order unchanged. External drags export URLs; incoming files and text are rejected. A drag can take tabs to another space: see Several tabs at once.
- Move to Space preserves a live page within the same profile. Crossing profiles requires confirmation and a new page identity; see [Spaces](SPACES.md).
- A group's folder opens with it: its front flap's top edge drops and widens as the group opens, then closes back over it (`FolderIcon`); under the pointer a closed folder opens a little, and a dragged tab about to go in lifts it. Reduce Motion changes it without moving. Change Icon… in a group's menu gives it a symbol instead, chosen among forty in a few families (`FolderSymbols`), filled while the group is open; the folder itself comes first in the choices.
- Resting the pointer on a closed group's header for 0.6 s lists its tabs beside it (`folderPreview`), with the sidebar's own rows and without the group's name, on its trailing side, or its leading side without room, never off screen. A click opens a tab; a row's button closes it, or takes it out of the favorites, and the rows close up as in the sidebar. The list stays while the pointer goes from the header to it and ends a moment after it leaves both, once its last tab is gone, when Aero is no longer active, or at a click elsewhere, a key or a scroll. A click on the header, a right click included, keeps it away until the pointer leaves the header. It grows a little out of the header as it comes and shrinks back toward it as it goes, only fading with Reduce Motion. It is a panel that never takes the keyboard from the page; it does not show during a drag or for an empty group.
- Ungroup leaves the group's favorites pinned where it was. Custom names persist independently of website titles.
- A group's place among the loose favorites is its slot, the number of loose favorites above it (`BrowserSession.pinned(in:)`); closing, unpinning or moving away a favorite above it never moves it past another entry.

## Pinned pages

A favorite keeps the page it was pinned on (`BrowserTab.pinnedURL`), set as it becomes a favorite, kept as it moves, changes space or profile, and dropped when it goes back to the open tabs. Browsing in it never replaces that page. A browser page is one page whatever its query: a terminal's folder never takes it away. A pinned address that redirects stays away from its page; replace it with the current one.

- Away from its pinned page, ignoring the fragment and a path's trailing slash, a favorite shows the title of the page it is on and, quietly in the sidebar's secondary ink, offers to go back: a return arrow on a faint circle at the end of its row or a split's segment, or a small return badge on its tile's corner, brightening under the pointer. Its tooltip names the pinned page: its name, or its site.
- Those, or a double click on the row, the tile or the segment, go back to the pinned page, as does closing the favorite. A loaded page goes there whether shown or not.
- **Edit Pinned Page** in its menu: Replace Pinned URL with Current, and Edit…, which edits the address in place of the row's title, or in a popover for a tile, read as the address field reads one.

## Several tabs at once

⌘-click picks a tab or a group's header in the sidebar without showing or opening it, along with the tab shown; ⌘-click again drops it. ⇧-click picks everything on screen from the last item ⌘-clicked, else the shown tab, to the one clicked, groups' headers included; a closed group's rows are not on screen. Picked tabs and groups look selected. Showing another tab, changing space, Escape or an action on them ends the selection. It belongs to the window and is never saved. `TabSelection` holds the rules, `SidebarTabs.entries(of:)` the order of picked groups and tabs.

- **Context menu**: on a picked tab it acts on all of them, in sidebar order: Copy Links · Duplicate *n* Tabs · Add to Favorites, Pin Tabs · New Group with *n* Tabs, Move to Group ›, Move to Space › · Close *n* Tabs. On a tab outside the selection it acts on that tab alone, as before.
- **With groups picked**, a picked group's or tab's context menu offers Copy Links · Collapse or Expand Groups, Move to Space › · Ungroup, for all of them; a picked group's tabs go with it. Dragged, they all land together, in order, in the pinned list, tabs from the grid or the open tabs included.
- **Tabs menu and shortcuts**: Duplicate Tab, New Group with Tab, Move to Group, Move to Space and Close Tab act on the selection when it includes the shown tab.
- **Dragging** a picked tab takes the others along: they land together, in order, and the page shows the gap they will fill. The drag image counts them.
- **Groups** drag by their header. The group shows as a gap where it would land, its tabs with it; it moves before the first entry of the pinned list, group or loose favorite, whose middle is below the pointer, else last. A tab lands before or after a group as it does a tab: a header's top quarter drops before its group, a closed group's bottom quarter after it, the rest into it. Resting a dragged tab on a closed group for half a second opens it, so the tab can go between its rows; until then the tab keeps its place, as a gap, and the group lights up, so the rows never close up under the pointer. A group a drag opened closes again when the drag ends without tabs landing in it. A group's context menu has Move to Space › too.
- **Another space**: resting a drag on a side of the page for half a second lights that side in the next space's color, then slides to that space, where the tabs drop at a place of its page. Released before the pointer moves again, they go to the end of their kind of place in the space now shown. Resting on a space's icon in the footer opens it the same way; dropping on the icon moves them there directly. A group goes with its tabs, in their order, before the group under the pointer or last. Within a profile, tabs keep their identity and live page; across profiles one confirmation covers them all, as for Move to Space. A tab still downloading keeps every tab where it is. A tab that was shown when the drag began is shown again in its new space.

## History

History (`aero://history`, ⌘Y) is a native tab, reused within its space. Internal pages create no WebKit page and cannot be opened by websites. Web navigation commands are unavailable on them.

Visits are recorded on document commits and address changes, excluding reloads and hibernation restores. Relaunching and loading a restored URL counts as a visit. Titles update existing entries. Search matches title/address words and prefixes without case or diacritics. Clear and delete apply only to the current profile. Storage, retry and retention rules are in [Storage](STORAGE.md).

## Favicons

Icons are fetched anonymously, downsampled off the main actor and cached by profile and host. Restored tabs can show cached icons without loading their pages. Memory retains at most 256 icons and their derived selection colors. SVG is unsupported; App Transport Security blocks nonlocal plain-HTTP icon requests.

## Peek

A force click on a link previews it over its page, without leaving the page: the page's frame shrinks back in the window and what the page shows blurs and dims, the frame itself staying sharp, and a card grows out of the link with the linked page. The card is a live page in the tab's profile: it scrolls, plays and takes the keyboard. Beside it, glass buttons close it or open it in a tab. Open Link in Peek in a link's context menu does the same with a mouse or a trackpad without Force Touch.

- Pressing a link past halfway to a force click starts loading it and reveals the card as far as the pressure goes, the page receding with it; the force click lets it spring open, and releasing before it returns the card into its link and discards its page. A press ends at its release, or as it starts dragging the link; the page's late answer about a press already released opens nothing, and Escape or a click on the page behind ends a preview still following a press. The pressure is window state apart from the preview, so its updates redraw the preview alone.
- The card's page is laid out once, at the page's own size, and shown scaled down: opening, closing, pinching and growing into a tab only move and scale it, so neither page lays out again during the motion (`PeekPresentation`).
- Escape, a click on the page behind, the close button, or pinching in shrinks the card back into its link and ends its page. Showing another tab, space or profile ends it at once.
- Open Peek in Tab (Command-O while a link is previewed; Open File keeps Command-O otherwise), the button, or spreading two fingers grows the card over the whole page with a bounce; its page becomes a tab after its opener, shown at once, as it is: nothing reloads, and the document shown is recorded in history. The pinch moves the card with the fingers and commits as soon as it goes far enough, or when let go quickly, with a tick of the trackpad; a pinch let go short of that is drawn back as by a magnet. Its motion uses springs of Apple's kind (`PeekMotion`): quick to answer, settling without a wobble, with a touch of overshoot where the card lands.
- WebKit's own link preview is off in every page, so it never opens beside Aero's. On a link, the click that ends the force click never reaches the page, which would follow the link. Anywhere else, Force Touch keeps WebKit's own behavior, such as Look Up. The page's view reads the trackpad's pressure (`pressureChange`), and a script in Aero's isolated world finds the link under the pointer, through open shadow roots; the address must be a website's, its frame is the page's own measure.
- The preview's downloads, links for other apps, site permissions, dialogs and popups belong to its tab. It records no history and previews no further links until it becomes a tab. One preview at a time; opening another ends the first.
- With Reduce Motion it appears and goes without moving. The context menu item relies on the identifier WebKit gives Open Link in New Window, which the SDK does not export; should it change, the item is not offered.

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

Downloads use sanitized unique filenames in Downloads, with quarantine and source metadata; Finder and the Dock show their progress on the file, as for Safari's. Closing a tab does not cancel them. The downloads button's circle fills as a pie with the bytes received of the downloads under way, grey while they are all paused. The popover gives each download's speed over its last seconds and the time left at that speed (`TransferRate`), and pauses, resumes, cancels and retries it: a pause keeps WebKit's resume data, so the download continues where it stopped when the server allows, and starts over otherwise. A finished file opens with a double click, drags out as the file itself, and its menu shows it in the Finder, renames it in place with its stem selected, as in the Finder (a name already taken is refused, never replaced), copies its address, or moves it to the Trash, never deleting it. Removing a download from the list, or clearing the inactive ones, leaves its file. The list lasts only for the session; tests write inside their isolated data directory.

## Quitting

⌘Q asks for confirmation unless disabled in Settings. Return or a second ⌘Q confirms; Escape cancels. Dock quit, logout and restart do not prompt. Normal quit drains accepted storage work; see [Storage](STORAGE.md).

## Testing

`BrowsingJourneys`, `KeyboardJourneys` and `SidebarJourneys` drive these behaviors against local pages; `SidebarTabsTests` covers tab order and drop targets. See [Testing](TESTING.md) for fixtures and plans, and [Performance](PERFORMANCE.md) for measurements. Physical haptics, device permissions and external service compatibility need manual checks.
