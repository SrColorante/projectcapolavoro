<?php
$host = '127.0.0.1';
$db   = 'chatProject';
$user = 'root'; // Cambia con il tuo utente
$pass = '';     // Cambia con la tua password
$charset = 'utf8mb4';

$dsn = "mysql:host=$host;dbname=$db;charset=$charset";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
];

try {
    $pdo = new PDO($dsn, $user, $pass, $options);

    // Self-healing database migrations:
    // 1. Ensure email column is nullable in 'utenti' table
    try {
        $pdo->exec("ALTER TABLE utenti MODIFY COLUMN email VARCHAR(120) BINARY NULL UNIQUE");
    } catch (\Exception $e) {
        // Table may not exist yet or alter failed, ignore
    }

    // 2. Remove old 10-digit constraint on utenti table
    try {
        $pdo->exec("ALTER TABLE utenti DROP CONSTRAINT CHK_IDUTENTE_10_DIGITS");
    } catch (\Exception $e) {
        // Constraint may not exist, ignore
    }

    // 3. Ensure CHK_IDUTENTE_PHONE exists or modify the check
    try {
        $pdo->exec("ALTER TABLE utenti ADD CONSTRAINT CHK_IDUTENTE_PHONE CHECK (IDutente BETWEEN 10000000 AND 999999999999999)");
    } catch (\Exception $e) {
        // Constraint may already exist or fail, ignore
    }

    // 4. Remove old constraints on messaggi table
    try {
        $pdo->exec("ALTER TABLE messaggi DROP CONSTRAINT CHK_SENDER_10_DIGITS");
    } catch (\Exception $e) {
        // Constraint may not exist, ignore
    }
    try {
        $pdo->exec("ALTER TABLE messaggi DROP CONSTRAINT CHK_RECEIVER_10_DIGITS");
    } catch (\Exception $e) {
        // Constraint may not exist, ignore
    }

    // 5. Ensure status column in messaggi
    try {
        $pdo->exec("ALTER TABLE messaggi ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'sent'");
    } catch (\Exception $e) {
        // Column may already exist, ignore
    }

    // 6. Create chat_typing_status table
    try {
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS chat_typing_status (
                chat_id BIGINT UNSIGNED NOT NULL,
                user_id BIGINT UNSIGNED NOT NULL,
                status VARCHAR(50) NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (chat_id, user_id),
                CONSTRAINT FK_CTS_CHAT FOREIGN KEY (chat_id) REFERENCES chat(IDchat) ON DELETE CASCADE,
                CONSTRAINT FK_CTS_USER FOREIGN KEY (user_id) REFERENCES utenti(IDutente) ON DELETE CASCADE
            )
        ");
    } catch (\Exception $e) {
        // Table or constraints may already exist, ignore
    }

} catch (\PDOException $e) {
    throw new \PDOException($e->getMessage(), (int)$e->getCode());
}