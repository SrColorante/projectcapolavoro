-- Schema SQLite per i test.
-- Rispecchia le colonne delle tabelle MySQL toccate dalla logica di sicurezza e
-- GDPR. Non e' lo schema di produzione: serve solo a esercitare le librerie
-- senza richiedere un server MySQL.

CREATE TABLE utenti (
    IDutente          INTEGER PRIMARY KEY,
    nome              TEXT NOT NULL,
    cognome           TEXT NOT NULL DEFAULT 'Utente',
    nickname          TEXT NOT NULL DEFAULT '',
    email             TEXT NULL UNIQUE,
    password_hash     TEXT NOT NULL,
    dataCreazione     TEXT NOT NULL DEFAULT '2026-01-01',
    is_guest          INTEGER NOT NULL DEFAULT 0,
    preferred_language TEXT NOT NULL DEFAULT 'en',
    profile_bio       TEXT NULL,
    profile_photo_url TEXT NULL,
    profile_audio_url TEXT NULL,
    profile_audio_duration_seconds REAL NULL,
    e2ee_public_key   TEXT NULL,
    e2ee_key_algorithm TEXT NULL,
    two_factor_enabled INTEGER NOT NULL DEFAULT 0,
    two_factor_channel TEXT NULL,
    two_factor_destination TEXT NULL,
    two_factor_verified_at TEXT NULL,
    pec_certified_at  TEXT NULL,
    processing_restricted INTEGER NOT NULL DEFAULT 0,
    processing_restricted_at TEXT NULL,
    deletion_requested_at TEXT NULL,
    deletion_scheduled_for TEXT NULL,
    deletion_reason   TEXT NULL,
    erased_at         TEXT NULL,
    data_retention_until TEXT NULL
);

CREATE TABLE utenti_sessioni (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id       INTEGER NOT NULL,
    token_hash    TEXT NOT NULL UNIQUE,
    device_label  TEXT NULL,
    ip_hash       TEXT NULL,
    created_at    TEXT NOT NULL,
    last_used_at  TEXT NOT NULL,
    expires_at    TEXT NOT NULL,
    revoked_at    TEXT NULL,
    revoked_reason TEXT NULL
);

CREATE TABLE consensi (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id      INTEGER NULL,
    subject_pseudonym TEXT NULL,
    tipo         TEXT NOT NULL,
    granted      INTEGER NOT NULL,
    policy_version TEXT NOT NULL,
    source       TEXT NOT NULL DEFAULT 'unknown',
    recorded_at  TEXT NOT NULL DEFAULT (datetime('now')),
    withdrawn_at TEXT NULL,
    ip_hash      TEXT NULL
);

CREATE TABLE audit_log (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    correlation_id   TEXT NOT NULL,
    actor_pseudonym  TEXT NULL,
    actor_user_id    INTEGER NULL,
    action           TEXT NOT NULL,
    resource_type    TEXT NULL,
    resource_id      TEXT NULL,
    outcome          TEXT NOT NULL DEFAULT 'ok',
    ip_hash          TEXT NULL,
    detail           TEXT NULL,
    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE rate_limit_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    bucket_key  TEXT NOT NULL,
    occurred_at TEXT NOT NULL
);

CREATE TABLE chat (
    IDchat     INTEGER PRIMARY KEY,
    is_group   INTEGER NOT NULL DEFAULT 0,
    name       TEXT NULL,
    created_by INTEGER NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    avatar_url TEXT NULL,
    utente1    INTEGER NULL,
    utente2    INTEGER NULL
);

CREATE TABLE chat_members (
    chat_id   INTEGER NOT NULL,
    user_id   INTEGER NOT NULL,
    joined_at TEXT NOT NULL DEFAULT (datetime('now')),
    role      TEXT NOT NULL DEFAULT 'member',
    PRIMARY KEY (chat_id, user_id)
);

CREATE TABLE chat_typing_status (
    chat_id    INTEGER NOT NULL,
    user_id    INTEGER NOT NULL,
    status     TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (chat_id, user_id)
);

CREATE TABLE shared_files (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_user_id INTEGER NOT NULL,
    file_name     TEXT NOT NULL,
    mime_type     TEXT NOT NULL,
    size_bytes    INTEGER NOT NULL,
    source_url    TEXT NULL,
    storage_key   TEXT NULL UNIQUE,
    preview_type  TEXT NOT NULL DEFAULT 'file',
    preview_payload TEXT NULL,
    message_id    INTEGER NULL,
    bypassed_limit INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at    TEXT NULL,
    purge_after   TEXT NULL
);

CREATE TABLE messaggi (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    textmessage   TEXT NOT NULL,
    senderID      INTEGER NULL,
    reciverID     INTEGER NULL,
    chat_id       INTEGER NULL,
    file_attachment_id INTEGER NULL,
    timenow       TEXT NOT NULL DEFAULT (datetime('now')),
    is_certified  INTEGER NOT NULL DEFAULT 0,
    message_signature TEXT NULL,
    e2ee_metadata TEXT NULL,
    read_at       TEXT NULL,
    edited_at     TEXT NULL,
    deleted_at    TEXT NULL,
    deleted_by    INTEGER NULL,
    purge_after   TEXT NULL
);
