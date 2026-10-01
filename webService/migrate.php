<?php
/**
 * migrate.php — Applicazione delle migrazioni e manutenzione del database.
 *
 * USO
 *     php webService/migrate.php status       stato delle migrazioni
 *     php webService/migrate.php up          applica le migrazioni pendenti
 *     php webService/migrate.php retention   esegue la conservazione (cron)
 *     php webService/migrate.php purge       esegue le cancellazioni scadute
 *     php webService/migrate.php seed        utenti di esempio (solo sviluppo)
 *
 * PERCHE' ESISTE
 * La versione precedente eseguiva sei ALTER TABLE / CREATE TABLE dentro
 * db.php, quindi a OGNI richiesta HTTP: sei DDL per chiamata, piu' una race
 * condition fra richieste concorrenti che poteva far fallire una transazione
 * perche' un'altra richiesta aveva gia' modificato lo schema. Le migrazioni
 * vanno eseguite una volta, in modo controllato, da qui.
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    header('Content-Type: text/plain; charset=UTF-8');
    echo "Questo script si esegue solo da riga di comando.\n";
    exit(1);
}

require_once __DIR__ . '/lib/config.php';
require_once __DIR__ . '/lib/db.php';
require_once __DIR__ . '/lib/logging.php';
require_once __DIR__ . '/lib/privacy.php';
require_once __DIR__ . '/lib/retention.php';
require_once __DIR__ . '/lib/consent.php';
require_once __DIR__ . '/lib/upload.php';

Config::bootstrap();

$command = strval($argv[1] ?? 'status');

/**
 * Ogni migrazione e' una funzione che applica il DDL se necessario.
 * Devono essere idempotenti: eseguirele due volte non deve fallire.
 */
final class Migrations
{
    /**
     * @return array<int, array{id:string, title:string, fn:callable}>
     */
    public static function all(): array
    {
        return [
            [
                'id' => '001_utenti_sessioni',
                'title' => 'Tabella sessioni con token hashati',
                'fn' => [self::class, 'createSessions'],
            ],
            [
                'id' => '002_consensi',
                'title' => 'Registro dei consensi (Art. 7)',
                'fn' => [self::class, 'createConsensi'],
            ],
            [
                'id' => '003_audit_log',
                'title' => 'Registro di controllo pseudonimo (Art. 5(2))',
                'fn' => [self::class, 'createAuditLog'],
            ],
            [
                'id' => '004_rate_limit',
                'title' => 'Eventi per il rate limit',
                'fn' => [self::class, 'createRateLimit'],
            ],
            [
                'id' => '005_user_blocks',
                'title' => 'Blocchi fra utenti (Art. 21)',
                'fn' => [self::class, 'createUserBlocks'],
            ],
            [
                'id' => '006_utenti_gdpr',
                'title' => 'Colonne GDPR su utenti',
                'fn' => [self::class, 'alterUtenti'],
            ],
            [
                'id' => '007_messaggi_gdpr',
                'title' => 'Colonne conservazione e cancellazione su messaggi',
                'fn' => [self::class, 'alterMessaggi'],
            ],
            [
                'id' => '008_shared_files_storage',
                'title' => 'Chiave di archiviazione e cancellazione su shared_files',
                'fn' => [self::class, 'alterSharedFiles'],
            ],
            [
                'id' => '009_indexes',
                'title' => 'Indici per le query calcolate a ogni polling',
                'fn' => [self::class, 'createIndexes'],
            ],
            [
                'id' => '010_chat_created_at',
                'title' => 'Timestamp di creazione delle chat',
                'fn' => [self::class, 'alterChat'],
            ],
        ];
    }

    /** Applica una singola istruzione DDL, saltando se l'oggetto esiste gia'. */
    private static function ddl(string $sql, string $guard): void
    {
        $exists = Db::fetchOne($guard);
        if ($exists !== null) {
            return;
        }
        Db::pdo()->exec($sql);
    }

    private static function columnExists(string $table, string $column): bool
    {
        try {
            Db::pdo()->query("SELECT `$column` FROM `$table` LIMIT 1");
            return true;
        } catch (\PDOException $e) {
            return false;
        }
    }

