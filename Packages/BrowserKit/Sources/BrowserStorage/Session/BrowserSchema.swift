extension DatabaseSchema {
    static let browser = DatabaseSchema(identifier: 0x41455232, migrations: ["""
        CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id = 1), initialized INTEGER NOT NULL CHECK(initialized IN (0,1)));
        INSERT INTO state VALUES (1, 0);
        CREATE TABLE profiles (
            id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, removing INTEGER NOT NULL CHECK(removing IN (0,1)),
            position INTEGER NOT NULL CHECK(position >= 0)
        ) STRICT;
        CREATE TABLE spaces (
            id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
            name TEXT NOT NULL, color TEXT NOT NULL, emoji TEXT,
            position INTEGER NOT NULL CHECK(position >= 0)
        ) STRICT;
        CREATE INDEX spaces_profile ON spaces(profile_id);
        CREATE TABLE tab_groups (
            id TEXT PRIMARY KEY NOT NULL, space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
            name TEXT NOT NULL, collapsed INTEGER NOT NULL CHECK(collapsed IN (0,1)), position INTEGER NOT NULL CHECK(position >= 0),
            UNIQUE(id, space_id)
        ) STRICT;
        CREATE TABLE tabs (
            id TEXT PRIMARY KEY NOT NULL, space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
            url TEXT NOT NULL, title TEXT NOT NULL, custom_name TEXT,
            placement TEXT NOT NULL CHECK(placement IN ('open','grid','list')), group_id TEXT,
            position INTEGER NOT NULL CHECK(position >= 0),
            CHECK(group_id IS NULL OR placement = 'list'),
            FOREIGN KEY(group_id, space_id) REFERENCES tab_groups(id, space_id) DEFERRABLE INITIALLY DEFERRED
        ) STRICT;
        CREATE INDEX tabs_space ON tabs(space_id, position);
        CREATE INDEX groups_space ON tab_groups(space_id, position);
        CREATE TABLE site_permissions (
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE, origin TEXT NOT NULL,
            permission TEXT NOT NULL, decision TEXT NOT NULL CHECK(decision IN ('allow','block')),
            PRIMARY KEY(profile_id, origin, permission)
        ) STRICT;
        CREATE TABLE extensions (
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE, id TEXT NOT NULL,
            version TEXT NOT NULL, package_id TEXT NOT NULL, source_folder TEXT,
            enabled INTEGER NOT NULL CHECK(enabled IN (0,1)), pinned INTEGER NOT NULL CHECK(pinned IN (0,1)),
            removing INTEGER NOT NULL CHECK(removing IN (0,1)), pending_version TEXT, position INTEGER NOT NULL,
            PRIMARY KEY(profile_id, id)
        ) STRICT;
        CREATE TABLE extension_grants (
            profile_id TEXT NOT NULL, extension_id TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('permission','site')),
            value TEXT NOT NULL, PRIMARY KEY(profile_id, extension_id, kind, value),
            FOREIGN KEY(profile_id, extension_id) REFERENCES extensions(profile_id, id) ON DELETE CASCADE
        ) STRICT;
        """, """
        ALTER TABLE profiles ADD COLUMN password_extension TEXT;
        """])
}
