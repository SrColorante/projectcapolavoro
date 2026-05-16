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
    CONSTRAINT FK_SENDER FOREIGN KEY (senderID) REFERENCES utenti(IDutente),
    CONSTRAINT FK_RECEIVER FOREIGN KEY (reciverID) REFERENCES utenti(IDutente),
    CONSTRAINT CHK_SENDER_10_DIGITS CHECK (senderID BETWEEN 1000000000 AND 9999999999),
    CONSTRAINT CHK_RECEIVER_10_DIGITS CHECK (reciverID BETWEEN 1000000000 AND 9999999999)
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
