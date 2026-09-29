# Onboarding and import

The first launch introduces Aero, brings favorites, history and passwords over from another browser, shows a few shortcuts, and ends on a clean New Tab page. Nothing else is asked: spaces and profiles come from the import, and are edited later in Settings. Open tabs are never imported: the person starts fresh, with everything they kept.

## When it appears

Only on a fresh store: the first launch of a channel, before any browsing record exists. Its progress is a versioned preference (`browser.onboarding`: format version, current step, completed), so a relaunch, such as the one macOS requires after granting Full Disk Access, resumes on the same step. Completing or skipping records completion; the onboarding never shows again for that store. People who already use Aero import with **Import from Another Browser…** (File menu and command bar), which runs the same source, choice and import steps over the browser, without resizing the window or saving progress.

## Presentation

The onboarding covers the main window's content, like storage recovery, and never opens a second window. While it shows, the window is compact (1040 × 660 points, centered, not resizable); when it ends, the window grows back to its previous frame, or a generous browser size on a first launch. A plate on the leading side carries the words; the trailing stage shows what each step does. Titles use Gilda Display, bundled with the app under the SIL Open Font License; everything else is the browser's own: system type, `BrowserPalette` colors, `PanelButtonStyle`, `FormSection`, switches and `Keycaps`.

Behind the stage, a dot grid of wind (`OnboardingWind.metal`) writes one shape per step: the feather of the alternate app icon (`BrandFeather`), the source browser's name, that name becoming "Aero" during the import, the shortcut just pressed, rings around the app icon, the New Tab crescent. Dots only grow and shrink in their cells: a new shape arrives from upwind behind a frayed front while the old one is carried downwind. Nothing is drawn over the grid. The wind drifts at 30 frames per second while the person interacts and settles 20 seconds after the last input; gusts, morphs and ripples run at the display cadence. It holds still while the window is inactive, in Low Power Mode and with Reduce Motion (shapes then appear without motion); it is removed with Reduce Transparency or Increase Contrast. At the end the onboarding fades over the real browser, whose New Tab wind rises as usual.

Each step fits on one plate at French length. The plate's footer is the same on every step: the Aero wordmark, then Back as a chevron, and the one blue action at the bottom trailing corner, which Return presses (Get started, Continue, Set as default, Start browsing); the default browser step adds Not now beside it. Leaving the onboarding is a quiet Skip setup link (Cancel for an import alone) across from the progress bar, never a button beside the step's answer. The wordmark keeps its size; a translation too long for both gives the actions the row. Command-Left Bracket goes back; every control has a localized accessibility label and the import result is announced.

The stage places each picture in the room its wind shape leaves (`OnboardingLayout.stageRegion`) and scales it down to fit (`StageFit`), so it holds at any window size. From the import to the end it shows the browser itself in miniature (`OnboardingBrowserTwin`): the main window at the chrome's own sizes, drawn from the browser's records (the selected space, its favorites with their icons, groups, the spaces in the footer) over the space's New Tab wind, with the control bar, the hidden sidebar and the recent-tab switcher as the person tries them. It is one view across those steps, so it changes instead of reloading.

## Steps

1. **Welcome.** "Light as air.", how long setup takes, and the three things ahead: bringing things over (with the icons of the browsers found), the essential shortcuts, the default browser. The dots gather into the feather.
2. **Source.** Installed browsers found on this Mac, with what each holds, or Start fresh. A file of bookmarks is not offered.
3. **What comes along.** A switch for each kind the browser gives: favorites (spaces and favorites for Arc), history, and passwords except for Safari. For Dia, a line says its spaces and favorites stay in Dia instead of a favorites switch. The stage shows how source spaces become Aero spaces and the profile each uses.
4. **Import.** Progress per kind, then the result. Passwords follow `PASSWORDS.md` › Import and export.
5. **Getting around.** A two-finger swipe (or Control-Command-Right and Left) switches spaces; Command-K opens the control bar, Command-S the sidebar, Control-Tab the last tab. Each can be tried in a preview.
6. **Default browser.** Make Aero the default through `NSWorkspace.setDefaultApplication`, which shows macOS's own confirmation, or Not now.
7. **Ready.** Start browsing.

