# Build and release

## Contract

A source checkout always builds **Aero Dev** by default, even at a release tag. An Apple account is not required. Debug and Release describe compiler optimization, not a publication channel. Official publication is an explicit operation from an immutable Git tag.

One Xcode project, one application target and the local BrowserKit package own the build. Shared schemes and xcconfig files are the source of build settings. Platform.xcconfig owns settings shared by all targets; UITests.xcconfig owns test-runner settings. Shell scripts orchestrate Apple's tools; GitHub Actions calls those same scripts.

## Toolchain

`Configuration/Toolchain.env` pins Xcode 27.0 (27A266a), which supplies Swift 6.4. The Swift language mode is 6, the architecture arm64 and the deployment target macOS 26.0. Both the CLI and the Xcode application build phase check the selected Xcode version.

Install the Metal Toolchain once:

```sh
xcodebuild -downloadComponent MetalToolchain
```

Select the required Xcode with `DEVELOPER_DIR` or `xcode-select`. CI uses the standard ARM `xcode-27` runner and explicitly selects `/Applications/Xcode_27.0.0.app/Contents/Developer`; it fails if Apple tooling differs from the pin. This runner image is currently in public preview. Updating the toolchain is a reviewed configuration change, not a silent switch to latest.

## Source builds

Open `Aero.xcodeproj`, select **Aero Dev**, and Run. Local signing uses Xcode's **Sign to Run Locally** (ad hoc), with no team or provisioning profile. Other channel schemes are available for explicit inspection, also with local signing until distribution supplies the identity. Run E2E tests through the Aero Dev scheme, in Debug or Release.

```sh
Scripts/build.sh build
Scripts/build.sh run
Scripts/build.sh run --configuration Release
Scripts/build.sh dmg
```

`dmg` defaults to Release; the other commands default to Debug. `--configuration Debug|Release` selects optimization without changing the dev identity. Source builds accept a dirty checkout. Logs, a source patch (including untracked files), a manifest and optional DMG are retained in a unique `build/artifacts/` directory. DerivedData lives in `build/DerivedData/`. Nothing installs into Applications automatically.

The local DMG contains Aero Dev and a shortcut to Applications. Its filename explicitly says `local`; it is not a notarized public release. Ad hoc signing may cause macOS to ask for privacy permissions again after rebuilds.

## Channels and data

| Channel | Scheme | Configuration | Bundle identifier | Application Support directory |
| --- | --- | --- | --- | --- |
| Source | Aero Dev | Debug / Release | app.getaero.browser.debug | Aero Development |
| Nightly | Aero Nightly | Nightly | app.getaero.browser.nightly | Aero Nightly |
| Beta | Aero Beta | Beta | app.getaero.browser.beta | Aero Beta |
| Stable | Aero | Stable | app.getaero.browser | Aero |

All publication configurations use the same optimized compiler settings. Each has a distinct app name and bundle identifier, so applications coexist. `AeroDataDirectory` in the built Info.plist selects browser records independently of `DEBUG`. Dev and stable retain their durable directory names and identifiers to preserve user data.

Preferences and caches are scoped to the bundle identifier. Profile records and their UUIDs live in each channel's database; BrowserWebKit owns the corresponding website stores through the public `WKWebsiteDataStore(forIdentifier:)` API. Never copy WebKit files or share a browser database between channels. E2E tests keep using `AERO_TEST_DATA`, unique preference suites and nonpersistent website stores.

## Versioning and tags

`Configuration/Version.xcconfig` owns the next marketing version. Info.plist reads it through `MARKETING_VERSION`. Published beta and stable tags must match that version. `CFBundleVersion` for publication is the full-history commit count, while `AeroRevision` records the full commit SHA. Local builds use build number 1 and the CLI records its revision; direct Xcode builds identify the revision as `local`.

Accepted tags:

- `nightly-<full-commit-SHA>`: one immutable nightly per pushed main commit.
- `vX.Y.Z-beta.N`: numbered beta, N starts at 1.
- `vX.Y.Z`: stable.

No leading zeroes in numeric versions. Every published tag must point to a commit reachable from main. Increment the marketing version through review before the next product version. Beta identifiers belong to the tag and release name, not to Apple's numeric marketing version field.

## Official packaging

```sh
export APPLE_TEAM_ID='<team>'
export APPLE_API_KEY_ID='<key ID>'
export APPLE_API_ISSUER_ID='<issuer UUID>'
export APPLE_API_KEY_PATH='/absolute/path/to/notarization.p8'
Scripts/distribute.sh v0.1.0-beta.1
```

The named tag must exist at HEAD and the checkout must be clean. A Developer ID Application signing identity must be present in the keychain. The script does not create tags, modify the checkout or publish releases.

