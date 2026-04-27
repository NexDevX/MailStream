import Foundation

/// V1 schema — first persisted shape.
///
/// Tables:
///  · accounts        — one row per connected mailbox
///  · folders         — IMAP/Graph folders, scoped to an account
///  · messages        — header-only by default, body lazy-loaded
///  · attachments     — metadata only; blob lives on disk under Caches/
///  · sync_state      — per-folder UID/cursor for incremental fetch
///  · drafts          — local-only compose drafts
///
/// All times are stored as **UNIX milliseconds** (`INTEGER`). Strings are
/// always UTF-8. Foreign keys cascade on delete so removing an account
/// purges its data without orphan rows.
enum V1Schema {

    static let version: Int = 1

    static let statements: [String] = [

        // ---------------------------------------------------------------
        // accounts
        // ---------------------------------------------------------------
        """
        CREATE TABLE IF NOT EXISTS accounts (
            id              TEXT PRIMARY KEY NOT NULL,
            provider_type   TEXT NOT NULL,           -- 'qq' | 'gmail' | …
            display_name    TEXT NOT NULL DEFAULT '',
            email_address   TEXT NOT NULL,
            status          TEXT NOT NULL DEFAULT 'disconnected',
            last_synced_at  INTEGER,                 -- UNIX ms
            last_error      TEXT,
            is_enabled      INTEGER NOT NULL DEFAULT 1,
            sort_index      INTEGER NOT NULL DEFAULT 0,
            created_at      INTEGER NOT NULL,
            updated_at      INTEGER NOT NULL
        );
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_email ON accounts(email_address);",

        // ---------------------------------------------------------------
        // folders
        // ---------------------------------------------------------------
        """
        CREATE TABLE IF NOT EXISTS folders (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id      TEXT NOT NULL,
            -- Provider-side identifier: IMAP raw name (UTF-7) or Graph id.
            remote_id       TEXT NOT NULL,
            -- Display name (UTF-8 / decoded).
            name            TEXT NOT NULL,
            -- Logical role: inbox | sent | drafts | trash | junk | archive | other
            role            TEXT NOT NULL DEFAULT 'other',
            unread_count    INTEGER NOT NULL DEFAULT 0,
            total_count     INTEGER NOT NULL DEFAULT 0,
            attributes      TEXT,                     -- JSON array of IMAP flags
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
        );
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_account_remote ON folders(account_id, remote_id);",
        "CREATE INDEX IF NOT EXISTS idx_folders_role ON folders(account_id, role);",

        // ---------------------------------------------------------------
        // messages — header-only by default
        // ---------------------------------------------------------------
        // body_loaded = 0 → headers only; body is fetched lazily and
        // body_text/body_html columns are filled. This keeps the steady-
        // state memory footprint small.
        """
        CREATE TABLE IF NOT EXISTS messages (
            id              TEXT PRIMARY KEY NOT NULL,           -- our UUID
            account_id      TEXT NOT NULL,
            folder_id       INTEGER NOT NULL,
            remote_uid      INTEGER NOT NULL,                    -- IMAP UID
            message_id      TEXT,                                -- RFC822 Message-ID
            thread_id       TEXT,                                -- gmail-style thread group
            in_reply_to     TEXT,
            subject         TEXT NOT NULL DEFAULT '',
            from_name       TEXT NOT NULL DEFAULT '',
            from_address    TEXT NOT NULL DEFAULT '',
            to_addresses    TEXT NOT NULL DEFAULT '[]',          -- JSON [{name,address}]
            cc_addresses    TEXT NOT NULL DEFAULT '[]',
            bcc_addresses   TEXT NOT NULL DEFAULT '[]',
            reply_to        TEXT,
            preview         TEXT NOT NULL DEFAULT '',
            sent_at         INTEGER NOT NULL,                    -- UNIX ms
            received_at     INTEGER NOT NULL,                    -- INTERNALDATE
            size_bytes      INTEGER,
            flags_seen      INTEGER NOT NULL DEFAULT 0,
            flags_flagged   INTEGER NOT NULL DEFAULT 0,
            flags_answered  INTEGER NOT NULL DEFAULT 0,
            flags_draft     INTEGER NOT NULL DEFAULT 0,
            has_attachment  INTEGER NOT NULL DEFAULT 0,
            label_keys      TEXT NOT NULL DEFAULT '[]',          -- JSON array
            body_loaded     INTEGER NOT NULL DEFAULT 0,
            body_text       TEXT,
            body_html       TEXT,
            updated_at      INTEGER NOT NULL,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
            FOREIGN KEY (folder_id)  REFERENCES folders(id)  ON DELETE CASCADE
        );
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_uid ON messages(account_id, folder_id, remote_uid);",
        "CREATE INDEX IF NOT EXISTS idx_messages_received ON messages(account_id, received_at DESC);",
        "CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id) WHERE thread_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_messages_unread ON messages(account_id, flags_seen) WHERE flags_seen = 0;",
        // FTS5 is built into Apple's libsqlite3.
        """
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            subject, from_name, from_address, preview, body_text,
            content='messages', content_rowid='rowid', tokenize='unicode61'
        );
        """,
        // Keep FTS in sync with messages.
        """
        CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
            INSERT INTO messages_fts(rowid, subject, from_name, from_address, preview, body_text)
            VALUES (new.rowid, new.subject, new.from_name, new.from_address, new.preview, COALESCE(new.body_text, ''));
        END;
        """,
        """
        CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, subject, from_name, from_address, preview, body_text)
            VALUES ('delete', old.rowid, old.subject, old.from_name, old.from_address, old.preview, COALESCE(old.body_text, ''));
        END;
        """,
        """
        CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, subject, from_name, from_address, preview, body_text)
            VALUES ('delete', old.rowid, old.subject, old.from_name, old.from_address, old.preview, COALESCE(old.body_text, ''));
            INSERT INTO messages_fts(rowid, subject, from_name, from_address, preview, body_text)
            VALUES (new.rowid, new.subject, new.from_name, new.from_address, new.preview, COALESCE(new.body_text, ''));
        END;
        """,

        // ---------------------------------------------------------------
        // attachments — metadata only; the binary lives on disk.
        // ---------------------------------------------------------------
        """
        CREATE TABLE IF NOT EXISTS attachments (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            message_id      TEXT NOT NULL,
            filename        TEXT NOT NULL,
            mime_type       TEXT NOT NULL DEFAULT 'application/octet-stream',
            size_bytes      INTEGER NOT NULL DEFAULT 0,
            content_id      TEXT,
            disposition     TEXT,                                -- inline | attachment
            cache_path      TEXT,                                -- relative to Caches/MailStream/Attachments
            FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(message_id);",

        // ---------------------------------------------------------------
        // sync_state — per-folder cursor for incremental sync
        // ---------------------------------------------------------------
        """
        CREATE TABLE IF NOT EXISTS sync_state (
            folder_id       INTEGER PRIMARY KEY,
            last_uid        INTEGER NOT NULL DEFAULT 0,
            uidvalidity     INTEGER,                             -- IMAP UIDVALIDITY
            highest_modseq  INTEGER,                             -- CONDSTORE / Gmail history
            last_full_sync  INTEGER,                             -- UNIX ms
            FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
        );
        """,

        // ---------------------------------------------------------------
        // drafts — local compose state, persisted across launches
        // ---------------------------------------------------------------
        """
        CREATE TABLE IF NOT EXISTS drafts (
            id              TEXT PRIMARY KEY NOT NULL,
            account_id      TEXT,
            in_reply_to     TEXT,
            to_addresses    TEXT NOT NULL DEFAULT '',
            cc_addresses    TEXT NOT NULL DEFAULT '',
            bcc_addresses   TEXT NOT NULL DEFAULT '',
            subject         TEXT NOT NULL DEFAULT '',
            body            TEXT NOT NULL DEFAULT '',
            created_at      INTEGER NOT NULL,
            updated_at      INTEGER NOT NULL,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
        );
        """,

        // ---------------------------------------------------------------
        // schema_version — single-row tracker
        // ---------------------------------------------------------------
        "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);"
    ]
}
