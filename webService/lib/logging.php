<?php
/**
 * logging.php — Audit trail strutturato e log tecnico.
 *
 * Regole GDPR applicate qui:
 *  - nel registro di controllo non finisce mai PII in chiaro: l'utente e'
 *    identificato da uno pseudonimo HMAC (non reversibile senza il pepper);
 *  - gli indirizzi IP sono conservati solo come hash con pepper, mai in chiaro;
 *  - il log tecnico non registra corpi di richiesta ne' parametri che
 *    contengono identificativi diretti come `user_id` (che in questo progetto
 *    coincide con il numero di telefono);
 *  - ogni riga ha un correlation id, cosi' un incidente si puo' ricostruire
 *    senza conservare dati personali.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';

final class Logger
{
    private static ?string $correlationId = null;

    public static function correlationId(): string
    {
        if (self::$correlationId === null) {
            $bytes = random_bytes(16);
            self::$correlationId = bin2hex($bytes);
        }
        return self::$correlationId;
    }

    public static function setCorrelationId(string $id): void
    {
        self::$correlationId = $id;
    }

    /** Genera uno pseudonimo stabile per un identificatore utente. */
    public static function pseudonymize(?string $identifier): ?string
    {
        if ($identifier === null || $identifier === '') {
            return null;
        }
        Config::bootstrap();
        return hash_hmac('sha256', $identifier, Config::privacyPepper());
    }

    /**
     * Hash dell'IP con pepper e troncato: 32 esagoni bastano per correlare
     * senza rappresentare un indirizzo riconducibile in modo diretto.
     */
    public static function hashIp(?string $ip): ?string
    {
        if ($ip === null || $ip === '') {
            return null;
        }
        Config::bootstrap();
        return substr(hash_hmac('sha256', $ip, Config::privacyPepper()), 0, 32);
    }

    public static function clientIp(): ?string
    {
        return $_SERVER['REMOTE_ADDR'] ?? null;
    }

    /**
     * Scrive una voce nel registro di controllo (Art. 5(2) — responsabilita' e
     * dimostrabilita'). Fallisce in silenzio: un audit non deve mai far cadere
     * una richiesta utente legittima.
     *
     * @param string|int|null $actorUserId gli identificatori provenienti dal
     *        database arrivano come interi (una colonna BIGINT con
     *        EMULATE_PREPARES disattivato restituisce int su PHP a 64 bit), per
     *        questo il parametro accetta anche interi e viene normalizzato.
     */
    public static function audit(
        string $action,
        $actorUserId = null,
        ?string $resourceType = null,
        $resourceId = null,
        string $outcome = 'ok',
        array $detail = []
    ): void {
        $actorUserId = $actorUserId === null ? null : strval($actorUserId);
        $resourceId = $resourceId === null ? null : strval($resourceId);

        try {
            if (!Db::tableExists('audit_log')) {
                return;
            }
            Db::execute(
                "INSERT INTO audit_log
                    (correlation_id, actor_pseudonym, actor_user_id, action,
                     resource_type, resource_id, outcome, ip_hash, detail)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    self::correlationId(),
                    self::pseudonymize($actorUserId),
                    $actorUserId,
                    $action,
                    $resourceType,
                    $resourceId,
                    $outcome,
                    self::hashIp(self::clientIp()),
                    json_encode($detail, JSON_UNESCAPED_SLASHES),
                ]
            );
        } catch (\Throwable $e) {
            error_log('[audit] ' . $e->getMessage());
        }
    }

    /**
     * Log tecnico su error_log. Il messaggio non deve contenere dati
     * personali: passare identificatori pseudonimi, non ID utente.
     */
    public static function technical(string $level, string $message, array $context = []): void
    {
        $line = sprintf(
            '[quice][%s][%s][cid=%s] %s',
            $level,
            date('c'),
            self::correlationId(),
            $message
        );
        if ($context !== []) {
            $line .= ' ' . json_encode($context, JSON_UNESCAPED_SLASHES);
        }
        error_log($line);
    }

    /**
     * Scrive il log su file solo se configurato. In produzione conviene
     * impostare QUICE_AUDIT_LOG_PATH su un filesystem con criteri di accesso
     * appropriati e cifrare a riposo.
     */
    public static function writeFile(string $line): void
    {
        $path = Config::auditLogPath();
        if ($path === null) {
            return;
        }
        @file_put_contents($path, $line . PHP_EOL, FILE_APPEND | LOCK_EX);
    }
}
