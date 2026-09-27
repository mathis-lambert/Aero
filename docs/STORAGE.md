# Storage

Implementation contract (2026-09-27): a fresh SQLite baseline, with no JSON importer or legacy reader. Previous files are preserved outside the new `Storage` directory. Future compatible releases evolve this baseline through ordered transactional migrations.

## Failure cases specified before implementation

1. A schema upgrade fails halfway or is interrupted: its data and version changes roll back together; a verified SQLite snapshot remains available. Rebuilding a referenced table must preserve its child rows, and a migration leaving broken references must roll back.
2. A newer/foreign/corrupt database is opened: no reset, schema creation or maintenance writes; report the failure and retain bytes.
3. Two app processes open the same browser state: the second cannot overwrite the first. A stale asynchronous save cannot replace a newer revision.
4. A relational snapshot loses identities, order, optional values, grants or profile boundaries on reload; a group in another space or duplicate extension identity must be rejected.
5. A write fails after some rows change: all changes roll back, in-memory committed state stays unchanged, retry succeeds.
6. Equal history timestamps cross a page boundary: every row remains reachable exactly once. A temporary lock cannot permanently disable the store; explicit clear/delete failures reach the caller.
7. A candidate extension is rejected or preparation fails: the active package and saved grants remain unchanged. Crash between file staging and registry commit leaves only an unused candidate. Uninstallation is repeatable after interruption.
8. Cache eviction removes durable data, crosses profiles or grows without a bound; caches must be expendable and separate from Application Support records.
9. Quit overtakes queued history writes or titles; shutdown must drain accepted work and surface failures.

Existing profile/session/history/site-control/extension E2E tests exercise real browser integration. Focused storage tests cover arbitrary SQLite faults, schema versions, equal timestamps and transactional invariants that the UI cannot deterministically drive.

## Ownership and layout

`StorageLocation` assembles locations once. Production uses `~/Library/Application Support/Aero/Storage`, Debug uses `Aero Development/Storage`, and tests use `Storage` inside the temporary directory supplied by `AERO_TEST_DATA`. The test runner owns this directory so it can inject startup faults while the app is stopped. App preferences remain in the bundle's UserDefaults domain (a unique suite for each test). Regenerable assets use `~/Library/Caches/<bundle identifier>`; tests get their own Caches directory.

The new directory intentionally starts with fresh profiles; the previous JSON, history and packages remain outside it, untouched and unused. There is no import, compatibility alias, dual write or old-format decoder. This is a one-time pre-release reset authorized for this refactor, not the policy for future releases.

- `Browser.sqlite`: profiles, one space per profile, groups, tabs/favorites, site decisions, extension registrations and grants. Explicit SQL columns, foreign keys, placement checks and domain validation own the format. BrowserStorage owns the schema mapping; BrowserCore contains the domain records.
- `History.sqlite`: separate high-volume history/FTS tables, logically scoped per profile. Failure does not stop browsing. No cross-database foreign key is claimed; future profile deletion must coordinate both stores and WebKit through a recoverable intent.
- `Extensions/<profile UUID>/<package UUID>`: immutable prepared packages; the registry chooses the active package. WebKit extension context IDs remain stable extension IDs.
- Website and extension runtime databases are owned by WebKit's public APIs, never copied or migrated by BrowserStorage.
- Favicons, downloaded filter lists and compiled rules are disposable. Favicon maintenance retains at most 512 files / 32 MiB / 30 days at a scan, with at most 64 writes (4 MiB) between scans. No idle timer is added. Filter resources have fixed identifiers and bounded downloaded input sizes.

## Writes, errors and lifecycle

`BrowserStore` is an actor with a process-level advisory lock for the data root. Other app processes cannot own the same browser store. Schema identity and integrity are checked before normal mutation. A validated initial profile is saved before normal startup is enabled.

Each save compares the current records with the last committed snapshot and writes changed records/order in one transaction. Revision ordering rejects late older saves. No generic ORM, mirrored writable JSON or database connection pool is involved. Tab lookups/differences are in memory; SQL does not delete/reinsert all tabs for a navigation.

Browser state uses WAL and `synchronous=FULL`; history uses WAL and `NORMAL`. SQL bindings and result codes are checked; temporary contention waits at most 250 ms off the main actor and then returns an error. Explicit history deletion waits for commit. Read failures can retry; recording failure is visible in the History page. Background maintenance is bounded and best effort.

Browser mutations save asynchronously through one owned task. While one snapshot is being written, further mutations mark the current session dirty instead of retaining additional snapshots or creating tasks. A killed process can lose queued actions. Once committed, SQLite supplies the configured transaction durability. Titles batch for two seconds; normal quit drains the writer, saves the latest state and retries history's pending writes and titles. There is no claim to restore web forms, page JS memory or arbitrary WebKit runtime state.

## Schema changes

`DatabaseSchema` contains an application identifier and ordered SQL migrations; array position plus one is the schema version. `BrowserSchema` and `HistoryStore.schema` own their respective steps. To change a schema:

