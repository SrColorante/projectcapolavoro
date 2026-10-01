<?php
/**
 * config.php — Configurazione centralizzata di Quice.
 *
 * Nessun segreto viene hardcodato: tutto arriva dall'ambiente o da un file
 * `.env` locale (NON tracciato in git). In assenza dei segreti obbligatori il
 * sistema si rifiuta di avviarsi in produzione: fallire subito e' preferibile
 * a servire richieste con credenziali prevedibili.
 *
 * @see lib/config.example.env
 */

declare(strict_types=1);

final class Config
{
    private static ?array $cache = null;

    /**
     * Percorso del file .env. Se assente si usa solo l'ambiente.
     */
    public static function envFilePath(): string
    {
        return dirname(__DIR__) . '/.env';
    }

    public static function appEnv(): string
    {
        return self::get('APP_ENV', 'development');
    }

    public static function isProduction(): bool
    {
        return in_array(self::appEnv(), ['production', 'prod'], true);
    }

    /**
     * Carica il .env una sola volta senza sovrascrivere variabili gia' presenti
     * nell'ambiente reale (che hanno sempre precedenza).
     */
    public static function bootstrap(): void
    {
        if (self::$cache !== null) {
            return;
        }

        $values = [];
        $file = self::envFilePath();
        if (is_readable($file)) {
            $values = self::parseEnvFile($file);
        }

        foreach ($values as $key => $value) {
            if (getenv($key) === false) {
                putenv("$key=$value");
                $_ENV[$key] = $value;
            }
        }

        self::$cache = $values;
    }

