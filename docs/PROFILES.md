# Profiles

A profile owns a browsing identity: its website store, its history and one space of tabs. Failure modes were written before the implementation.

## Sidebar

- The sidebar's tab area (pinned tiles, New Tab and the tab list) is one page per profile, side by side (`ProfilePager`). A horizontal two-finger swipe drags the pages and, released past a quarter of the width, moves to the neighbouring profile; otherwise they spring back. A gesture that starts vertically scrolls the tab list. Only the selected page and its neighbours are built.
- The footer shows the downloads button on the leading side, one icon per profile in the middle, and a button to add a profile on the trailing side. A profile's icon is its emoji, or a dot in its color when it has none; the selected profile's icon is highlighted, and every icon names the profile in its tooltip and accessibility label.
- Clicking a profile's icon slides to its page. The icon's context menu edits the profile.
- Switching profiles, by either means, selects the tab the profile last showed (or its New Tab page) and closes the control bar and the find bar. Pages of other profiles are records only: sliding past them never loads a website.

## Emoji

A profile may have one emoji. The profile prompt and Settings › Profiles take it as text: the field keeps a single emoji, and anything else leaves the profile with its color dot. `BrowserProfile.emoji(from:)` in BrowserCore is the only rule, applied on every edit and when a saved session is validated.

## Failure modes

1. A vertical scroll in the tab list switches profiles, or a swipe stops between two pages.
2. The footer and the pages disagree about the selected profile after a click, a swipe or a profile created from the prompt.
3. Switching back to a profile loses its selected tab, or leaves the previous profile's control bar or find bar open.
4. Sliding past a profile's page loads its websites.
5. The emoji field accepts words, digits, several emoji, whitespace or a lone modifier; a sequence emoji (flag, family, skin tone, keycap) is rejected or split.
6. A saved session with an invalid emoji loads, or a valid one fails validation.
7. A profile without an emoji shows nothing, or profiles are told apart by color alone.
8. With one profile, the footer or the pages behave differently than with several.

Verification: E2E `ProfilesE2ETests` creates a profile with an emoji, switches with the footer and checks tabs, selection and relaunch (2–3, 7–8). UI tests cannot drive the swipe (1, 4): `XCUIElement.scroll` and events posted by the test runner never reach the app, so it is checked by hand on a trackpad. Isolated `BrowserSessionTests` cover the emoji rule and its validation (5–6), which typing in the UI cannot vary exhaustively.

## Downloads

Downloads live in a popover from the footer's downloads button, not in the sidebar. The button shows the progress of active downloads as a ring; the popover lists the session's downloads with progress, cancel, retry, Show in Finder and Clear, or says there are none.

Failure modes:

9. The ring or the list redraws the sidebar for every packet.
10. Clearing removes an active download.
11. The popover shows a stale list, or cannot be reopened after it closes.

When a download starts, its file icon is thrown from the pointer (or the page's center when the pointer is elsewhere) in an arc into the downloads button, shrinking on the way, in about 0.6 s, and the button takes the hit: a small kick, then a damped wobble on its base. Nothing flies with Reduce Motion or while the sidebar is hidden; the flight never takes clicks.

12. A retry, a clear, a relaunch or a progress update throws a file again.
13. The file flies to the wrong place after the window is resized, or while the sidebar is hidden.
14. The flight runs with Reduce Motion, blocks clicks, or stays on screen.

Verification: E2E `testDownloadCompletesAndCanBeCleared` opens the popover, waits for the download and clears it (10–11). The ring updates in whole percents (9, `BrowserDownload.progressStep`). The flight is triggered only by `DownloadCoordinator.lastStarted`, which a new download sets (12), and is checked from the test's screen recording (13–14).

## Hover

Every borderless button of the chrome takes the `hover` fill under the pointer and the `pressed` fill while pressed, through `QuietButtonStyle`. Disabled buttons show no hover. Hover only changes on pointer events, so nothing animates while idle. Verified from the attached screenshots.