    private static function indexExists(string $table, string $index): bool
    {
        try {
            $stmt = Db::pdo()->prepare(
                'SELECT 1 FROM information_schema.statistics
                 WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?'
            );
            $stmt->execute([$table, $index]);
            return $stmt->fetchColumn() !== false;
        } catch (\PDOException $e) {
            return false;
        }
    }

    private static function addColumn(string $table, string $column, string $definition): void
    {
        if (self::columnExists($table, $column)) {
            return;
        }
        Db::pdo()->exec("ALTER TABLE `$table` ADD COLUMN `$column` $definition");
    }

    public static function createSessions(): void
    {
        self::ddl(
            'CREATE TABLE IF NOT EXISTS utenti_sessioni (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                user_id BIGINT UNSIGNED NOT NULL,
                token_hash CHAR(64) BINARY NOT NULL,
                device_label VARCHAR(120) BINARY NULL,
                ip_hash CHAR(32) BINARY NULL,
                created_at DATETIME NOT NULL,
                last_used_at DATETIME NOT NULL,
                expires_at DATETIME NOT NULL,
                revoked_at DATETIME NULL,
                revoked_reason VARCHAR(40) BINARY NULL,
                UNIQUE KEY uniq_token_hash (token_hash),
                KEY idx_session_user (user_id, revoked_at),
                KEY idx_session_expiry (expires_at)
            ) ENGINE=InnoDB',
            "SELECT 1 FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name = 'utenti_sessioni'"
        );
    }

    public static function createConsensi(): void
    {
        self::ddl(
            "CREATE TABLE IF NOT EXISTS consensi (
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
                KEY idx_consent_pseudonym (subject_pseudonym)
            ) ENGINE=InnoDB",
            "SELECT 1 FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name = 'consensi'"
        );
    }

    public static function createAuditLog(): void
    {
        // Stringa PHP a doppi apici: l'ENUM contiene apici singoli che
        // chiuderebbero una stringa a apici singoli.
        $sql = "CREATE TABLE IF NOT EXISTS audit_log (
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
            ) ENGINE=InnoDB";

        self::ddl(
            $sql,
            "SELECT 1 FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name = 'audit_log'"
        );
    }

    public static function createRateLimit(): void
    {
        self::ddl(
            'CREATE TABLE IF NOT EXISTS rate_limit_events (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                bucket_key VARCHAR(160) BINARY NOT NULL,
                occurred_at DATETIME NOT NULL,
                KEY idx_rate_bucket (bucket_key, occurred_at),
                KEY idx_rate_time (occurred_at)
            ) ENGINE=InnoDB',
            "SELECT 1 FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name = 'rate_limit_events'"
        );
    }

    public static function createUserBlocks(): void
    {
        self::ddl(
            'CREATE TABLE IF NOT EXISTS user_blocks (
                blocker_id BIGINT UNSIGNED NOT NULL,
                blocked_id BIGINT UNSIGNED NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (blocker_id, blocked_id)
            ) ENGINE=InnoDB',
            "SELECT 1 FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name = 'user_blocks'"
        );
    }

    public static function alterUtenti(): void
    {
        if (!Db::tableExists('utenti')) {
            throw new RuntimeException(
                'La tabella `utenti` non esiste. Importa prima webService/chat.sql '
                . 'su un database vuoto, oppure usa un backup di uno schema gia\' esistente.'
            );
        }
        self::addColumn('utenti', 'processing_restricted', 'TINYINT(1) NOT NULL DEFAULT 0');
        self::addColumn('utenti', 'processing_restricted_at', 'DATETIME NULL');
        self::addColumn('utenti', 'deletion_requested_at', 'DATETIME NULL');
        self::addColumn('utenti', 'deletion_scheduled_for', 'DATETIME NULL');
        self::addColumn('utenti', 'deletion_reason', 'VARCHAR(255) BINARY NULL');
        self::addColumn('utenti', 'erased_at', 'DATETIME NULL');
        self::addColumn('utenti', 'data_retention_until', 'DATE NULL');
        self::addColumn('utenti', 'e2ee_key_algorithm', 'VARCHAR(32) BINARY NULL');
    }

    public static function alterMessaggi(): void
    {
        if (!Db::tableExists('messaggi')) {
            throw new RuntimeException('La tabella `messaggi` non esiste.');
        }
        self::addColumn('messaggi', 'read_at', 'DATETIME NULL');
        self::addColumn('messaggi', 'edited_at', 'DATETIME NULL');
        self::addColumn('messaggi', 'deleted_at', 'DATETIME NULL');
        self::addColumn('messaggi', 'deleted_by', 'BIGINT UNSIGNED NULL');
        self::addColumn('messaggi', 'purge_after', 'DATETIME NULL');
    }

    public static function alterSharedFiles(): void
    {
        if (!Db::tableExists('shared_files')) {
            throw new RuntimeException('La tabella `shared_files` non esiste.');
        }
        self::addColumn('shared_files', 'storage_key', 'VARCHAR(500) BINARY NULL');
        self::addColumn('shared_files', 'deleted_at', 'DATETIME NULL');
        self::addColumn('shared_files', 'purge_after', 'DATETIME NULL');

        // I file precedenti alla migrazione hanno solo source_url: si ricava la
        // chiave di archiviazione dal nome, cosi' restano scaricabili.
        if (!self::columnExists('shared_files', 'storage_key')) {
            return;
        }
        $legacy = Db::fetchAll(
            'SELECT id, source_url FROM shared_files
             WHERE storage_key IS NULL AND source_url IS NOT NULL LIMIT 5000'
        );
        foreach ($legacy as $row) {
            $key = ltrim(strval($row['source_url']), '/');
            if ($key === '') {
                continue;
            }
            Db::execute(
                'UPDATE shared_files SET storage_key = ? WHERE id = ?',
                [$key, $row['id']]
            );
        }
    }

    public static function createIndexes(): void
    {
        $indexes = [
            ['messaggi', 'idx_messaggi_chat', 'CREATE INDEX idx_messaggi_chat ON messaggi(chat_id, timenow)'],
            ['messaggi', 'idx_messaggi_sender', 'CREATE INDEX idx_messaggi_sender ON messaggi(senderID)'],
            ['messaggi', 'idx_messaggi_receiver', 'CREATE INDEX idx_messaggi_receiver ON messaggi(reciverID, status)'],
            ['messaggi', 'idx_messaggi_purge', 'CREATE INDEX idx_messaggi_purge ON messaggi(purge_after)'],
            ['chat', 'idx_chat_utente1', 'CREATE INDEX idx_chat_utente1 ON chat(utente1)'],
            ['chat', 'idx_chat_utente2', 'CREATE INDEX idx_chat_utente2 ON chat(utente2)'],
            ['chat_members', 'idx_chatmember_user', 'CREATE INDEX idx_chatmember_user ON chat_members(user_id, chat_id)'],
            ['shared_files', 'idx_files_owner', 'CREATE INDEX idx_files_owner ON shared_files(owner_user_id, created_at)'],
            ['shared_files', 'idx_files_purge', 'CREATE INDEX idx_files_purge ON shared_files(purge_after)'],
        ];

        foreach ($indexes as [$table, $name, $sql]) {
            if (!Db::tableExists($table) || self::indexExists($table, $name)) {
                continue;
            }
            try {
                Db::pdo()->exec($sql);
            } catch (\PDOException $e) {
                // Un indice gia' presente come chiave univoca non e' un errore.
                echo "  (indice $name non creato: gia' presente)\n";
            }
        }
    }

    public static function alterChat(): void
    {
        if (!Db::tableExists('chat')) {
            throw new RuntimeException('La tabella `chat` non esiste.');
        }
        self::addColumn('chat', 'created_at', 'DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP');
    }

    public static function ensureMigrationTable(): void
    {
        Db::pdo()->exec(
            'CREATE TABLE IF NOT EXISTS schema_migrations (
                id VARCHAR(64) PRIMARY KEY,
                title VARCHAR(160) NOT NULL,
                applied_at DATETIME NOT NULL
            ) ENGINE=InnoDB'
        );
    }

    public static function applied(): array
    {
        self::ensureMigrationTable();
        $rows = Db::fetchAll('SELECT id, applied_at FROM schema_migrations');
        $map = [];
        foreach ($rows as $row) {
            $map[strval($row['id'])] = strval($row['applied_at']);
        }
        return $map;
    }

    public static function markApplied(string $id, string $title): void
    {
        Db::execute(
            'INSERT INTO schema_migrations (id, title, applied_at) VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE title = VALUES(title)',
            [$id, $title, gmdate('Y-m-d H:i:s')]
        );
    }
}

