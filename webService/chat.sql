DROP DATABASE IF EXISTS chatProject;
CREATE DATABASE chatProject;
USE chatProject;

CREATE TABLE utenti (
    IDutente BIGINT UNSIGNED PRIMARY KEY,
    nome VARCHAR(20) BINARY NOT NULL,
    cognome VARCHAR(100) BINARY NOT NULL,
    nickname VARCHAR(50) BINARY NOT NULL,
    email VARCHAR(120) BINARY NOT NULL UNIQUE,
    password_hash VARCHAR(255) BINARY NOT NULL,
    dataCreazione DATE NOT NULL,
    is_guest TINYINT(1) NOT NULL DEFAULT 0,
    preferred_language VARCHAR(10) BINARY NOT NULL DEFAULT 'en',
    profile_bio VARCHAR(500) BINARY NULL,
    profile_photo_url VARCHAR(500) BINARY NULL,
    profile_audio_url VARCHAR(500) BINARY NULL,
    profile_audio_duration_seconds DECIMAL(4,2) NULL,
    e2ee_public_key TEXT BINARY NULL,
    two_factor_enabled TINYINT(1) NOT NULL DEFAULT 0,
    two_factor_channel ENUM('email', 'phone') NULL,
    two_factor_destination VARCHAR(190) BINARY NULL,
    two_factor_verified_at DATETIME NULL,
    pec_certified_at DATETIME NULL,
    CONSTRAINT CHK_IDUTENTE_10_DIGITS CHECK (IDutente BETWEEN 1000000000 AND 9999999999)
);

CREATE TABLE chat (
    IDchat BIGINT UNSIGNED PRIMARY KEY,
    utente1 BIGINT UNSIGNED,
    utente2 BIGINT UNSIGNED,
    CONSTRAINT FK_UTENTE1 FOREIGN KEY (utente1) REFERENCES utenti(IDutente),
    CONSTRAINT FK_UTENTE2 FOREIGN KEY (utente2) REFERENCES utenti(IDutente),
    CONSTRAINT CHK_IDCHAT_10_DIGITS CHECK (IDchat BETWEEN 1000000000 AND 9999999999)
);

CREATE TABLE messaggi (
    id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    textmessage VARCHAR(15000) NOT NULL,
    senderID BIGINT UNSIGNED,
    reciverID BIGINT UNSIGNED,
    timenow DATETIME NOT NULL,
    is_certified TINYINT(1) NOT NULL DEFAULT 0,
    message_signature TEXT BINARY NULL,
    e2ee_metadata JSON NULL,
    CONSTRAINT FK_SENDER FOREIGN KEY (senderID) REFERENCES utenti(IDutente),
    CONSTRAINT FK_RECEIVER FOREIGN KEY (reciverID) REFERENCES utenti(IDutente),
    CONSTRAINT CHK_SENDER_10_DIGITS CHECK (senderID BETWEEN 1000000000 AND 9999999999),
    CONSTRAINT CHK_RECEIVER_10_DIGITS CHECK (reciverID BETWEEN 1000000000 AND 9999999999)
);

CREATE TABLE otp_two_factor_codes (
    id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    userID BIGINT UNSIGNED NOT NULL,
    channel ENUM('email', 'phone') NOT NULL,
    destination VARCHAR(190) BINARY NOT NULL,
    otp_hash VARCHAR(255) BINARY NOT NULL,
    purpose ENUM('login', 'password_recovery', 'pec_certification') NOT NULL,
    expires_at DATETIME NOT NULL,
    consumed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_OTP_USER FOREIGN KEY (userID) REFERENCES utenti(IDutente)
);

CREATE TABLE shared_files (
    id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    owner_user_id BIGINT UNSIGNED NOT NULL,
    file_name VARCHAR(255) BINARY NOT NULL,
    mime_type VARCHAR(120) BINARY NOT NULL,
    size_bytes BIGINT UNSIGNED NOT NULL,
    source_url VARCHAR(1000) BINARY NULL,
    preview_type ENUM('audio', 'image', 'video', 'gif', 'pdf', 'link', 'file') NOT NULL DEFAULT 'file',
    preview_payload JSON NULL,
    bypassed_limit TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_SHARED_FILE_OWNER FOREIGN KEY (owner_user_id) REFERENCES utenti(IDutente)
);

INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash, dataCreazione) VALUES
    (1234567890, 'Mario', 'Rossi', 'mario.rossi', 'mario.rossi@test.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', '2024-01-10'),
    (1234567891, 'Luca', 'Bianchi', 'luca.b', 'luca.bianchi@test.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', '2024-02-05'),
    (1234567892, 'Giulia', 'Verdi', 'giulia.v', 'giulia.verdi@test.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', '2024-03-02');

INSERT INTO chat (IDchat, utente1, utente2) VALUES
    (2345678901, 1234567890, 1234567891),
    (2345678902, 1234567890, 1234567892);

INSERT INTO messaggi (textmessage, senderID, reciverID, timenow) VALUES
    ('Ciao Luca! Hai visto il nuovo progetto?', 1234567890, 1234567891, '2024-04-01 09:10:00'),
    ('Sì, l''ho appena aperto. È davvero interessante!', 1234567891, 1234567890, '2024-04-01 09:12:00'),
    ('Giulia, ti va una call oggi pomeriggio?', 1234567890, 1234567892, '2024-04-01 10:30:00'),
    ('Certo! Dopo le 15 va bene.', 1234567892, 1234567890, '2024-04-01 10:33:00');