    private static function parseEnvFile(string $file): array
    {
        $parsed = [];
        $lines = @file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if ($lines === false) {
            return $parsed;
        }

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || $line[0] === '#') {
                continue;
            }
            $parts = explode('=', $line, 2);
            if (count($parts) !== 2) {
                continue;
            }
            $key = trim($parts[0]);
            $value = trim($parts[1]);
            // Consente di racchiudere il valore in apici per preservare gli spazi.
            if (strlen($value) >= 2
                && (($value[0] === '"' && substr($value, -1) === '"')
                    || ($value[0] === "'" && substr($value, -1) === "'"))) {
                $value = substr($value, 1, -1);
            }
            $parsed[$key] = $value;
        }

        return $parsed;
    }

    public static function get(string $key, ?string $default = null): ?string
    {
        $value = getenv($key);
        if ($value === false || $value === '') {
            return $default;
        }
        return $value;
    }

    public static function getInt(string $key, int $default): int
    {
        $value = self::get($key);
        if ($value === null || !preg_match('/^-?\d+$/', $value)) {
            return $default;
        }
        return (int)$value;
    }

    public static function getBool(string $key, bool $default): bool
    {
        $value = self::get($key);
        if ($value === null) {
            return $default;
        }
        return in_array(strtolower($value), ['1', 'true', 'yes', 'on'], true);
    }

    /**
     * Segreto usato per firmare le richieste (HMAC anti-manomissione).
     *
     * Nota di sicurezza: essendo il client distribuito, questo segreto NON e'
     * un segreto di autenticazione — vive nel binario dell'app. Serve solo a
     * rendere difficile il replay e il tampering di corpo/parametri. L'autenticazione
     * reale è il token di sessione (vedi lib/auth.php).
     */
    public static function appSigningSecret(): string
    {
        $secret = self::get('QUICE_APP_SECRET');
        if ($secret !== null) {
            return $secret;
        }
        if (self::isProduction()) {
            throw new RuntimeException(
                'QUICE_APP_SECRET mancante: definiscilo nel file .env prima di avviare in produzione.'
            );
        }
        return 'quice-dev-signing-secret';
    }

    /**
     * Pepper per l'hash degli indirizzi IP e per la pseudonimizzazione nei log.
     * Separato dal segreto applicativo per non riusare lo stesso materiale.
     */
    public static function privacyPepper(): string
    {
        $pepper = self::get('QUICE_PRIVACY_PEPPER');
        if ($pepper !== null) {
            return $pepper;
        }
        if (self::isProduction()) {
            throw new RuntimeException(
                'QUICE_PRIVACY_PEPPER mancante: indefinirlo prima di avviare in produzione.'
            );
        }
        return 'quice-dev-privacy-pepper';
    }

    public static function dbDsn(): string
    {
        $dsn = self::get('QUICE_DB_DSN');
        if ($dsn !== null) {
            return $dsn;
        }
        $host = self::get('QUICE_DB_HOST', '127.0.0.1');
        $name = self::get('QUICE_DB_NAME', 'chatProject');
        return "mysql:host=$host;dbname=$name;charset=utf8mb4";
    }

    public static function dbUser(): string
    {
        $user = self::get('QUICE_DB_USER');
        if ($user === null) {
            if (self::isProduction()) {
                throw new RuntimeException('QUICE_DB_USER mancante in produzione.');
            }
            return 'root';
        }
        return $user;
    }

    public static function dbPassword(): string
    {
        $password = self::get('QUICE_DB_PASSWORD', '');
        if ($password === null && self::isProduction()) {
            throw new RuntimeException('QUICE_DB_PASSWORD mancante in produzione.');
        }
        return $password ?? '';
    }

    /** Origini autorizzate a chiamare l'API. `*` solo in sviluppo. */
    public static function allowedOrigins(): array
    {
        $configured = self::get('QUICE_ALLOWED_ORIGINS');
        if ($configured === null) {
            if (self::isProduction()) {
                throw new RuntimeException(
                    'QUICE_ALLOWED_ORIGINS mancante in produzione (elenco separato da virgola).'
                );
            }
            return ['*'];
        }
        $origins = array_values(array_filter(array_map('trim', explode(',', $configured))));
        return $origins === [] ? [] : $origins;
    }

    /** Durata di validita' di un token di sessione, in secondi. */
    public static function sessionTtlSeconds(): int
    {
        return self::getInt('QUICE_SESSION_TTL_SECONDS', 60 * 60 * 24 * 30);
    }

    /** Numero massimo di tentativi di login falliti prima del blocco. */
    public static function maxLoginAttempts(): int
    {
        return self::getInt('QUICE_MAX_LOGIN_ATTEMPTS', 5);
    }

    public static function loginLockoutSeconds(): int
    {
        return self::getInt('QUICE_LOGIN_LOCKOUT_SECONDS', 900);
    }

    /** Dimensione massima di un upload in byte (default 50 MiB). */
    public static function maxUploadBytes(): int
    {
        return self::getInt('QUICE_MAX_UPLOAD_BYTES', 52428800);
    }

    /** Percorso della cartella che contiene i file caricati. */
    public static function uploadsDir(): string
    {
        $dir = self::get('QUICE_UPLOADS_DIR');
        if ($dir !== null) {
            return rtrim($dir, '/');
        }
        return dirname(__DIR__) . '/uploads';
    }

    /** Percorso del log strutturato. Null per disabilitare la scrittura su file. */
    public static function auditLogPath(): ?string
    {
        return self::get('QUICE_AUDIT_LOG_PATH');
    }

    /** Numero di giorni oltre i quali una richiesta di cancellazione viene forzata. */
    public static function erasureGraceDays(): int
    {
        return self::getInt('QUICE_ERASURE_GRACE_DAYS', 30);
    }

    /** Giorni di conservazione predefiniti per tipo di risorsa. */
    public static function retentionDays(string $resource): int
    {
        $key = 'QUICE_RETENTION_' . strtoupper($resource);
        return self::getInt($key, self::defaultRetentionDays($resource));
    }

    public static function defaultRetentionDays(string $resource): int
    {
        $defaults = [
            'messaggi' => 365,
            'shared_files' => 180,
            'utenti_sessioni' => 30,
            'audit_log' => 730,
            'consensi' => 1825,
            'chat_typing_status' => 1,
        ];
        return $defaults[$resource] ?? 365;
    }

    /**
     * Verifica che i segreti obbligatori siano presenti. Da chiamare all'avvio
     * del processo; fallisce in produzione se qualcosa manca.
     */
    public static function assertConfigured(): void
    {
        // Valuta le property per far emergere l'eccezione se qualcosa manca.
        self::dbDsn();
        self::dbUser();
        self::dbPassword();
        self::privacyPepper();
        self::appSigningSecret();
        self::allowedOrigins();
    }
}
