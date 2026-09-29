# Testing

Two kinds of tests, each for what only it can check. Unit tests pin down rules with many cases, in seconds.
Journeys drive the real app through what a person does, in minutes. A behavior is tested once, at the lowest level
that can observe it.

## Layout

```text
Packages/BrowserKit/Tests/   Swift Testing, one target per module: models, formats, stores, WebKit helpers
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
