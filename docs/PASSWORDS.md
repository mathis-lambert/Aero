# Passwords and passkeys

Aero saves website passwords per profile, fills them on request, suggests strong passwords for new accounts, and leaves passkeys to WebKit and macOS. Passwords never leave the macOS keychain except when the user exports them.

## Why Aero keeps its own passwords

Apple's credential facilities are preferred (AGENTS.md), but none fills a third-party WebKit browser: iCloud Keychain AutoFill is disabled for `WKWebView`, and the Passwords app's browser extensions exist only for Chromium browsers and Firefox. Aero therefore stores its passwords in the user's login keychain, under its own items, and fills them itself. Passkeys are different: macOS offers them to browsers through AuthenticationServices, so Aero stores none.

The login keychain, not the data protection keychain: the latter needs a keychain access group entitlement backed by a provisioning profile, which source builds do not have. Consequences: passwords stay on this Mac (no iCloud sync), and a locally signed build asks macOS for access again after each rebuild, because its code signature changes. Developer ID builds keep a stable signature and do not ask.

## Model

A profile owns its passwords; spaces of the same profile share them, other profiles never see them. A saved login is identified by its profile, origin and username.

Each login is one keychain internet password item:

| Attribute | Value |
| --- | --- |
| Server, protocol, port | The origin the login was saved from (`https` or `http`, host, port) |
| Account | The username, possibly empty |
| Value | The password, UTF-8, and nothing else |
| Security domain | `<bundle identifier>/<profile UUID>`: part of the keychain's uniqueness, so one item exists per profile, origin and username, and release channels never mix |
| Creator | `AERO`, or `AERT` for test runs |
| Label | `host (username)`, what Keychain Access shows |
| Comment | The time of last use, seconds since 1970 |
| Accessibility | When the Mac is unlocked |

Nothing about passwords is written to the SQLite database: the keychain is the only source of truth, so an item deleted in Keychain Access simply disappears from Aero. "Never save for this site" is the site permission **Save passwords** set to Block, stored with the profile's other site decisions ([Site controls](SITE_CONTROLS.md)). Its default follows Settings › Passwords › Offer to save passwords.

The keychain is read in two steps: attributes of every matching item without secrets, then a single secret when it is needed. Reading is off the main actor.

## Matching sites

A login is offered on the page's origin first, then on origins of the same site: the same registrable domain, computed with the Public Suffix List bundled in the app (`Scripts/update-public-suffix-list.sh`; © Mozilla Foundation contributors, MPL 2.0). So `accounts.example.com` gets the logins of `example.com`, but `alice.github.io` never gets those of `bob.github.io`. A login saved over HTTPS is never offered over HTTP; one saved over HTTP is offered on the same site over HTTPS. Offers are sorted by last use.

## Detecting forms

A script in Aero's isolated content world, in every frame, finds sign-in and sign-up fields: a password field with the text or email field before it, `autocomplete` hints first (`username`, `current-password`, `new-password`). A username-only step can also identify a visible email field or an account field from its name or ID, such as `identifierId`. It reports to the native bridge only:

- a field gaining focus, with its kind and frame-relative position;
- the field losing focus;
- a username-only submission (form submit, a button click, or Return in the account field), with the username typed;
- a password submission (form submit, a click on its submit button, Return in the password field), with the username if present on that page and the password typed.

The bridge takes the origin from `WKScriptMessage.frameInfo`, never from the message; it drops messages from non-web origins and bounds every string (username 512 characters, password 1024). Pages cannot post to the isolated world.

## Filling

When a sign-in field of the selected tab gains focus and the profile has logins for the site, a list of accounts appears under the field, drawn by Aero over the page. Choosing one fills that frame only, after the script checks the frame is still at the same origin, through the fields' native setters with the input and change events a keystroke fires. Nothing is filled without a click. A frame from another origin than the page gets offers for its own origin, never the page's. The list closes when the person types in the field or presses Escape, when the field loses focus, the tab changes or the page navigates. It never takes the keyboard from the page.

## AutoFill

Each profile fills passwords with Aero or with one of its extensions that runs in websites, such as a password manager. Adding such an extension offers to let it fill the profile's passwords, already on for a password manager (docs/EXTENSIONS.md › Password managers); an extension may also take them or give them back with Chrome's `privacy.services.passwordSavingEnabled`; and Settings › Passwords › the profile › AutoFill changes the choice. With an extension chosen, Aero neither shows its list on sign-in fields nor offers to save, so the two never compete on the same field; the extension fills and saves with its own data. The logins saved in Aero stay in the keychain and are offered again when the profile goes back to Aero. A turned-off or failed extension leaves the profile to Aero meanwhile; removing it resets the choice. The choice is stored with the profile.

## Saving

After a username-only step, Aero keeps the account in memory, scoped to its tab, profile and origin. The next password submission in that scope can use it within five minutes if the password page has no account field. An account on the password page takes precedence. A password submission in another scope discards the pending account, and closing the tab clears it. Nothing is saved until the password is submitted.

After a password submission, the credential waits in memory, attached to its tab, and the window offers to save it: **Save**, **Never for this site** or **Not now**. Return saves (or updates) and Escape chooses Not now; the offer takes keyboard focus when it appears so those keys reach the browser instead of the submitted page. A known username with a different password offers **Update** instead; an unchanged one only records its use. Nothing is offered when the site's Save passwords decision is Block, for an empty password, or for a page that is not HTTP(S). The pending credential is forgotten when answered, replaced by a newer submission, or when its tab closes.

## Strong passwords

