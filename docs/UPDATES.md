# Software updates

Aero uses Sparkle 2.10.0, pinned in the Xcode project and Package.resolved. This is
an application dependency, not a BrowserKit dependency: Sparkle owns update checks,
downloads, archive verification, installation and its native, localized update UI.
It avoids maintaining a privileged installer, archive extractor or replacement protocol
in Aero. The framework is embedded by Swift Package Manager. No extra daemon or polling
loop is added by the application; automatic checks use Sparkle's daily schedule.

## Channels

There is one published Aero app (`app.getaero.browser`, data in `Aero`), whatever the release. The update channel
is the person's choice in Settings › Software Updates, kept in the preferences (`browser.updates.channel`); every
channel is the same app, with the same tabs, history, passwords and website data.

| Channel | Reads | Gets |
| --- | --- | --- |
| Stable (default) | `https://getaero.app/updates/stable.xml` | `vX.Y.Z` releases |
| Beta | the same feed, with Sparkle's `beta` channel allowed | `vX.Y.Z-beta.N` and `vX.Y.Z` releases |
| Nightly | `https://getaero.app/updates/nightly.xml` | `nightly-<sha>`, one per main commit |

Betas are announced in the stable feed, in Sparkle's `beta` channel; stable releases are in no channel, so everyone
gets them and Sparkle offers whichever allowed build is newest. `AppUpdater` allows that channel through
`allowedChannels(for:)` when Beta is chosen. Stable releases and betas therefore distribute one at a time, so neither
rebuilds `stable.xml` from a base the other is replacing. Nightlies come from every main commit: they have their own
feed, named through `feedURLString(for:)`, so rebuilding it does not rewrite the feed every stable client reads, and it
never lags a beta or stable release. Each feed is signed whole by CI.

Stable and beta read Sparkle's default feed, from Info.plist. Changing the channel resets Sparkle's update cycle and
checks in the background at once. Sparkle never installs an older build: moving to a steadier channel, from nightly to
stable for example, takes effect with that channel's next release newer than the installed one; Settings says so. An
update already downloaded still installs on quit and stays offered. No feed URL or key comes from a runtime environment
variable or downloaded settings.

## In Aero

`AppUpdater` is owned by `BrowserModel`, outside SwiftUI reconstruction. It starts after onboarding (or immediately on
an existing installation). Settings, the application menu and the command catalog use the same check action. It adapts
Sparkle's KVO properties into Observation and follows Sparkle's delegate callbacks into one status: checking, up to date,
an update available, an update downloaded and ready, or a failure. It does not persist a second set of preferences.
Automatic checking and downloading default to enabled and can be disabled independently. System profiling is off.

- **Settings › Software Updates**: the app icon, version, build and channel, the status with the one action that fits
  (Check for Updates, Install…, Restart to Update), the channel choice with what each brings, and the two automatic
  switches.
- **The sidebar's reminder**: Sparkle's gentle scheduled update reminders. An update found on schedule never opens a
  window over the page; a small card above the sidebar's footer names the version and offers Update, which opens it in
  Sparkle's window with its notes, or Restart once it is downloaded. Closed, it stays away until a newer version or
  the next launch. Checks the person asks for always use Sparkle's window.

A downloaded update installs when the app quits. Restarting now, from the sidebar, Settings or Sparkle's window, asks
the user to save website work and warns explicitly about active downloads. Cancel keeps the browser open. Every
accepted termination, including Sparkle's request, passes through the existing asynchronous session/history flush. A
failed save cancels termination. Tabs are restored as records, not as arbitrary website execution state: unsaved forms,
active calls and session-only downloads cannot be promised to survive. Aero never initiates a forced restart or claims
to detect all unsaved website state.

Source builds (Aero Dev, Debug or Release) and `AERO_TEST_DATA` runs do not create Sparkle; Settings shows the channels
disabled. Only `Scripts/distribute.sh` enables it while supplying the public key. A distribution of another identity
or key is disabled with an explanatory Settings message. Sparkle startup errors are also shown there.

## Trust and packaging

Archives retain Developer ID signing and notarization. Sparkle also verifies Ed25519
signatures **before extraction**. Feeds are signed too, with no expiry fallback to an
unsigned feed (`SUSignedFeedFailureExpirationInterval = 0`). Losing the EdDSA key therefore
requires manual reinstallation for clients that can no longer validate a feed; keep an
encrypted offline backup. Planned rotations must retain the old signing key until the
transition is complete. This ZIP-only pipeline does not automate emergency DMG recovery.

The public key comes from the distribution environment variable `SPARKLE_PUBLIC_ED_KEY`
and is embedded at build time. `SPARKLE_PRIVATE_KEY` is a GitHub environment secret;
it is written only to runner temporary storage, never the checkout or retained artifacts.
The framework and command-line tools must be upgraded together: the tools archive is
SHA-256 pinned in `Scripts/sparkle-tools.sh`. Keep their release notes and security fixes
under review. Do not rotate a production key by simply changing these two settings;
follow Sparkle's documented key-rotation procedure for already installed applications.

Only complete app ZIPs enter the appcast generator. DMGs remain manual installers and
dSYM ZIPs remain debugging artifacts. Delta updates are disabled: Aero supports Finder
custom icons which modify its installed bundle, and complete archives keep that case
simple. The chosen icon is reapplied at launch. GitHub-generated source ZIPs are never
updater inputs.

Build numbers are `<full-history-commit-count>.0`, or `<count>.<beta-number>` for beta
releases. This lets another beta tag on the same commit advance. Publishing an older
commit may create a historical GitHub release, but cannot move the live feed backwards.

