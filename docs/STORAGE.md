# Storage

Browser state and history use SQLite; preferences use UserDefaults; caches are disposable files. The browser baseline is application ID `0x41455232`, version 1, with no legacy reader or importer. Future shipped schemas evolve through ordered transactional migrations.

## Ownership and layout

`StorageLocation` assembles locations once. The build channel selects `~/Library/Application Support/<channel directory>/Storage`: stable uses `Aero`, dev uses `Aero Development` in both Debug and Release, nightly uses `Aero Nightly`, beta uses `Aero Beta`. See `BUILD_AND_RELEASE.md`. Tests use `Storage` inside the temporary directory supplied by `AERO_TEST_DATA`. The test runner owns this directory so it can inject startup faults while the app is stopped. App preferences remain in the bundle's UserDefaults domain (a unique suite for each test). Regenerable assets use `~/Library/Caches/<bundle identifier>`; tests get their own Caches directory.

The baseline starts with fresh profiles. There is no import, compatibility alias, dual write or old-format decoder. Obsolete pre-release files outside `Storage` are disposable after stopping the old app; cleanup is an explicit development operation, not an application startup fallback. Unknown or corrupt current databases still use recovery rather than silent data deletion.

- `Browser.sqlite`: profiles, multiple spaces per profile, groups, tabs/favorites, site decisions, extension registrations and grants. Explicit SQL columns, foreign keys, placement checks and domain validation own the format. BrowserStorage owns the schema mapping; BrowserCore contains the domain records.
- `History.sqlite`: separate high-volume history/FTS tables, logically scoped per profile. Failure does not stop browsing. No cross-database foreign key is claimed; profile deletion coordinates both stores and WebKit through a recoverable intent.
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

UserDefaults keys keep small independent preferences. Shortcut overrides have their own document version and preserve unreadable bytes. Any future change to key meanings or shortcut representation must add an explicit conversion in its owner. Neither app release numbers nor display language define storage identity.

## Recovery

After a successful load, `Browser.recovery.sqlite` is an atomically replaced, SQLite-verified snapshot from the start of that launch. Backups are normalized to DELETE journal mode so the snapshot is standalone and readable without staging-path WAL/SHM files. It holds browser state only, never history. A failed read never overwrites it. Failed snapshot maintenance reports a save warning but does not prevent use of a valid primary database.

SQLiteDatabase owns verified snapshot staging and atomic replacement for both recovery and schema upgrades. Creating a launch snapshot returns its retained package IDs from the already validated committed state; startup does not decode the snapshot's tabs again just to enumerate extensions.

A missing primary database with an existing recovery snapshot or WAL is treated as data loss, not a fresh install. Startup failures expose Retry, Show files, and (when validated and compatible) an explicit restore action. Newer formats and another live writer cannot be restored over. Restoration warns that tabs, permissions and extension settings revert; archives current database and WAL sidecars under a unique `Recovery-*` directory; and promotes a verified staged snapshot. `Recovery.pending` blocks startup if interrupted. Recovery archives are never silently pruned because they may be the only remaining original data.

Each database keeps at most one automatic pre-upgrade snapshot (`.upgrade-backup`). Its recovery semantics belong to that upgrade, not an automatic down-migration. Extension cleanup retains packages referenced by the current launch recovery snapshot; if an older upgrade snapshot cannot be enumerated safely, cleanup is withheld. Do not retire a migration snapshot without accounting for referenced assets.

## Extensions

Preparation creates a candidate directory. Review rejection discards only that candidate. Approval commits the package UUID/version/grants before activation. Activation failure restores the prior registration and reloads its immutable package when available. Operations for one extension/profile are serialized; permission requests carry their actual profile, independent of current selection.

Uninstall first persists `isRemoving`, unloads the extension, uses WebKit data-record APIs to clear runtime storage without running the removed extension, checks reported errors, and then removes the registration. Startup completes interrupted removals. Unreferenced directories are collected after startup reconciliation, with recovery references retained. A tombstone whose cleanup fails remains durable; Settings offers Retry removal and restarting also retries it. There is no claim of a transaction spanning SQLite, the filesystem and WebKit.

## History

`HistoryStore` opens lazily on its actor. One database contains profile-scoped pages and visits, plus an FTS5 title/address index maintained by triggers. Every operation requires a profile; cursor pagination uses `(last_visit, id)` to preserve equal-timestamp entries.

Failed writes retry in order with their original timestamps, before a later clear can commit. Pending writes are memory-only and cannot survive forced termination. Read failures can retry without disabling browsing. Visits older than a year are pruned in batches of 500 on store activity, at most hourly when caught up and once a minute while catching up.