Start fresh goes from the source step straight to Getting around.

## Import

### Sources

`BrowserStorage/Import` holds one reader per format, composed per browser. Every Chromium browser is described once in `ChromiumBrowser.all` (folder, keychain item, bundle identifier, and where its favorites come from); its profiles, with the names and highlight colors of `Local State`, share the Chromium readers for history (`ChromiumHistory`), icons (`ChromiumFavicons`) and passwords (`ChromiumLogins`). Favorites come from `Bookmarks` (`ChromiumImport`), from Arc's sidebar (`ArcImport`), or nowhere for Dia. Safari has its own adapter (`SafariImport`). Detection only lists folders and reads no browsing data. Safari is listed when its folder exists; reading it requires Full Disk Access.

| Source | Spaces | Favorites | History | Passwords |
| --- | --- | --- | --- | --- |
| Arc | `StorableSidebar.json`: each space with its Arc profile, color and emoji | Pinned tabs, first-level pinned folders as groups, and the profile's favorites as tiles in each of its spaces | Profile's `History` | Profile's `Login Data` |
| Chrome, Brave, Edge, Vivaldi | One space per profile, in its highlight color | The bookmarks bar; its first-level folders, the other bookmarks and the mobile bookmarks as groups | Profile's `History` | Profile's `Login Data` |
| Dia | One space per profile (each group of spaces that share data), in its highlight color | None: encrypted, said in the choice step | Profile's `History` | Profile's `Login Data` |
| Safari | One space | Favorites bar; its first-level folders, the Bookmarks menu and other top-level folders as groups | `History.db` | Not offered: they live in the Passwords app; CSV import remains (`PASSWORDS.md`) |

Arc's unpinned tabs, Chromium's sessions and Safari's last session are not read. Dia keeps its spaces, favorites and pinned tabs in SQLCipher databases (`tabs.db`) with a key it derives itself; turning its Sync off does not decrypt them. They are never opened, and the few links left in Dia's `Bookmarks` file, which Dia does not show, are not taken for favorites.

Favorites arrive with the icon their Chromium profile has for that page, or else for another page of its site, scaled like a fetched icon. Arc keeps most sidebar icons in a private cache, and Safari's icon cache is private: those, and any other favorite without an icon, are fetched from the site once when the favorite is shown, like the icons of saved passwords.

### Mapping

- Each source profile becomes an Aero profile. Spaces keep the source's order, whatever their profile, and are created even when favorites are left behind or unreadable. The fresh store's default profile and space are reused for the first profile and space instead of staying empty.
- Arc spaces keep their title, their emoji and their theme's midtone as a custom color. Chromium spaces take the profile's name and highlight color; without one, and for Safari, the color presets in order.
- Each first-level folder becomes a collapsed group of favorites; the links of its subfolders are gathered in it, in their order, so no link is lost and groups never nest. Two folders with the same name stay two groups. Favorites keep their title as name.
- Only `http` and `https` addresses are kept; others are counted as skipped. The same address appears once per space.
- History keeps the last 365 days (`HistoryStore.retention`), at most 100,000 pages per profile, the most recent first, with each page's title, last visit and up to its 20 latest visits.

### Writing

Readers live in BrowserStorage, take the source root as a parameter and run off the main actor on copies of databases, since a running browser locks them. The app builds the resulting profiles, spaces, groups and favorites and applies them to the session in one mutation, persisted as one transaction. History is written in batches through one `HistoryStore` transaction per batch, and passwords through `importPasswords(from:into:)`. Each kind reports added, already present and skipped counts, or its failure, without stopping the others.

Importing again is safe: favorites are matched by address within their space, history pages merge by profile and address, and passwords never replace a different saved one. Cancelling (Back, Skip, quitting) stops the readers; model changes are applied only when reading finished, and a result that arrives after cancellation or after its destination profile was deleted is discarded. Imported website data (cookies, sign-ins) never crosses: sites ask to sign in again, which the Import step says.

### Full Disk Access

