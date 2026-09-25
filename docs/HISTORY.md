# History

The failure modes below were written before the implementation.

## Behavior

- A visit is recorded when a page commits a new document or changes its address in place (`pushState`), unless the address equals the page's previous one: reloads, redirects before commit and hibernation restores add nothing. Selecting a tab restored after a relaunch loads it, which counts as a visit.
- Titles arrive after the visit and update the entry.
- History belongs to a profile. Every query is scoped to one profile.
- History is a browser page shown in a tab (`aero://history`), like Chromium's history page. ⌘Y selects the space's History tab, or opens one. The page lists pages by their most recent visit, grouped by day, newest first. Search matches words in titles and addresses, ignoring case and diacritics ("ete" finds "Été"), with prefix matching. Return or double-click opens the entry in the same tab; the context menu opens it in a new tab; Delete removes it. Clear History removes the last hour, today, today and yesterday, or everything, for the current profile.
- Visits older than a year are pruned when the store opens.

## Storage

`HistoryStore` (BrowserStorage) is an actor over the system SQLite library, with no external dependency. Pages are unique per profile and address; visits reference pages; an FTS5 index over titles and addresses is kept in sync by triggers. The database uses WAL journaling, writes in transactions, and records its schema in `user_version`.

The store opens lazily on first use, so launching the browser never waits for it. If the file cannot be opened or has a newer schema, it is left untouched and history is unavailable for the session; the History page says so.

## Failure modes

1. User search text contains FTS syntax (`"`, `*`, `-`, `NEAR`, `OR`, parentheses) and produces a query error or unintended matches.
2. A page's history appears in another profile, or clearing one profile clears another.
3. Clearing a time range removes pages that also have older visits, or leaves pages with no remaining visit.
4. A corrupt or future-version database is overwritten or deleted.
5. Reopening an existing database re-runs the schema or loses data.
6. Very long titles or addresses bloat the database.
7. Old visits accumulate forever.
8. Recording or searching blocks the main actor, or the database opens during launch.
9. A late title update creates an entry that was just cleared.

## Internal pages

Browser pages use the `aero` scheme and are drawn natively in the page surface: no `WKWebView` and no web process is created for them. They are ordinary tab records, so they are restored after a relaunch, reordered, pinned and closed like other tabs. Typing `aero://history` in the address field opens the page.

Failure modes:

10. A website navigates to, links to or opens an `aero://` page.
11. An internal tab creates a web view or a web process, or is hibernated.
12. Web page commands (reload, back, forward, find) act while an internal page is shown.
13. ⌘Y opens a second History tab in the same space.
14. Turning a web tab into an internal page leaves its web page loaded, or the reverse leaves stale page state.

Verification: E2E `HistoryE2ETests` records visits from fixtures, searches, opens, deletes, clears and checks persistence across relaunch. Isolated `HistoryStoreTests` cover 1–7 and 9, which the UI cannot drive precisely (arbitrary search syntax, several profiles, backdated visits, damaged files). Failure mode 10 is blocked by the navigation policy, which only allows web, `about` and `blob` URLs in pages.
