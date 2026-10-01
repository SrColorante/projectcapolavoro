<?php
/**
 * auth.php — Autenticazione a token di sessione.
 *
 * PRIMA (vulnerabile): l'identita' dell'utente arrivava da `?user_id=` nella
 * query string e l'unica "prova" era una firma HMAC con un segreto unico
 * uguale per tutti, presente nel repository pubblico. Chiunque poteva quindi
 * leggere e scrivere i dati di qualunque utente semplicemente indovinando un
 * numero di telefono.
 *
 * ADESSO: l'identita' deriva esclusivamente da un token Bearer opaco,
 * emesso solo a login/register, memorizzato nel database solo come SHA-256 e
 * collegato a un utente. Il token viaggia nell'header `Authorization`, non
 * nella query string, quindi non finisce nei log di accesso ne' nella cronologia.
 *
 * Il token e' in chiaro solo sul dispositivo dell'utente e solo al momento
 * dell'emissione: il server non e' in grado di recuperarlo dai dati conservati.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/logging.php';
require_once __DIR__ . '/http.php';

final class Auth
{
    /** Il numero di telefono e' l'identificativo: esattamente 10 cifre. */
    public static function isValidUserId($value): bool
    {
        return is_scalar($value) && preg_match('/^\d{10}$/', strval($value)) === 1;
    }

    public static function hashToken(string $token): string
    {
        return hash('sha256', $token);
    }

    /**
     * Emette un token di sessione. Restituisce il token in chiaro, da
     * consegnare al client una sola volta.
     */
    public static function issueToken(
        string $userId,
        ?string $deviceLabel = null,
        ?string $ip = null
    ): array {
        $token = bin2hex(random_bytes(32));
        $now = time();
        $ttl = Config::sessionTtlSeconds();

        Db::execute(
            'INSERT INTO utenti_sessioni
                (user_id, token_hash, device_label, ip_hash, created_at, last_used_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
                $userId,
                self::hashToken($token),
                $deviceLabel !== null ? mb_substr($deviceLabel, 0, 120) : null,
                $ip !== null ? substr(hash_hmac('sha256', $ip, Config::privacyPepper()), 0, 32) : null,
                gmdate('Y-m-d H:i:s', $now),
                gmdate('Y-m-d H:i:s', $now),
                gmdate('Y-m-d H:i:s', $now + $ttl),
            ]
        );

        Logger::audit('session.issued', $userId, 'session', null, 'ok', [
            'expires_in' => $ttl,
        ]);

        return [
            'token' => $token,
            'expires_at' => gmdate('c', $now + $ttl),
            'expires_in' => $ttl,
        ];
    }

    /**
     * Risolve il token in un utente. Restituisce null se il token e' assente,
     * sconosciuto, scaduto o revocato.
     */
    public static function resolveToken(?string $token): ?array
    {
        if ($token === null || $token === '' || strlen($token) > 200) {
            return null;
        }
        if (!Db::tableExists('utenti_sessioni')) {
            return null;
        }

        $session = Db::fetchOne(
            'SELECT s.id, s.user_id, s.device_label, s.expires_at, s.revoked_at
             FROM utenti_sessioni s
             WHERE s.token_hash = ?',
            [self::hashToken($token)]
        );
        if ($session === null) {
            Logger::audit('session.rejected', null, 'session', null, 'denied', [
                'reason' => 'unknown_token',
            ]);
            return null;
        }

        if ($session['revoked_at'] !== null) {
            Logger::audit('session.rejected', $session['user_id'], 'session', null, 'denied', [
                'reason' => 'revoked',
            ]);
            return null;
        }

        $now = time();
        if (strtotime(strval($session['expires_at'])) <= $now) {
            Logger::audit('session.rejected', $session['user_id'], 'session', null, 'denied', [
                'reason' => 'expired',
            ]);
            return null;
        }

        // L'utente potrebbe essere stato cancellato nel frattempo.
        $user = Db::fetchOne(
            'SELECT IDutente, nome, nickname, email, is_guest, erased_at, deletion_requested_at
             FROM utenti WHERE IDutente = ?',
            [$session['user_id']]
        );
        if ($user === null) {
            return null;
        }
        if (($user['erased_at'] ?? null) !== null) {
            return null;
        }
        if (($user['deletion_requested_at'] ?? null) !== null) {
            // L'account e' in finestra di attesa di cancellazione: l'accesso
            // resta consentito per un breve periodo, cosi' l'utente puo'
            // annullare la richiesta o scaricare i propri dati.
            if ((strtotime(strval($user['deletion_requested_at'])) + 86400 * 3) < $now) {
                return null;
            }
        }

        self::touchSession(intval($session['id']));

        return [
            'user_id' => strval($session['user_id']),
            'session_id' => intval($session['id']),
            'device_label' => $session['device_label'] ?? null,
            'user' => $user,
        ];
    }

    /** Rinnova `last_used_at` ed estende la scadenza a meta' TTL (sliding). */
    private static function touchSession(int $sessionId): void
    {
        $ttl = Config::sessionTtlSeconds();
        $now = time();
        $renewThreshold = $now - (int)floor($ttl / 2);

        try {
            Db::execute(
                'UPDATE utenti_sessioni
                 SET last_used_at = ?,
                     expires_at = CASE WHEN last_used_at < ? THEN ? ELSE expires_at END
                 WHERE id = ?',
                [
                    gmdate('Y-m-d H:i:s', $now),
                    gmdate('Y-m-d H:i:s', $renewThreshold),
                    gmdate('Y-m-d H:i:s', $now + $ttl),
                    $sessionId,
                ]
            );
        } catch (\Throwable $e) {
            // L'aggiornamento del timestamp e' opportunistico.
        }
    }

    public static function revokeToken(string $token, string $reason = 'user_logout'): void
    {
        $hash = self::hashToken($token);
        $session = Db::fetchOne('SELECT user_id FROM utenti_sessioni WHERE token_hash = ?', [$hash]);
        if ($session === null) {
            return;
        }
        Db::execute(
            'UPDATE utenti_sessioni SET revoked_at = ?, revoked_reason = ? WHERE token_hash = ?',
            [gmdate('Y-m-d H:i:s'), $reason, $hash]
        );
        Logger::audit('session.revoked', $session['user_id'], 'session', null, 'ok', [
            'reason' => $reason,
        ]);
    }

    /** Revoca tutte le sessioni di un utente (cambio password, logout globale). */
    public static function revokeAllForUser(string $userId, string $reason = 'global_logout'): int
    {
        $affected = Db::execute(
            'UPDATE utenti_sessioni SET revoked_at = ?, revoked_reason = ?
             WHERE user_id = ? AND revoked_at IS NULL',
            [gmdate('Y-m-d H:i:s'), $reason, $userId]
        );
        if ($affected > 0) {
            Logger::audit('session.revoked_all', $userId, 'session', null, 'ok', [
                'reason' => $reason,
                'count' => $affected,
            ]);
        }
        return $affected;
    }

    /**
     * Verifica le credenziali. Aggiunge un ritardo fisso sui fallimenti per non
     * rivelare con il tempo di risposta se l'utente esiste.
     */
    public static function verifyPassword(string $userId, string $password): ?array
    {
        $user = Db::fetchOne(
            'SELECT * FROM utenti WHERE IDutente = ?',
            [$userId]
        );

        $hash = $user['password_hash'] ?? null;
        if ($hash === null) {
            // Utente inesistente: si esegue comunque un confronto fittizio per
            // uniformare il tempo di risposta.
            password_verify($password, '$2y$12$' . str_repeat('.', 53));
            return null;
        }

        if (!password_verify($password, strval($hash))) {
            return null;
        }

        // Aggiorna il costo di hashing se l'algoritmo di default e' cambiato.
        if (password_needs_rehash(strval($hash), PASSWORD_DEFAULT)) {
            Db::execute(
                'UPDATE utenti SET password_hash = ? WHERE IDutente = ?',
                [password_hash($password, PASSWORD_DEFAULT), $userId]
            );
        }

        return $user;
    }

    /**
     * Blocca temporaneamente un login troppo frequente. Combina il limite per
     * utente con quello per indirizzo IP, cosi' un attacco a spruzzo su piu'
     * account viene limitato dal secondo controllo.
     */
    public static function assertLoginAllowed(string $userId, ?string $ip): void
    {
        $max = Config::maxLoginAttempts();
        $window = Config::loginLockoutSeconds();
        $pseudonym = Logger::pseudonymize($userId) ?? 'anon';

        $retryUser = Http::rateLimit('login:user:' . $pseudonym, $max, $window);
        $retryIp = Http::rateLimit('login:ip:' . substr(strval($ip ?? 'none'), 0, 64), $max * 3, $window);

        $retry = max($retryUser, $retryIp);
        if ($retry > 0) {
            Logger::audit('login.throttled', $userId, null, null, 'denied', [
                'retry_after' => $retry,
            ]);
            Http::retryAfter($retry);
            Http::error(
                'Troppi tentativi di accesso. Riprova tra ' . $retry . ' secondi.',
                429
            );
        }
    }

    /**
     * Requisiti minimi di robustezza della password. Restituisce un errore o
     * null se la password e' accettabile.
     */
    public static function validatePasswordStrength(string $password): ?string
    {
        $length = mb_strlen($password);
        if ($length < 10) {
            return 'La password deve contenere almeno 10 caratteri.';
        }
        if ($length > 200) {
            return 'La password non puo\' superare i 200 caratteri.';
        }
        if (preg_match('/[a-z]/', $password) !== 1
            || preg_match('/[A-Z]/', $password) !== 1
            || preg_match('/\d/', $password) !== 1) {
            return 'La password deve contenere almeno una lettera minuscola, una maiuscola e una cifra.';
        }
        return null;
    }
}