1. Specify failure modes and add supported-format fixtures before implementation.
2. Append SQL that transforms existing rows and constraints. Never edit a shipped step or simply bump a number. No migration is needed for unrelated UI changes.
3. The runner validates identity/integrity, snapshots an older database with SQLite's backup API, and executes all pending steps and version updates inside one transaction. A failed step rolls everything back; retry is safe. Newer incompatible schemas are refused before journal configuration or maintenance.
4. Exercise upgrades including skipped versions and failure injection. Keep the resulting E2E `.xcresult` and reproduction manifest. Do not ship without an old-version fixture and semantic checks for retained identities and relationships.

The runner disables foreign-key actions only around the migration transaction and checks all references before commit, then reenables enforcement, including after failure. This permits table rebuilds without cascading deletion of their children. Follow SQLite's [table reconstruction procedure](https://www.sqlite.org/lang_altertable.html#making_other_kinds_of_table_schema_changes) and recreate affected indexes, triggers and views in the migration.

The baseline has one migration; there is deliberately no speculative v2. Tests exercise the actual runner with a separate miniature schema and a failing second migration, proving rollback and retry mechanics without adding fake production migrations.

UserDefaults keys keep small independent preferences. Shortcut overrides have their own document version and preserve unreadable bytes. Any future change to key meanings or shortcut representation must add an explicit conversion in its owner. Neither app release numbers nor display language define storage identity.

## Recovery

After a successful load, `Browser.recovery.sqlite` is an atomically replaced, SQLite-verified snapshot from the start of that launch. Backups are normalized to DELETE journal mode so the snapshot is standalone and readable without staging-path WAL/SHM files. It holds browser state only, never history. A failed read never overwrites it. Failed snapshot maintenance reports a save warning but does not prevent use of a valid primary database.

SQLiteDatabase owns verified snapshot staging and atomic replacement for both recovery and schema upgrades. Creating a launch snapshot returns its retained package IDs from the already validated committed state; startup does not decode the snapshot's tabs again just to enumerate extensions.

A missing primary database with an existing recovery snapshot or WAL is treated as data loss, not a fresh install. Startup failures expose Retry, Show files, and (when validated and compatible) an explicit restore action. Newer formats and another live writer cannot be restored over. Restoration warns that tabs, permissions and extension settings revert; archives current database and WAL sidecars under a unique `Recovery-*` directory; and promotes a verified staged snapshot. `Recovery.pending` blocks startup if interrupted. Recovery archives are never silently pruned because they may be the only remaining original data.

Each database keeps at most one automatic pre-upgrade snapshot (`.upgrade-backup`). Its recovery semantics belong to that upgrade, not an automatic down-migration. Extension cleanup retains packages referenced by the current launch recovery snapshot; if an older upgrade snapshot cannot be enumerated safely, cleanup is withheld. Do not retire a migration snapshot without accounting for referenced assets.

## Extensions

Preparation creates a candidate directory. Review rejection discards only that candidate. Approval commits the package UUID/version/grants before activation. Activation failure restores the prior registration and reloads its immutable package when available. Operations for one extension/profile are serialized; permission requests carry their actual profile, independent of current selection.

Uninstall first persists `isRemoving`, unloads the extension, uses WebKit data-record APIs to clear runtime storage without running the removed extension, checks reported errors, and then removes the registration. Startup completes interrupted removals. Unreferenced directories are collected after startup reconciliation, with recovery references retained. A tombstone whose cleanup fails remains durable; Settings offers Retry removal and restarting also retries it. There is no claim of a transaction spanning SQLite, the filesystem and WebKit.

## Validation

Validation artifacts include each E2E run's `.xcresult`, adjacent command/environment manifest and working-tree patch under `/tmp/aero-e2e-*`. Audit reproductions and measurements are retained under `/tmp/aero-final-audit/`.

Focused package tests cover state round-trip, stale revisions, transaction rollback on SQL failure, single-writer exclusion, future/corrupt preservation, migration rollback/retry, history isolation, deletion, FTS, retention and equal-timestamp pagination. Existing E2E suites cover browser/session/profile/permission integration. `ExtensionsE2ETests` additionally rejects a different package version, relaunches, verifies the original script still runs, removes it and verifies removal after another relaunch.

Performance claims require measurements; this change does not claim a faster startup or lower energy consumption. Immediate critical-state transactions trade write latency for a smaller crash-loss window; only changed rows are written, and animated titles are batched.

## Audit regression cases specified before corrections

A failed history write must retry after its cause is removed, preserve its original visit time, and never replay across a later clear; switching between two History profiles must reset rows, selection and search; cursor pagination must seek into the date/id index; a failed snapshot replacement must preserve the prior snapshot; bursts of browser changes must retain only one in-flight save and the latest pending state, and quit must persist that final state. Existing SQL fault tests and recovery E2E cover snapshot durability; history UI regressions use E2E with temporary databases.
