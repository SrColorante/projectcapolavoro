<?php
/**
 * db.php — Connessione PDO e helper di accesso ai dati.
 *
 * Nota rispetto alla versione precedente: qui NON viene eseguito alcun DDL.
 * Il vecchio file eseguiva sei ALTER/CREATE ad ogni singola richiesta (oltre a
 * essere una race condition tra processi concorrenti): le migrazioni stanno ora
 * in `migrate.php` e vanno eseguite una volta sola.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';

final class Db
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        Config::bootstrap();

        $options = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_STRINGIFY_FETCHES  => false,
        ];

        self::$pdo = new PDO(
            Config::dbDsn(),
            Config::dbUser(),
            Config::dbPassword(),
            $options
        );

        return self::$pdo;
    }

    /** Sovrascrive la connessione. Usato dai test con SQLite. */
    public static function setPdo(PDO $pdo): void
    {
        self::$pdo = $pdo;
    }

    public static function reset(): void
    {
        self::$pdo = null;
    }

    public static function fetchOne(string $sql, array $params = []): ?array
    {
        $stmt = self::pdo()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public static function fetchAll(string $sql, array $params = []): array
    {
        $stmt = self::pdo()->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public static function execute(string $sql, array $params = []): int
    {
        $stmt = self::pdo()->prepare($sql);
        $stmt->execute($params);
        return $stmt->rowCount();
    }

    public static function lastInsertId(): string
    {
        return strval(self::pdo()->lastInsertId());
    }

    public static function transaction(callable $work)
    {
        $pdo = self::pdo();
        $pdo->beginTransaction();
        try {
            $result = $work($pdo);
            $pdo->commit();
            return $result;
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    }

    /**
     * Verifica che la tabella esista. Usato dagli endpoint che devono dare un
     * errore pulito invece di un'eccezione PDO grezza.
     */
    public static function tableExists(string $table): bool
    {
        try {
            self::pdo()->query("SELECT 1 FROM `$table` LIMIT 1");
            return true;
        } catch (\PDOException $e) {
            return false;
        }
    }
}