The pipeline archives with Xcode, exports with Developer ID and a secure timestamp, notarizes a ZIP of the app, staples the app, then creates a compressed DMG with `diskutil image create from`, containing the app and Applications shortcut. It signs and notarizes the DMG and staples its ticket. Hardened runtime and the app's declared device entitlements are retained. Distribution must not contain `get-task-allow=true`.

The app is checked with `codesign`, `stapler` and `syspolicy_check`; the DMG with `hdiutil`, `codesign`, `stapler` and `spctl`. Only after all checks succeed does a `public/` directory appear, containing the DMG, SHA-256 checksum and manifest. Archives, dSYMs, export logs and notarization responses remain alongside it. Builds are traceable to source and tooling; signed and timestamped outputs are not promised to be byte-identical.

Each notarization waits at most 30 minutes. Failure or timeout stops publication and retains the submission response. An Apple submission can continue after a timeout: use its retained ID with `notarytool info` or `log` to diagnose it. Rerunning creates a fresh output directory; it does not overwrite previous results. Keep archive/dSYM backups for released versions beyond the CI retention period.

## GitHub Actions

`ci.yml` builds Debug and packages a local Release DMG on main and pull requests. It has read-only repository access and no Apple secrets. It retains outputs for 7 days. UI tests run through `Scripts/run-e2e.sh` in a logged-in GUI session; the hosted build workflow does not claim E2E coverage.

`distribution.yml` builds a nightly on every push to main, using the exact commit from the push event even if main advances before the runner starts. There is no scheduled build. Tags include the full commit SHA, so multiple pushes on the same day have distinct releases. Manual dispatch accepts an existing tag; leave it empty to build main. Retrying an already published release is a no-op; failed builds reuse their immutable tag.

Preparation checks the tag and main ancestry before credentials are loaded. Automatically created nightly tags use `GITHUB_TOKEN`; the same workflow proceeds to distribution directly, without relying on a new tag-triggered run. Beta and nightly releases are marked prerelease and never latest. Stable releases become latest. A release is created as a draft, receives all artifacts, and is published only after upload succeeds. Existing GitHub Releases are never overwritten. If upload fails, inspect and delete the incomplete draft before retrying; its tag stays unchanged. Concurrency is scoped to the ref and commit/tag: different main pushes can build independently without replacing each other in the pending queue.

The `distribution` GitHub environment contains:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | APPLE_CERTIFICATE_P12_BASE64 | Base64 PKCS#12 certificate and private key |
| Secret | APPLE_CERTIFICATE_PASSWORD | PKCS#12 export password |
| Secret | APPLE_API_PRIVATE_KEY | App Store Connect team API key, PEM .p8 content |
| Variable | APPLE_TEAM_ID | Apple Developer team |
| Variable | APPLE_API_KEY_ID | API key identifier |
| Variable | APPLE_API_ISSUER_ID | API issuer UUID |

The job imports the certificate into a temporary keychain. It writes the API key only to runner temporary storage and removes credentials in an `always()` cleanup step. Signing secrets are never required by contributors. GitHub supplies the release token with `contents: write`; no personal access token is needed. Protect main, release tags and changes to workflows; restrict the distribution environment to trusted publication refs. Configure any desired stable approval in GitHub environment protection rules.

Public repositories use free standard hosted runner compute; larger runners are not selected. Artifacts have a retention policy: CI outputs 7 days, distribution archives and diagnostics 14 days. Published DMGs are GitHub Release assets, separate from transient Actions artifacts.

## Validation and failure modes

Before changing this pipeline, account for: missing toolchain/components; absent signing credentials; wrong PKCS#12 password or team; malformed/moved tags; dirty source; mismatched version; shallow history; missing channel metadata; shared user-data paths; failed or timed-out notarization; missing tickets; damaged signatures; partial uploads; retries replacing published assets; and secrets appearing in logs or artifacts.

Validate a source Debug build and Release DMG without a Developer ID identity, inspect channel metadata, and run focused session/storage and appearance E2E tests with retained xcresult and reproduction manifests. Inspect the mounted DMG and copy its app to a temporary install directory before launch. Official acceptance also requires the signed pipeline and a real downloaded/quarantined install, ideally on another Mac, including an offline launch. Verify channel website-data isolation through browsing before claiming it as experimentally validated. Test the custom Finder icon after installation; Xcode removes its resource-fork metadata from reused build products before signing.

Passkeys and any future managed entitlements are separate features. Add only approved capabilities and the required provisioning profiles to their explicit channel identities; do not make ordinary source builds depend on publication credentials.

## References

- [Apple: xcconfig files](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project)
- [Apple: packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [Apple: notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [GitHub: Apple certificates on runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [GitHub: workflow triggering and GITHUB_TOKEN](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)
