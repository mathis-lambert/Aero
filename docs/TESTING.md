# Testing

Two kinds of tests, each for what only it can check. Unit tests pin down rules with many cases, in seconds.
Journeys drive the real app through what a person does, in minutes. A behavior is tested once, at the lowest level
that can observe it.

## Layout

```text
Packages/BrowserKit/Tests/   Swift Testing, one target per module: models, formats, stores, WebKit helpers, extensions
  BrowserExtensionsTests/Fixtures/   an extension checking, in WebKit, what Aero adds to its engine
Tests/
  AeroTests/                 Swift Testing, hosted by Aero Dev: the app's own rules
    Shortcuts/               resolution, conflicts, persistence, priority, key identity
    Sidebar/                 tab order and drop targets
    Localization/            the String Catalog against the sources
    Onboarding/              wind decay, shape completion and motion policy
  AeroUITests/               XCUITest
    Support/                 E2ETestCase, Seed, FixtureServer, ScreenshotColor
    Journeys/                one file per area, one test per journey
    Performance/             launch, idle onboarding, rendering and many-spaces measurements
    Fixtures/
      pages/                 served over HTTP by FixtureServer
      extensions/            folders installed from Settings › Extensions
      import-sources/        fixture browsers for the onboarding (docs/ONBOARDING.md)
      native-hosts/          the native messaging host the test extension talks to
  Plans/                     Unit, Smoke, Full and Performance test plans
```

## Choosing the level

- **Unit test** a rule that is pure or nearly so and has many cases or failure modes: parsers and importers,
  migrations and recovery, shortcut resolution, ordering and drop geometry, catalog completeness. List the failure
  modes at the top of the file before writing the code, and keep a test only if it would catch a real bug.
  Never test a view, a trivial value or the implementation's own shape.
- **Journey** what needs the real app: WebKit, keyboard focus and routing, menus, windows, drag and drop, the
  Settings window, persistence across launches. Before adding a test, add a step to the journey that already goes
  there. Do not check in a journey what a unit test checks.
- **Extension compatibility** uses controlled Chrome-format example extensions checked into the repository. Test
  browser API contracts and app integration; never a vendor's UI, private messages or a moving store release.
  Select the relevant tests in `BrowserExtensionsTests` (docs/EXTENSIONS.md › Verification).
- **Performance** only in its plan, in Release, with the numbers reported alongside the hardware (docs/PERFORMANCE.md).

## Writing journeys

- One launch per journey. `launch()` takes the language, layout, appearance and the screen to reach
  (browser, onboarding or recovery); `relaunch()` and `quitAndRelaunch()` keep or change them.
- **Seed what is not under test.** `launch { seed in … }` writes spaces, profiles, groups and tabs through
  `BrowserStore` before launch, so a journey starts where its checks begin. Build through the interface only what the
  journey verifies.
- Wait for conditions (`waitForExistence`, `poll`), never for time. `pause` is only for something that must *not*
  happen, or for a system transition with nothing to observe.
- Query by accessibility identifier. Where the menu bar and a context menu share a title, use
  `chooseInContextMenu`, `chooseInMenuBar` and `chooseInSubmenu`.
- Every assertion says what it proves. Attach screenshots at the moments a reviewer should see.
- Each test has four minutes (the plans enforce it); a journey that needs more is two journeys.

## Isolation

`AERO_TEST_DATA` points each journey at a folder of its own: records, caches, downloads, a preferences suite and a
keychain namespace, with ephemeral website stores. The unit tests' host app gets its own folder from the plans.
Test runs never read other browsers, the internet, the real keychain or the Mac's default browser setting:
`AERO_TEST_SEARCH`, `AERO_TEST_FILTERS`, `AERO_TEST_NATIVE_HOSTS` and `AERO_TEST_IMPORT_SOURCES` point at fixtures.

## Running

```sh
Scripts/test.sh unit          # package and app unit tests, after every change
Scripts/test.sh               # smoke: unit tests and the six core journeys, while developing
Scripts/test.sh full          # everything but performance, before a commit or a pull request
Scripts/test.sh performance   # in Release
Scripts/test.sh full AeroUITests/SidebarJourneys   # one area
```

Journeys need a logged-in GUI session and control the mouse and keyboard while they run. Each run keeps a unique
`/tmp/aero-tests-*.xcresult` with its screenshots, a manifest with the exact command, revision, toolchain and fixtures,
and a patch of the tested working tree.

Still checked by hand: physical keyboard layouts and input methods, device permissions, passkey ceremonies and the
default browser confirmation on a signed build, Reduce Motion, and frame pacing in Instruments.

## Xcode Cloud

Use Xcode Cloud's **Test** action to run journeys on Apple's Macs without taking over the developer's desktop.
Cloud builds test products and runs them in a separate phase; fixtures therefore come from the UI test bundle,
not a source checkout path. The runner fails before launching Aero if that resource folder is missing.

Onboard `Aero.xcodeproj` from **Integrate > Xcode Cloud > Create Workflow** in Xcode, select the Apple Developer
team and authorize access to the Aero GitHub repository. Xcode 27 supports onboarding a product for building and
testing without an App Store app record. Keep this a test workflow
with no archive, distribution or TestFlight post-action.

Configure the workflow as follows:

- Scheme: **Aero Dev**; action: **Test**, configuration **Debug**, destination **macOS on Apple Silicon**.
- Select **Smoke** for pull requests targeting `main`; use **Full** for a separate manual workflow initially.
- Disable parallel execution of UI journeys: they share a desktop, focus and the system pasteboard.
- Select **Xcode 27.0 (27A266a)** explicitly. Do not use a latest-version alias: `Scripts/check-toolchain.sh`
  rejects a different version. If Cloud does not offer the pinned version or an arm64 test destination, the workflow
  cannot run this checkout; update the toolchain deliberately rather than bypassing that check.
- Select a compatible build OS and the desired test OS among Cloud's available destinations. A run on macOS 27
  does not verify macOS 26 compatibility.

`ci_scripts/ci_post_clone.sh` checks the selected toolchain. The pinned Cloud image already includes Metal;
downloading that component again fails with an "already imported" error. Cloud
owns the test action; do not call `Scripts/test.sh` from a custom build script. Local ad hoc signing remains the
source default; resolve any Cloud signing requirements through the workflow/team configuration rather than adding
personal signing settings to the repository.

Start one manual Smoke run to verify Cloud signing, runner launch, fixture access and desktop interactions. Inspect
the `.xcresult` and attached screenshots before enabling automatic triggers. Cloud retains result bundles and build
logs in its reports; the local `/tmp` manifest from `Scripts/test.sh` is not produced by Cloud's native test action.
Apple Developer membership includes 25 compute hours per month; monitor usage before adding scheduled Full runs.

The configured **E2E Smoke** workflow currently starts manually from a branch, uses **Aero Dev / Smoke**,
builds with **Xcode 27 (27A266a)** on **macOS 27 (26A428)**, and tests on **macOS 26.6.2 (25G83)**.
Start it from Xcode's **Report navigator > Cloud > Aero > E2E Smoke > Start Build**. Use `fix/compatibility`
until the Cloud preparation has landed on `main`. Automatic pull-request triggers and a separate Full workflow
should be enabled only after the first Smoke run succeeds.

References: [workflow actions](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions),
[custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts),
[getting started](https://developer.apple.com/xcode-cloud/get-started/).
