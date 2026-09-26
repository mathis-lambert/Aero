# Site controls

What the browser offers for the site in the selected tab: its address actions, the control center, site data and permissions, ad and tracker blocking, and automatic picture in picture.

## Address actions

On a website, the sidebar's address shows two buttons: Copy link and the control center. Copy link (⇧⌘C) puts the page's address on the pasteboard and shows a checkmark for a moment. Neither shows on the New Tab page or a browser page (`aero://`).

Failure modes:

1. The copied address is stale (the saved tab address before a redirect or `pushState`) or not a web address.
2. The buttons show, or act, on a browser page or the New Tab page.
3. The feedback is visual only, so VoiceOver users get no confirmation.

Verification: E2E `testAddressActionsAndControlCenter` (the pasteboard holds the page's address; no buttons on the New Tab page; 2). The live address is read from the web view (1), and the copy is announced to VoiceOver (3).

## Control center

A popover on the address's control center button:

- **Share**, through the system share menu.
- **Extensions**: the profile's extensions, each running its action or opening its popup, then a way to the Chrome Web Store (`docs/EXTENSIONS.md`).
- **Block ads & trackers** and **Automatic picture in picture** for this site, each showing its current state; clicking switches it for the site.
- **Secure** or **Not secure**: secure when the page and everything it loaded came over HTTPS with a trusted certificate. Clicking opens the system certificate panel for the page's server.
- **…**: the site data actions below; Site settings… shows in the control center.

The popover closes when the selected tab changes.

Failure modes:

1. The control center acts on another tab than the one it opened for.
2. "Secure" is shown for a page with mixed content, or a certificate panel opens for a plain HTTP page.
3. A switch shows the global setting while the site overrides it, or the reverse.
4. Share offers the wrong address.

Verification: E2E `testAddressActionsAndControlCenter` (a plain HTTP page reads Not secure; the … menu and Site settings; 2). 1 holds because the popover closes when the tab changes; 3, because the switches read the same decision pages use. The share menu and the certificate panel are checked by hand.

## Site data and permissions

Right-clicking the reload button, and the control center's … menu, offer Clear cookies, Clear cache and Site settings…; all three are catalog commands, so the command palette has them too. They act on the selected page's site in its profile's data store. WebKit groups data by site (the registrable domain), so clearing `mail.example.com` clears `example.com` and its other subdomains, as Safari does. Clearing cookies or all data reloads the page, so it stops using what was removed.

Site settings, a popover on the reload button or a page of the control center, shows the site's cookie count and whether it stores other data, Delete data, and a decision per permission:

| Permission | Choices | Without a decision |
| --- | --- | --- |
| Camera, microphone, location | Ask, Allow, Block | WebKit's own prompt, every time |
| Ads and trackers | Default, Allow, Block | Settings › General › Block ads and trackers |
| Automatic picture in picture | Default, Allow, Block | Settings › General › Automatic picture in picture |

Decisions belong to the profile, are saved with the session and keyed by the page's origin (`scheme://host[:port]`, lowercased, without the default port). An embedded frame gets the page's decision; WebKit's permissions policy already keeps cross-origin frames out unless the page delegates to them. Reset permissions forgets every decision for the site.

The app declares camera, microphone and location usage, with the hardened runtime entitlements that let macOS ask for them.

Failure modes:

1. Clearing touches another site, or another profile's store.
2. A subdomain keeps the site's cookies, such as a session cookie set on the parent domain.
3. The page keeps using removed cookies until the user reloads it.
4. A decision is keyed on another origin (an embedded frame, a different port or letter case), so it does not apply to the page it was set on.
5. A decision is lost at relaunch.
6. A camera and microphone request is granted while one of the two is blocked, or Ask grants without a prompt.
7. WebKit waits forever for a decision, or a closed tab answers one.
8. macOS refuses the device although the site is allowed (missing usage description or entitlement).
9. The actions run on a browser page (`aero://`) or with no page.

Verification: E2E `testSiteDataClearsAndPermissionsPersist` (Clear cookies and Delete data empty the site's cookies and reload it while `127.0.0.1` keeps its own; decisions survive a relaunch; 1, 3, 5). By construction: 2 (WebKit removes whole site records), 4 (`SiteOrigin` is the only key, from the page's address), 6 and 7 (`BrowserPage`'s delegate), 9 (the commands are disabled without a web page). Using a device is checked by hand: WebKit asks macOS for the app's own authorization before it asks for the site's decision, so the result depends on the machine (6, 8). Clear cache has no observable E2E effect.

## Ad and tracker blocking

Aero blocks with WebKit content rule lists, enforced inside WebKit's networking and style resolution: no JavaScript runs in pages for it. The rules come from [EasyList and EasyPrivacy](https://easylist.to), © The EasyList authors, used under CC BY-SA 3.0; the app credits them in Settings.

`FilterListConverter` (BrowserCore) turns the lists' Adblock Plus syntax into WebKit rules:

- Network rules: `||` domain anchors, `|` anchors, `*` wildcards, `^` separators, `$third-party`, resource types (`script`, `image`, `stylesheet`, `font`, `media`, `xmlhttprequest`, `subdocument`, `ping`, `websocket`, `popup`, `document`, `other`, and their negations), `$domain=` (either only included or only excluded domains), `$match-case`, and `@@` exceptions.
- Element hiding: `##` generic and per domain, `#@#` exceptions, and the `$elemhide`, `$generichide` and `$document` exceptions.
- Skipped: regular expression rules, extended CSS (`#?#`, `:-abp-…`, `:has-text()`…), scriptlets and snippets (`#$#`, `#%#`, `##+js`), `$redirect`, `$rewrite`, `$csp`, `$removeparam`, mixed `$domain=` lists, `example.*` domains, and any option it does not know. Skipping loses a rule; misreading one blocks the wrong thing.

WebKit accepts at most 150,000 rules per list and applies an exception only within its own list, so the converter splits the rules over several lists and repeats in each the exceptions that apply to it. Rules are ordered: network blocks, network exceptions, generic hiding, `$generichide` exceptions, domain hiding, `$elemhide` exceptions, `$document` exceptions.

The app bundles a snapshot of both lists (`Scripts/update-filter-lists.sh` refreshes it), so blocking works from the first launch. `ContentBlocker` (BrowserWebKit) compiles the lists off the main thread into a rule list store under Application Support, named from a hash of the sources and the converter version, so later launches look them up instead of compiling. `FilterListUpdater` (the app) downloads both lists once a day while the app runs, retrying after an hour on failure; a response is kept only if it is a complete Adblock Plus list newer than the one in use and compiles, and `FilterListStore` (BrowserStorage) writes it atomically. Otherwise the previous lists stay in use. Test runs download from the fixture server instead, never from the internet, and bundle nothing.

Each main-frame navigation adds the rule lists to the page, or removes them, from the site's decision, so a site set to Allow is unblocked from its first request. Pages opened before the lists are compiled get them when ready; changing the global setting applies to open pages from their next load; changing a site's switch reloads it.

Failure modes:

1. A misread pattern blocks the wrong thing (anchors, separators, wildcards, escaping, case).
2. An exception does not undo its block because it landed in another list or before the block.
3. A list exceeds WebKit's rule limit, or a rule WebKit rejects fails the whole list, and nothing is blocked.
4. Unsupported syntax is translated into a wrong rule instead of being skipped.
5. An invalid CSS selector hides nothing, or hides nothing else either.
6. Every launch compiles the lists again, or converting blocks the main thread.
7. Pages loaded before compilation finishes are never protected.
8. A site's Allow leaks to another site or profile.
9. A failed, partial or corrupt download replaces working lists; updates run too often, never, or from tests.
10. Generic hiding breaks a site that has a `$generichide` exception.
11. The lists' attribution is missing.

Verification: E2E `testAdsAndTrackersAreBlockedUnlessAllowed` (a fixture list downloaded from the fixture server blocks a third-party image and hides an element but keeps the site's own image; the site's switch reloads it unblocked; 7, 9's test case). Isolated `FilterListConverterTests` cover 1–5, with patterns checked by what they match. Measured on the 26 Sep 2026 lists: 139,551 rules and 693 skipped, converted in 2 s and compiled in 5.5 s in a release build (8 s to convert in a debug build), once per list version (6). Attribution: Settings › General (11).

## Automatic picture in picture

When the selected tab changes and the tab left behind plays a visible, unmuted video, the video moves to the system's picture in picture window; selecting that tab again brings it back inline. It follows the site's decision, then Settings › General. Sites' own picture in picture buttons work too.

macOS WebKit has no public API for picture in picture: it is off in every `WKWebView`. Aero turns on the private preference `allowsPictureInPictureMediaPlayback` Safari uses, only if the running WebKit exposes it, so a WebKit without it only loses picture in picture. The request is a script from the app, which WebKit accepts without a click in the page. A page in picture in picture is never hibernated.

Failure modes:

1. A paused, muted, ended, hidden or audio-only video is moved, or a second video replaces the first.
2. Returning to the tab leaves the video in its window, or the app reopens a window the user closed.
3. Hibernation unloads a page whose video is in picture in picture.
4. A blocked site or the global setting turned off still moves.
5. A WebKit without the private preference crashes the app.

Verification: E2E `testVideoMovesToPictureInPictureWhenLeavingTheTab` (leaving the tab moves the playing video and selecting it again brings it back; with the site switched off it stays inline; 2, 4). `PageScripts.enterPictureInPicture` picks only a visible, unmuted, playing video and never a second one (1); hibernation keeps a page in picture in picture (3); the preference is set only when WebKit answers to it (5).

## Limits

- Popups share their opener's content controller, so a popup on another site takes that site's blocking decision for both pages' next loads.
- Blocking has no cosmetic scriptlets or `$redirect` replacements: sites that detect blockers may notice.
- The share menu and the certificate panel are the system's own.
- Only a video in the page's own document moves automatically, not one in an embedded player's frame.
- Top-level navigation to a blocked domain is blocked too, as WebKit applies a rule without resource types to every load.
