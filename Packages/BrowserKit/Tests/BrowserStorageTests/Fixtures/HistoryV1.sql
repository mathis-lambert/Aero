-- Shipped history schema, retained as an upgrade fixture.
CREATE TABLE pages (
    id INTEGER PRIMARY KEY,
    profile_id TEXT NOT NULL,
    url TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    last_visit REAL NOT NULL,
    UNIQUE (profile_id, url)
);
CREATE INDEX pages_recent ON pages (profile_id, last_visit DESC, id DESC);
CREATE TABLE visits (
    id INTEGER PRIMARY KEY,
    page_id INTEGER NOT NULL REFERENCES pages (id) ON DELETE CASCADE,
    visited_at REAL NOT NULL
);
CREATE INDEX visits_page ON visits (page_id);
CREATE INDEX visits_time ON visits (visited_at);
CREATE VIRTUAL TABLE pages_fts USING fts5 (
    title, url, content = 'pages', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2'
);
CREATE TRIGGER pages_insert AFTER INSERT ON pages BEGIN
    INSERT INTO pages_fts (rowid, title, url) VALUES (new.id, new.title, new.url);
END;
CREATE TRIGGER pages_delete AFTER DELETE ON pages BEGIN
    INSERT INTO pages_fts (pages_fts, rowid, title, url) VALUES ('delete', old.id, old.title, old.url);
END;
CREATE TRIGGER pages_update AFTER UPDATE OF title, url ON pages BEGIN
    INSERT INTO pages_fts (pages_fts, rowid, title, url) VALUES ('delete', old.id, old.title, old.url);
    INSERT INTO pages_fts (rowid, title, url) VALUES (new.id, new.title, new.url);
END;
