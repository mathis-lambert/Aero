# Site controls

What the browser offers for the site in the selected tab: its address actions, the control center, site data and permissions, ad and tracker blocking, automatic picture in picture, and whether it is offered to save passwords.

## Address actions

On a website, the sidebar's address shows two buttons: Copy link and the control center. Copy link (⇧⌘C) puts the page's address on the pasteboard and shows a checkmark for a moment. Neither shows on the New Tab page or a browser page (`aero://`).

## Control center

A popover on the address's control center button:

- **Share**, through the system share menu, and beside it **Capture in Portrait Mode** ([Portrait mode](PORTRAIT.md)).
- **Extensions**: the profile's extensions, each running its action or opening its popup, then a way to the Chrome Web Store ([Extensions](EXTENSIONS.md)).
- **Block ads & trackers** and **Automatic picture in picture** for this site, each showing its current state; clicking switches it for the site.
- **Secure** or **Not secure**: secure when the page and everything it loaded came over HTTPS with a trusted certificate. Clicking opens the system certificate panel for the page's server.
- **…**: the site data actions below; Site settings… shows in the control center.

The popover closes when the selected tab changes.

## Site data and permissions

Right-clicking the reload button, and the control center's … menu, offer Clear cookies, Clear cache and Site settings…; all three are catalog commands, so the command palette has them too. They act on the selected page's site in its profile's data store. WebKit groups data by site (the registrable domain), so clearing `mail.example.com` clears `example.com` and its other subdomains, as Safari does. Clearing cookies or all data reloads the page, so it stops using what was removed.

Site settings, a popover on the reload button or a page of the control center, shows the site's cookie count and whether it stores other data, Delete data, and a decision per permission:

| Permission | Choices | Without a decision |
| --- | --- | --- |
| Camera, microphone, location | Ask, Allow, Block | WebKit's own prompt, every time |
| Ads and trackers | Default, Allow, Block | Settings › General › Block ads and trackers |
| Automatic picture in picture | Default, Allow, Block | Settings › General › Automatic picture in picture |
| Save passwords | Default, Allow, Block | Settings › Passwords › Offer to save passwords; Never for this site sets Block ([Passwords](PASSWORDS.md)) |

Decisions belong to the profile, are saved with the session and keyed by the page's origin (`scheme://host[:port]`, lowercased, without the default port). An embedded frame gets the page's decision; WebKit's permissions policy already keeps cross-origin frames out unless the page delegates to them. Reset permissions forgets every decision for the site.

The app declares camera, microphone and location usage, with the hardened runtime entitlements that let macOS ask for them.

## Ad and tracker blocking

Aero blocks with WebKit content rule lists, enforced inside WebKit's networking and style resolution: no JavaScript runs in pages for it. The rules come from [EasyList and EasyPrivacy](https://easylist.to), © The EasyList authors, used under CC BY-SA 3.0; the app credits them in Settings.

`FilterListConverter` (BrowserCore) turns the lists' Adblock Plus syntax into WebKit rules:

- Network rules: `||` domain anchors, `|` anchors, `*` wildcards, `^` separators, `$third-party`, resource types (`script`, `image`, `stylesheet`, `font`, `media`, `xmlhttprequest`, `subdocument`, `ping`, `websocket`, `popup`, `document`, `other`, and their negations), `$domain=` (either only included or only excluded domains), `$match-case`, and `@@` exceptions.
- Element hiding: `##` generic and per domain, `#@#` exceptions, and the `$elemhide`, `$generichide` and `$document` exceptions.
- Skipped: regular expression rules, extended CSS (`#?#`, `:-abp-…`, `:has-text()`…), scriptlets and snippets (`#$#`, `#%#`, `##+js`), `$redirect`, `$rewrite`, `$csp`, `$removeparam`, mixed `$domain=` lists, `example.*` domains, and any option it does not know. Skipping loses a rule; misreading one blocks the wrong thing.

WebKit accepts at most 150,000 rules per list and applies an exception only within its own list, so the converter splits the rules over several lists and repeats in each the exceptions that apply to it. Rules are ordered: network blocks, network exceptions, generic hiding, `$generichide` exceptions, domain hiding, `$elemhide` exceptions, `$document` exceptions.

The app bundles a snapshot of both lists (`Scripts/update-filter-lists.sh` refreshes it), so blocking works from the first launch. `ContentBlocker` (BrowserWebKit) compiles the lists off the main thread into a disposable rule list cache, named from a hash of the sources and the converter version, so later launches look them up instead of compiling. `FilterListUpdater` (the app) downloads both lists at launch when the last check is a day old, then once a day while the app runs, as macOS schedules background maintenance (`NSBackgroundActivityScheduler`), which defers a failed check and asks again later; a response is kept only if it is at most 32 MiB and it is a complete Adblock Plus list newer than the one in use and compiles, and `FilterListStore` (BrowserStorage) writes it atomically. Otherwise the previous lists stay in use. Test runs download from the fixture server instead, never from the internet, and bundle nothing.

Each main-frame navigation adds the rule lists to the page, or removes them, from the site's decision, so a site set to Allow is unblocked from its first request. Pages opened before the lists are compiled get them when ready; changing the global setting applies to open pages from their next load; changing a site's switch reloads it.

## Automatic picture in picture

When the selected tab changes and the tab left behind plays a visible, unmuted video, the video moves to the system's picture in picture window; selecting that tab again brings it back inline. It follows the site's decision, then Settings › General. Sites' own picture in picture buttons work too.

macOS WebKit has no public API for picture in picture: it is off in every `WKWebView`. Aero turns on the private preference `allowsPictureInPictureMediaPlayback` Safari uses, only if the running WebKit exposes it, so a WebKit without it only loses picture in picture. The request is a script from the app, which WebKit accepts without a click in the page. A page in picture in picture is never hibernated.

## Limits

- Popups share their opener's content controller, so a popup on another site takes that site's blocking decision for both pages' next loads.
- Blocking has no cosmetic scriptlets or `$redirect` replacements: sites that detect blockers may notice.
- The share menu and the certificate panel are the system's own.
- Only a video in the page's own document moves automatically, not one in an embedded player's frame.
- Top-level navigation to a blocked domain is blocked too, as WebKit applies a rule without resource types to every load.