## Release and retry

1. Build and notarize the application and create the final app ZIP.
2. Retrieve the existing appcast of the tag's feed: `nightly.xml` for nightlies, `stable.xml`
   otherwise. Only 404 means a first publication; other HTTP failures stop distribution. Verify
   an existing feed before reusing it.
3. `generate_appcast` signs the archive and feed, infers OS/hardware requirements and
   embeds the same Markdown notes used by the GitHub release: the annotated tag's message
   for beta and stable (BUILD_AND_RELEASE.md › Versioning and tags). It keeps up to five
   versions per compatibility branch, Sparkle channel included. A beta's item is in the
   `beta` channel. No extra release-notes hosting is needed.
4. Publish the GitHub draft only after every asset, including `<feed>.xml`, uploads.
5. A separate Linux job downloads that immutable appcast, checks its archive URLs,
   sends it over SSH and verifies the public endpoint serves the same bytes.

A `workflow_dispatch` with an already published tag skips rebuilding and retries only
feed publication. GitHub release assets are not overwritten. Retrying an old pre-updater
release without an XML asset fails explicitly. The app continues to use the last valid
feed while publication is unavailable. Workflows can finish out of order: the server
rejects older builds and conflicting archives for an existing build. Such a rejected
old publication does not warrant rolling back the newer feed.

## One-time setup before merging/enabling distribution

GetAero serves `stable.xml` and `nightly.xml` from its persistent directory.
`beta.xml` is never written. A feed not yet published returns 404; no placeholder should be installed.

1. Fetch the pinned tools with `Scripts/sparkle-tools.sh /tmp/aero-sparkle-tools`.
   Run `bin/generate_keys --account Aero` from that directory, then use `-p` to read
   the public key and `-x <private-file>` to export the private key. Back up the private
   file securely. Add the public key as variable `SPARKLE_PUBLIC_ED_KEY` and the private
   file contents as secret `SPARKLE_PRIVATE_KEY` in GitHub's `distribution` environment.
2. On the GetAero host, install `Scripts/receive-appcast.py` somewhere the publishing
   account cannot modify, for example `/usr/local/libexec/aero-receive-appcast.py`.
   It requires Python 3.10+ and no third-party packages. Give a dedicated, unprivileged
   account write access only to `/opt/mathislambert.fr/applications/getaero/updates`;
   files must remain readable by Nginx. Preserve the existing deployment user's access.
3. Install a dedicated SSH public key with a forced command in that account's
   `authorized_keys` (one line, replacing the final public key):

   ```text
   restrict,command="/usr/bin/python3 /usr/local/libexec/aero-receive-appcast.py /opt/mathislambert.fr/applications/getaero/updates" ssh-ed25519 <public-key>
   ```

   The account must have no Docker access. Keep the receiver and SSH configuration
   outside the writable updates directory. `SSH_ORIGINAL_COMMAND` must be exactly
   `stable` or `nightly`; arbitrary shell commands and paths are rejected.
   After a change to `receive-appcast.py`, copy the new file over the installed one before
   the next release.
4. In Aero's `distribution` environment add `UPDATE_HOST`, `UPDATE_USER`,
   `UPDATE_SSH_KEY`, `UPDATE_KNOWN_HOSTS` and optionally `UPDATE_PORT` (default 22).
   Obtain the host key over a trusted connection. Do not reuse the site's Docker
   deployment credential for this restricted publisher.

The receiver bounds input, validates each feed's GitHub archive URLs and their Sparkle
channel (in the stable feed, betas only in `beta` and stable releases in none, so a beta never
reaches everyone) and numeric versions, holds a per-feed filesystem lock, requires each
channel's newest build to move forward against the current feed, and
writes a mode-644 temporary file before fsync and atomic rename. It preserves the signed
XML bytes exactly. It trusts the authorized CI signer; cryptographic verification is
performed during generation and independently by every Sparkle client. Temporary files
and lock files are inaccessible through GetAero's Nginx configuration.

## Validation

- `Scripts/test.sh unit`: update isolation/configuration, the chosen channel's persistence, and catalog coverage.
- `python3 -m unittest discover -s Tests/Distribution -v`: malformed input, wrong feed or Sparkle channel,
  stale publication, same-build conflict, idempotent retry and file preservation.
- `Scripts/test.sh full`: includes Settings' disabled updater in the isolated Dev app.
- Before shipping the first enabled release, install two notarized releases of one channel in an
  isolated macOS account. Verify discovery, notes, download, cancel/retry, installation
  on quit, immediate restart, restoration and persistence failure. Test a broken archive
  signature and unavailable feed. Keep the commands, exact signed artifacts, appcast,
  OS version and resulting logs/screenshots with the release validation record.
  In that disposable account only, with the Stable or Beta channel chosen, Sparkle's existing
  `SUFeedURL` preference can point Aero at a local HTTP fixture server (`defaults write
  app.getaero.browser SUFeedURL -string http://127.0.0.1:<port>/stable.xml`); include a beta
  item to check that only Beta offers it. Nightly names its feed itself.
  Sign that fixture appcast and its archives with the key embedded in the test builds;
  never disable signature verification or publish test builds to the live channel.
  Remove the override after the test. This does not require changing Aero's production
  feed configuration or adding an updater bypass to the normal UI test host.

Local builds and the normal test suite do **not** prove signed replacement works. The
first updater-enabled app must be installed manually; existing releases have no updater.
