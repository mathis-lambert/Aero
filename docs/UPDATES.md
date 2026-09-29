# Software updates

Aero uses Sparkle 2.10.0, pinned in the Xcode project and Package.resolved. This is
an application dependency, not a BrowserKit dependency: Sparkle owns update checks,
downloads, archive verification, installation and its native, localized update UI.
It avoids maintaining a privileged installer, archive extractor or replacement protocol
in Aero. The framework is embedded by Swift Package Manager. No extra daemon or polling
loop is added by the application; automatic checks use Sparkle's daily schedule.

## Application behavior

`AppUpdater` is owned by `BrowserModel`, outside SwiftUI reconstruction. It starts after
onboarding (or immediately on an existing installation). Settings > Software Updates,
the application menu and the command catalog use the same check action. Settings adapts
Sparkle's KVO properties into Observation; it does not persist a second set of preferences.
Automatic checking and downloading default to enabled and can be disabled independently.
System profiling is off.

A downloaded update installs when the app quits. Sparkle can offer an immediate restart;
Aero then asks the user to save website work and warns explicitly about active downloads.
Cancel keeps the browser open. Every accepted termination, including Sparkle's request,
passes through the existing asynchronous session/history flush. A failed save cancels
termination. Tabs are restored as records, not as arbitrary website execution state:
unsaved forms, active calls and session-only downloads cannot be promised to survive.
Aero never initiates a forced restart or claims to detect all unsaved website state.

Source builds (including local Beta/Stable scheme builds) and `AERO_TEST_DATA` runs do not
create Sparkle. Only `Scripts/distribute.sh` enables it while supplying the public key.
A configured distribution with an invalid channel, identity, key or feed is disabled
with an explanatory Settings message. Sparkle startup errors are also shown there.

| Application | Feed | Bundle ID |
| --- | --- | --- |
| Aero | `https://getaero.app/updates/stable.xml` | `app.getaero.browser` |
| Aero Beta | `https://getaero.app/updates/beta.xml` | `app.getaero.browser.beta` |
| Aero Nightly | `https://getaero.app/updates/nightly.xml` | `app.getaero.browser.nightly` |

These are separate applications and databases. There is no in-app channel switch.
No feed URL or key is taken from a runtime environment variable or downloaded settings.

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
2. Retrieve the existing channel appcast. Only 404 means a first publication; other
   HTTP failures stop distribution. Verify an existing feed before reusing it.
3. `generate_appcast` signs the archive and feed, infers OS/hardware requirements and
   embeds the same Markdown notes used by the GitHub release: the annotated tag's message
   for beta and stable (BUILD_AND_RELEASE.md › Versioning and tags). It keeps up to five
   versions per compatibility branch. No extra release-notes hosting is needed.
4. Publish the GitHub draft only after every asset, including `<channel>.xml`, uploads.
5. A separate Linux job downloads that immutable appcast, checks its archive URLs,
   sends it over SSH and verifies the public endpoint serves the same bytes.

A `workflow_dispatch` with an already published tag skips rebuilding and retries only
feed publication. GitHub release assets are not overwritten. Retrying an old pre-updater
release without an XML asset fails explicitly. The app continues to use the last valid
feed while publication is unavailable. Workflows can finish out of order: the server
rejects older builds and conflicting archives for an existing build. Such a rejected
old publication does not warrant rolling back the newer feed.

## One-time setup before merging/enabling distribution

GetAero v0.2.3 already serves only `stable.xml`, `beta.xml` and `nightly.xml` from its
persistent directory. Empty channels return 404; no placeholder should be installed.

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
   `stable`, `beta` or `nightly`; arbitrary shell commands and paths are rejected.
4. In Aero's `distribution` environment add `UPDATE_HOST`, `UPDATE_USER`,
   `UPDATE_SSH_KEY`, `UPDATE_KNOWN_HOSTS` and optionally `UPDATE_PORT` (default 22).
   Obtain the host key over a trusted connection. Do not reuse the site's Docker
   deployment credential for this restricted publisher.

The receiver bounds input, validates channel-specific GitHub archive URLs and numeric
versions, holds a per-channel filesystem lock, compares against the current feed, and
writes a mode-644 temporary file before fsync and atomic rename. It preserves the signed
XML bytes exactly. It trusts the authorized CI signer; cryptographic verification is
performed during generation and independently by every Sparkle client. Temporary files
and lock files are inaccessible through GetAero's Nginx configuration.

## Validation

- `Scripts/test.sh unit`: update isolation/configuration and catalog coverage.
- `python3 -m unittest discover -s Tests/Distribution -v`: malformed input, wrong channel,
  stale publication, same-build conflict, idempotent retry and file preservation.
- `Scripts/test.sh full`: includes Settings' disabled updater in the isolated Dev app.
- Before shipping the first enabled release, install two notarized nightlies in an
  isolated macOS account. Verify discovery, notes, download, cancel/retry, installation
  on quit, immediate restart, restoration and persistence failure. Test a broken archive
  signature and unavailable feed. Keep the commands, exact signed artifacts, appcast,
  OS version and resulting logs/screenshots with the release validation record.
  In that disposable account only, Sparkle's existing `SUFeedURL` preference can point
  the nightly app at a local HTTP fixture server (`defaults write
  app.getaero.browser.nightly SUFeedURL -string http://127.0.0.1:<port>/nightly.xml`).
  Sign that fixture appcast and its archives with the key embedded in the test builds;
  never disable signature verification or publish test builds to the live channel.
  Remove the override after the test. This does not require changing Aero's production
  feed configuration or adding an updater bypass to the normal UI test host.

Local builds and the normal test suite do **not** prove signed replacement works. The
first updater-enabled app must be installed manually; existing releases have no updater.