Selecting Safari without access shows why and opens System Settings › Privacy & Security › Full Disk Access. macOS applies the permission after relaunch; the onboarding resumes on the source step and checks access again by opening `Bookmarks.plist`. Continue stays unavailable for Safari until then.

## Test runs

With `AERO_TEST_DATA`, sources are read only from the folder in `AERO_TEST_IMPORT_SOURCES` (the repository's `Tests/AeroUITests/Fixtures/import-sources`), laid out like `~/Library/Application Support` and `~/Library/Safari`, and never from the real ones; without it, no source is found. The onboarding itself shows in UI tests only with `AERO_TEST_ONBOARDING=1`, so other tests start on the browser. Fixture visits are dated 2030 so they stay inside the import window. Fixture addresses use the reserved `.test` domain, so fetching a favorite's missing icon never reaches a real site. Passwords of fixture browsers are not decrypted in UI tests (their key would live in the real keychain); isolated tests cover decryption.

## Failure modes and acceptance scenarios

1. The onboarding shows on a store with existing records, or again after completion or skipping; a relaunch mid-onboarding restarts from the beginning or loses choices.
2. Importing twice duplicates favorites, groups or history pages, or replaces a saved password.
3. A running source browser (locked database) fails the whole import, or a corrupt `StorableSidebar.json`, `Bookmarks`, `History` or `Bookmarks.plist` crashes, hangs, or silently imports nothing without a message.
4. An import writes into the wrong profile, reorders the source's spaces, or leaves an empty default profile or space next to imported ones.
5. A partial model import: some spaces or favorites saved and others not after a failure or cancellation; a late result after cancellation or profile deletion recreates records.
6. Non-web addresses (`chrome://`, `javascript:`, `file:`) become favorites; an unbounded history or bookmark tree (10,000 items, deep nesting) blocks the main actor or exceeds the stated limits.
7. Safari reads as "no data" instead of asking for Full Disk Access, or Continue proceeds without access; the relaunch loses the step.
8. Declining the keychain prompt or a locked keychain reads as zero passwords, or stops favorites and history.
9. Open tabs are imported from any source.
10. The window's frame is restored inside SwiftUI's update, re-entering it and crashing when the onboarding ends.
11. The wind runs while the window is inactive, after it settles, in Low Power Mode or with Reduce Motion; text overlaps the dots; a shape is drawn over the grid instead of in it.
12. A test run reads real browser folders, the real keychain or real Safari data.
13. French text overflows the plate, or dark appearance leaves unreadable text; a control lacks an accessibility label; Return triggers the wrong action.
14. Setting the default browser reports success when macOS's confirmation was declined.
15. A subfolder's links are lost, subfolders become groups of their own, or all folders collapse into one; the leftovers of an encrypted browser's `Bookmarks` are imported as its favorites; an imported favorite keeps a letter when its source had its icon.

## Verification

`WindMotionTests` checks that gusts, morphs and ripples release the display cadence as their frames settle,
and that Reduce Motion completes a shape immediately. The timeline observes this frame state; it pauses once
the interaction rest delay has elapsed and no effect is active.

Isolated Swift tests cover the source formats with fixtures: Arc sidebar variants (default and custom profiles, emoji, first-level and nested folders, favorites, non-tab items), Chromium bookmarks, history and icons (nested folders, non-web addresses, empty and corrupt files, time conversions, limits, icon sizes), Dia's unreadable favorites, and Safari bookmarks and history (3, 6, 15), which UI tests cannot vary exhaustively. `OnboardingJourneys` runs the onboarding on fixture sources in `AERO_TEST_DATA`: an Arc import from the keyboard with Back, a relaunch mid-onboarding, the shortcuts tried in place and completion across relaunch; a Chrome import in French and dark appearance with first-level folders as groups, Chrome's icons and Skip; and a second import from the File menu without duplicates (1, 2, 4, 9, 10, 12, 13, 15). Dia's and Safari's imports are covered by the isolated tests only. Safari without access, Reduce Motion, the wind's frame cadence and GPU time (Instruments: idle, interaction, morph) are still checked by hand (7, 11). Keychain prompts and the default browser confirmation are checked by hand on a signed build (8, 14).