On a new-password field, the list offers **Use strong password**: 20 characters in three groups of letters and digits, the format of Safari's strong passwords (`abcdef-ghijkl-mnopqr`-shaped, mixed case, at least one digit), from the system's secure random generator. It fills every new-password field of the form and is saved when the form is submitted, as any other password.

## Managing

Settings › Passwords lists the profiles that own saved logins and the shared saving preference. Open a profile to search its logins, import passwords or export a CSV file. Each visible login reuses the profile's site favicon; when none is cached, Aero asks that host for `/favicon.ico`. This uses the existing favicon cache, limited to 256 icons in memory and 512 files or 32 MiB on disk, with one icon per host and profile. Open a login for its account and password details, editing and deletion. Settings Back and Forward move between these pages. The Passwords command (in the command bar) opens the overview. Showing, copying or editing a password and exporting require the Mac owner's authentication (Touch ID or the account password), valid for five minutes. A copied password stays on this Mac, never reaching Universal Clipboard, and is removed from the pasteboard after 60 seconds if it is still there. Deleting a login removes its keychain item.

## Import and export

- **From Chrome, Arc, Dia, Brave, Edge and Vivaldi**: Aero reads the browser profile's `Login Data` from a temporary copy, and macOS asks once for the browser's "Safe Storage" key. Passwords are decrypted in memory (`v10`: AES-128-CBC with a PBKDF2-SHA1 key) and saved into the chosen Aero profile; sites the browser never saves for become Block decisions. Safari's passwords are already in the Passwords app, which Aero cannot read.
- **CSV import**: the columns Chrome, Safari, Firefox and 1Password write (`name`/`title`, `url`, `username`, `password`, `note`/`notes`). Files are limited to 16 MiB so parsing cannot grow without bound. Rows without a web address or a password are skipped and counted.
- **CSV export**: Chrome's columns. The file is plain text, which the save panel says; it is written with owner-only permissions.

An import never overwrites a different saved password for the same login; it reports how many were added, already present and skipped.

## Passkeys

Aero does not take part in passkey requests: WebKit performs them with AuthenticationServices, and macOS shows its own sheet (iCloud Keychain, a password app, a nearby phone or a security key). WebKit does so only in a browser holding Apple's `com.apple.developer.web-browser.public-key-credential` entitlement, granted on request and usable only with a provisioning profile. Apple granted it to the stable identity, `app.getaero.browser`, which is signed with its profile ([BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md#stable-passkey-signing)); Dev, Beta, Nightly and source builds lack it, and pages see WebKit's own answer. Passkeys belong to macOS and the chosen credential provider, not to Aero's profiles or password vault.

Check on the notarized stable app before releasing a newly entitled build:

1. Create a passkey on a test website, restart Aero and sign in with it; sign in with a passkey created in another browser.
2. Note how macOS asks for access to passkeys on first use, then check denial and recovery in System Settings › Privacy & Security.
3. Cancel the system sheet and retry; close the requesting tab while the sheet is open.
4. Leave a page with conditional passkey suggestions open, quit Aero, relaunch it and sign in again: an abandoned request must not block later ones.
5. A security key, a nearby phone or a third-party provider when available.

## Profiles

Deleting a profile deletes its passwords: the step runs with the other data removals, after the deletion intent is saved and before the profile record is removed, and is retried on the next launch if it fails.

## Test runs

With `AERO_TEST_DATA`, items use the creator `AERT` and a security domain under the test folder's name; a launch removes abandoned `AERT` items older than a day, leaving concurrent test runs alone. Real passwords are never read or written by tests. Browsers to import from are looked for only in the fixture sources (`ONBOARDING.md` › Test runs).

## Failure modes and acceptance scenarios

1. A frame of another origin is filled with the page's login, or the page's claimed origin is trusted over the frame's.
2. A login is offered on another site: another registrable domain, a sibling under a public suffix (`github.io`), or HTTP for an HTTPS login.
3. One profile sees, fills or exports another profile's logins; a space of the same profile does not see them.
4. Never for this site is lost on relaunch, or a blocked site still offers to save.
5. A changed password creates a second item instead of offering Update; an import overwrites a different saved password.
6. Deleting a profile leaves its keychain items, or an interrupted deletion never removes them.
7. A locked, denied or failing keychain reads as "no passwords", or saving fails silently.
8. A pending credential survives its tab or is offered after the user moved to another tab; a password appears in a log, the database or a crash report.
9. A generated password is not identical in the new-password fields, lacks a digit, or repeats between suggestions.
10. The account list steals keyboard focus from the page, or stays after the field loses focus or the page navigates.
11. CSV parsing breaks on quoted commas, quotes, line breaks inside fields, a byte order mark or CRLF lines, or loses non-ASCII text; an export cannot be read back.
12. A Chromium import fails for a running browser (locked database), silently skips undecryptable rows, or reads another browser's key.
13. A test run reads or writes real keychain items.
14. A username-only first step is lost before the password page, or a pending username is paired with a password from another tab, profile, origin, or an old sign-in attempt.
15. Renaming a login to an existing username on the same origin replaces that account's password or removes either login.
16. An import still writing while its destination profile is deleted recreates passwords for a profile that no longer exists.
17. An IPv6 site's origin loses its brackets, so its saved login or site decision cannot be read back.

Verification: `PasswordsJourneys` covers saving, filling, Update, Never across relaunch, the strong password on sign-up, profile isolation, Settings listing and deletion, and two-step account capture without crossing tabs or origins (1–5, 8–10, 14). Isolated Swift tests cover site matching (2), CSV (11), Chromium decryption and a running browser's locked database (12), keychain scoping and deletion per profile (3, 5, 6, 7), rename collisions (15), writes after profile deletion (16), and IPv6 origin round trips (17), which UI tests cannot vary exhaustively or observe.