function cmd_status(): void
{
    $applied = Migrations::applied();
    $pending = 0;
    echo "Migrazioni:\n";
    foreach (Migrations::all() as $migration) {
        $isApplied = isset($applied[$migration['id']]);
        $pending += $isApplied ? 0 : 1;
        printf(
            "  [%s] %-28s %s%s\n",
            $isApplied ? 'ok' : '--',
            $migration['id'],
            $migration['title'],
            $isApplied ? '  (' . $applied[$migration['id']] . ')' : ''
        );
    }
    echo $pending === 0
        ? "\nSchema aggiornato.\n"
        : "\n$pending migrazione/i pendente/i. Esegui: php migrate.php up\n";
}

function cmd_up(): void
{
    Migrations::ensureMigrationTable();
    $applied = Migrations::applied();
    $count = 0;

    foreach (Migrations::all() as $migration) {
        if (isset($applied[$migration['id']])) {
            continue;
        }
        echo "Applico {$migration['id']} — {$migration['title']}\n";
        try {
            $migration['fn']();
        } catch (\Throwable $e) {
            fwrite(STDERR, "  FALLITO: " . $e->getMessage() . "\n");
            exit(1);
        }
        Migrations::markApplied($migration['id'], $migration['title']);
        $count++;
    }

    echo $count === 0
        ? "Nessuna migrazione pendente.\n"
        : "Applicate $count migrazione/i.\n";
    echo "Versione informativa privacy: " . Consent::policyVersion() . "\n";
}

