-- =====================================================================
--  chat.sql — Schema di Quice (MySQL 8 / MariaDB 10.x)
--
--  IMPORTAZIONE
--      mysql -u root -p < webService/chat.sql
--
--  NOTA SULLE DIPENDENZE CIRCOLARI
--  `messaggi` referenzia `shared_files` (il messaggio ha un allegato) e
--  `shared_files` referenzia `messaggi` (il file sa a quale messaggio
--  appartiene). MySQL non risolve un riferimento a una tabella non ancora
--  creata e fallisce con errno 150. La versione precedente di questo file
--  creava `messaggi` prima di `shared_files`: l'intero schema NON era
--  importabile su un database vuoto, quindi le installazioni documentate
--  non potevano funzionare. Qui si spezza il ciclo: prima la tabella senza
--  vincolo, poi l'ALTER che aggiunge il vincolo.
--
--  I dati di esempio in fondo servono solo per lo sviluppo. Non importare
--  questo file su un'istallazione reale: usa migrate.php (vedi sotto).
-- =====================================================================

DROP DATABASE IF EXISTS chatProject;
CREATE DATABASE chatProject CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE chatProject;

-- ---------------------------------------------------------------------
--  utenti
--  L'identificativo coincide con il numero di telefono: 10 cifre.
--  Colonne aggiunte per il GDPR: limitazione del trattamento (Art. 18),
--  cancellazione (Art. 17) e scadenza dei dati degli account ospite.
-- ---------------------------------------------------------------------
CREATE TABLE utenti (
    IDutente BIGINT UNSIGNED PRIMARY KEY,
    nome VARCHAR(20) BINARY NOT NULL,
    cognome VARCHAR(100) BINARY NOT NULL,
    nickname VARCHAR(50) BINARY NOT NULL,
    email VARCHAR(120) BINARY NULL UNIQUE,
    password_hash VARCHAR(255) BINARY NOT NULL,
    dataCreazione DATE NOT NULL,
    is_guest TINYINT(1) NOT NULL DEFAULT 0,
    preferred_language VARCHAR(10) BINARY NOT NULL DEFAULT 'en',
    profile_bio VARCHAR(500) BINARY NULL,
    profile_photo_url VARCHAR(500) BINARY NULL,
    profile_audio_url VARCHAR(500) BINARY NULL,
    profile_audio_duration_seconds DECIMAL(4,2) NULL,
    e2ee_public_key TEXT BINARY NULL,
    e2ee_key_algorithm VARCHAR(32) BINARY NULL,
    two_factor_enabled TINYINT(1) NOT NULL DEFAULT 0,
    two_factor_channel ENUM('email', 'phone') NULL,
    two_factor_destination VARCHAR(190) BINARY NULL,
    two_factor_verified_at DATETIME NULL,
    pec_certified_at DATETIME NULL,

    -- GDPR ------------------------------------------------------------
    -- Art. 18: limitazione del trattamento. Blocca nuovi dati in uscita ma
    -- mantiene accesso, rettifica e portabilita'.
    processing_restricted TINYINT(1) NOT NULL DEFAULT 0,
    processing_restricted_at DATETIME NULL,
    -- Art. 17: cancellazione in due tempi. `deletion_requested_at` e' la
    -- richiesta, `deletion_scheduled_for` la data in cui diventa definitiva,
    -- `erased_at` la data della cancellazione effettiva.
    deletion_requested_at DATETIME NULL,
    deletion_scheduled_for DATETIME NULL,
    deletion_reason VARCHAR(255) BINARY NULL,
    erased_at DATETIME NULL,
    -- Scadenza dei dati per gli account ospite (minimizzazione, Art. 5(1)(e)).
    data_retention_until DATE NULL,

    CONSTRAINT CHK_IDUTENTE_PHONE CHECK (IDutente BETWEEN 1000000000 AND 9999999999)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Sessioni: hash SHA-256 del token, mai il token stesso.
--  La colonna token_hash e' UNIQUE perche' e' la chiave di ricerca a ogni
--  richiesta: senza indice ogni chiamata API farebbe una scansione.
-- ---------------------------------------------------------------------
CREATE TABLE utenti_sessioni (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    token_hash CHAR(64) BINARY NOT NULL,
    device_label VARCHAR(120) BINARY NULL,
    -- IP mai in chiaro: solo hash con pepper (Art. 5(1)(c)).
    ip_hash CHAR(32) BINARY NULL,
    created_at DATETIME NOT NULL,
    last_used_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME NULL,
    revoked_reason VARCHAR(40) BINARY NULL,
    UNIQUE KEY uniq_token_hash (token_hash),
    KEY idx_session_user (user_id, revoked_at),
    KEY idx_session_expiry (expires_at),
    CONSTRAINT FK_SESSION_USER FOREIGN KEY (user_id)
        REFERENCES utenti(IDutente) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Registro dei consensi (Art. 7).
--  Sono append-only: ogni decisione e' una riga nuova, cosi' la prova
--  storica resta intatta anche se l'utente revoca.
--  `user_id` diventa NULL dopo la cancellazione dell'account: la prova
--  della liceita' del trattamento sopravvive pseudonima.
-- ---------------------------------------------------------------------
CREATE TABLE consensi (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NULL,
    subject_pseudonym CHAR(64) BINARY NULL,
    tipo ENUM('privacy_policy', 'data_processing', 'translation_ondevice',
              'lan_peer_transfer', 'voice_bio', 'diagnostics') NOT NULL,
    granted TINYINT(1) NOT NULL,
    policy_version VARCHAR(20) BINARY NOT NULL,
    source VARCHAR(20) BINARY NOT NULL DEFAULT 'unknown',
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    withdrawn_at DATETIME NULL,
    ip_hash CHAR(32) BINARY NULL,
    KEY idx_consent_user (user_id, recorded_at),
    KEY idx_consent_pseudonym (subject_pseudonym),
    CONSTRAINT FK_CONSENT_USER FOREIGN KEY (user_id)
        REFERENCES utenti(IDutente) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Registro di controllo (Art. 5(2) responsabilita' e dimostrabilita').
--  Nessuna PII in chiaro: l'attore e' un pseudonimo HMAC e l'IP e' un hash.
--  `actor_user_id` viene azzerato alla cancellazione, mantenendo la
--  dimostrabilita' senza conservare l'identificativo diretto.
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    correlation_id CHAR(32) BINARY NOT NULL,
    actor_pseudonym CHAR(64) BINARY NULL,
    actor_user_id BIGINT UNSIGNED NULL,
    action VARCHAR(60) BINARY NOT NULL,
    resource_type VARCHAR(40) BINARY NULL,
    resource_id VARCHAR(64) BINARY NULL,
    outcome ENUM('ok', 'denied', 'error') NOT NULL DEFAULT 'ok',
    ip_hash CHAR(32) BINARY NULL,
    detail TEXT BINARY NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_audit_actor (actor_user_id, created_at),
    KEY idx_audit_pseudonym (actor_pseudonym, created_at),
    KEY idx_audit_created (created_at),
    KEY idx_audit_correlation (correlation_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Eventi per il rate limit a finestra scorrevole.
--  Nessun identificativo diretto nella chiave: gia' pseudonimizzata.
-- ---------------------------------------------------------------------
CREATE TABLE rate_limit_events (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bucket_key VARCHAR(160) BINARY NOT NULL,
    occurred_at DATETIME NOT NULL,
    KEY idx_rate_bucket (bucket_key, occurred_at),
    KEY idx_rate_time (occurred_at)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  Blocchi fra utenti (Art. 21 — diritto di opposizione).
--  Entrambi i lati sono in ON DELETE CASCADE: se uno dei due cancelli
--  l'account il blocco scompare da solo, senza dati orfani.
-- ---------------------------------------------------------------------
CREATE TABLE user_blocks (
    blocker_id BIGINT UNSIGNED NOT NULL,
    blocked_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT FK_BLOCK_BLOCKER FOREIGN KEY (blocker_id)
        REFERENCES utenti(IDutente) ON DELETE CASCADE,
    CONSTRAINT FK_BLOCK_BLOCKED FOREIGN KEY (blocked_id)
        REFERENCES utenti(IDutente) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  chat
-- ---------------------------------------------------------------------
CREATE TABLE chat (
    IDchat BIGINT UNSIGNED PRIMARY KEY,
    is_group TINYINT(1) NOT NULL DEFAULT 0,
    name VARCHAR(100) BINARY NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    avatar_url VARCHAR(500) BINARY NULL,
    utente1 BIGINT UNSIGNED NULL,
    utente2 BIGINT UNSIGNED NULL,
    -- Le chat di gruppo non hanno utente1/utente2 valorizzati: il vincolo
    -- CHECK impedisce che i due campi restino popolati insieme, cosa che
    -- prima rendeva ambigue le query di appartenenza.
    CONSTRAINT FK_UTENTE1 FOREIGN KEY (utente1) REFERENCES utenti(IDutente),
    CONSTRAINT FK_UTENTE2 FOREIGN KEY (utente2) REFERENCES utenti(IDutente),
    CONSTRAINT FK_CHAT_CREATOR FOREIGN KEY (created_by) REFERENCES utenti(IDutente),
    CONSTRAINT CHK_IDCHAT_10_DIGITS CHECK (IDchat BETWEEN 1000000000 AND 9999999999),
    -- Indice per la query di elenco, che filtra su utente1/utente2 a ogni poll.
    KEY idx_chat_utente1 (utente1),
    KEY idx_chat_utente2 (utente2)
) ENGINE=InnoDB;

CREATE TABLE chat_members (
    chat_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    role ENUM('admin', 'member') NOT NULL DEFAULT 'member',
    PRIMARY KEY (chat_id, user_id),
    KEY idx_chatmember_user (user_id, chat_id),
    CONSTRAINT FK_CM_CHAT FOREIGN KEY (chat_id) REFERENCES chat(IDchat) ON DELETE CASCADE,
    CONSTRAINT FK_CM_USER FOREIGN KEY (user_id) REFERENCES utenti(IDutente) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE chat_typing_status (
    chat_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    status VARCHAR(50) NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (chat_id, user_id),
    CONSTRAINT FK_CTS_CHAT FOREIGN KEY (chat_id) REFERENCES chat(IDchat) ON DELETE CASCADE,
    CONSTRAINT FK_CTS_USER FOREIGN KEY (user_id) REFERENCES utenti(IDutente) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  shared_files — creata PRIMA di messaggi (vedi nota in testa al file).
--  `storage_key` e' il percorso relativo sotto uploads/. Non contiene il
--  nome originale dell'utente: quello resta in `file_name`, come solo
--  metadato. Il nome del file su disco e' casuale (random_bytes) e non
--  piu' uniqid(), che e' prevedibile.
-- ---------------------------------------------------------------------
CREATE TABLE shared_files (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    owner_user_id BIGINT UNSIGNED NOT NULL,
    file_name VARCHAR(255) BINARY NOT NULL,
    mime_type VARCHAR(120) BINARY NOT NULL,
    size_bytes BIGINT UNSIGNED NOT NULL,
    source_url VARCHAR(1000) BINARY NULL,
    storage_key VARCHAR(500) BINARY NULL,
    preview_type ENUM('audio', 'image', 'video', 'gif', 'pdf', 'link', 'file') NOT NULL DEFAULT 'file',
    preview_payload JSON NULL,
    message_id INT UNSIGNED NULL,
    bypassed_limit TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- GDPR: cancellazione graduale e termine di conservazione.
    deleted_at DATETIME NULL,
    purge_after DATETIME NULL,
    UNIQUE KEY uniq_storage_key (storage_key),
    KEY idx_files_owner (owner_user_id, created_at),
    KEY idx_files_purge (purge_after),
    CONSTRAINT FK_SHARED_FILE_OWNER FOREIGN KEY (owner_user_id)
        REFERENCES utenti(IDutente) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  messaggi
--  `read_at`, `edited_at`, `deleted_at` e `purge_after` sono le colonne che
--  rendono possibile onorare Art. 5(1)(e) e il diritto di rettifica/cancellazione.
-- ---------------------------------------------------------------------
CREATE TABLE messaggi (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    textmessage VARCHAR(15000) NOT NULL,
    senderID BIGINT UNSIGNED,
    reciverID BIGINT UNSIGNED NULL,
    chat_id BIGINT UNSIGNED NULL,
    file_attachment_id BIGINT UNSIGNED NULL,
    timenow DATETIME NOT NULL,
    is_certified TINYINT(1) NOT NULL DEFAULT 0,
    message_signature TEXT BINARY NULL,
    e2ee_metadata JSON NULL,
    read_at DATETIME NULL,
    edited_at DATETIME NULL,
    deleted_at DATETIME NULL,
    deleted_by BIGINT UNSIGNED NULL,
    purge_after DATETIME NULL,
    -- Copre il percorso legacy (messaggi con chat_id NULL e reciverID
    -- valorizzato) e quello nuovo, interrogati ad ogni polling.
    KEY idx_messaggi_chat (chat_id, timenow),
    KEY idx_messaggi_sender (senderID),
    KEY idx_messaggi_receiver (reciverID, status),
    KEY idx_messaggi_purge (purge_after),
    CONSTRAINT FK_SENDER FOREIGN KEY (senderID) REFERENCES utenti(IDutente),
    CONSTRAINT FK_RECEIVER FOREIGN KEY (reciverID) REFERENCES utenti(IDutente),
    CONSTRAINT FK_MSG_CHAT FOREIGN KEY (chat_id) REFERENCES chat(IDchat) ON DELETE CASCADE,
    CONSTRAINT FK_MSG_FILE FOREIGN KEY (file_attachment_id) REFERENCES shared_files(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Chiusura del ciclo di dipendenze: ora `messaggi` esiste.
ALTER TABLE shared_files
    ADD CONSTRAINT FK_SF_MESSAGE FOREIGN KEY (message_id)
        REFERENCES messaggi(id) ON DELETE SET NULL;

CREATE TABLE otp_two_factor_codes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userID BIGINT UNSIGNED NOT NULL,
    channel ENUM('email', 'phone') NOT NULL,
    destination VARCHAR(190) BINARY NOT NULL,
    otp_hash VARCHAR(255) BINARY NOT NULL,
    purpose ENUM('login', 'password_recovery', 'pec_certification') NOT NULL,
    expires_at DATETIME NOT NULL,
    consumed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_otp_user (userID, expires_at),
    CONSTRAINT FK_OTP_USER FOREIGN KEY (userID) REFERENCES utenti(IDutente) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =====================================================================
--  DATI DI ESEMPIO — SOLO PER SVILUPPO
--  Non usare questi account su un'istanza reale. Importa le migrazioni con
--  `php webService/migrate.php` invece di questo file.
--  Password degli utenti di esempio: "password" (bcrypt, hash qui sotto).
-- =====================================================================
INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash, dataCreazione) VALUES
    (3391234567, 'Mario', 'Rossi',  'mario.rossi', 'mario.rossi@test.example', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', '2024-01-10'),
    (3391234568, 'Luca', 'Bianchi', 'luca.b',      'luca.bianchi@test.example', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', '2024-02-05'),
    (3391234569, 'Giulia', 'Verdi',  'giulia.v',    'giulia.verdi@test.example', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', '2024-03-02');

INSERT INTO chat (IDchat, utente1, utente2) VALUES
    (2345678901, 3391234567, 3391234568),
    (2345678902, 3391234567, 3391234569);

INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id, timenow) VALUES
    ('Ciao Luca! Hai visto il nuovo progetto?', 3391234567, 3391234568, 2345678901, '2024-04-01 09:10:00'),
    ('Sì, l''ho appena aperto. È davvero interessante!', 3391234568, 3391234567, 2345678901, '2024-04-01 09:12:00'),
    ('Giulia, ti va una call oggi pomeriggio?', 3391234567, 3391234569, 2345678902, '2024-04-01 10:30:00'),
    ('Certo! Dopo le 15 va bene.', 3391234569, 3391234567, 2345678902, '2024-04-01 10:33:00');