function cmd_retention(array $args): void
{
    $dryRun = in_array('--dry-run', $args, true);
    $summary = Retention::run($dryRun);
    echo ($dryRun ? "[dry run] " : '') . "Conservazione eseguita:\n";
    foreach ($summary as $key => $value) {
        printf("  %-28s %s\n", $key, var_export($value, true));
    }
}

function cmd_purge(): void
{
    $result = Privacy::purgeDueErasures();
    echo "Cancellazioni definitive: {$result['processed']}\n";
    foreach ($result['details'] as $entry) {
        echo '  soggetto ' . $entry['subject'] . "\n";
    }
}

function cmd_seed(): void
{
    $demoPassword = 'password';
    $users = [
        [3391234567, 'Mario', 'mario.rossi', 'mario.rossi@test.example'],
        [3391234568, 'Luca', 'luca.b', 'luca.bianchi@test.example'],
        [3391234569, 'Giulia', 'giulia.v', 'giulia.verdi@test.example'],
    ];

    foreach ($users as [$id, $name, $nickname, $email]) {
        $exists = Db::fetchOne('SELECT 1 AS ok FROM utenti WHERE IDutente = ?', [$id]);
        if ($exists !== null) {
            echo "  $id gia' presente\n";
            continue;
        }
        Db::execute(
            'INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash, dataCreazione)
             VALUES (?, ?, ?, ?, ?, ?, CURDATE())',
            [$id, $name, 'Demo', $nickname, $email, password_hash($demoPassword, PASSWORD_DEFAULT)]
        );
        Consent::record(strval($id), 'privacy_policy', true, 'seed');
        Consent::record(strval($id), 'data_processing', true, 'seed');
        echo "  creato $id ($name)\n";
    }

    echo "\nAttenzione: password di esempio debole ($demoPassword).\n";
    echo "Non usare questi account su un'istanza reale.\n";
}

try {
    switch ($command) {
        case 'up':
            cmd_up();
            break;
        case 'status':
            cmd_status();
            break;
        case 'retention':
            cmd_retention(array_slice($argv, 2));
            break;
        case 'purge':
            cmd_purge();
            break;
        case 'seed':
            cmd_seed();
            break;
        default:
            fwrite(STDERR, "Comando sconosciuto: $command\n");
            fwrite(
                STDERR,
                "Uso: php migrate.php [status|up|retention|purge|seed]\n"
            );
            exit(1);
    }
} catch (Throwable $e) {
    fwrite(STDERR, 'Errore: ' . $e->getMessage() . "\n");
    exit(1);
}
