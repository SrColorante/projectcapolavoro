<?php
/**
 * http.php — Impostazioni di sicurezza HTTP, CORS, risposte JSON e rate limit.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/logging.php';

final class Http
{
    private static bool $headersSent = false;

    /**
     * Intestazioni di sicurezza applicate a ogni risposta.
     *
     * La CSP e' restrittiva di proposito: l'API non deve mai poter eseguire
     * script ne' incorporare contenuti esterni, e i file caricati dagli utenti
     * non devono poter essere interpretati come documenti attivi.
     */
    public static function applySecurityHeaders(): void
    {
        if (headers_sent()) {
            return;
        }
        self::$headersSent = true;

        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: no-referrer');
        header('Cross-Origin-Resource-Policy: same-site');
        header_remove('X-Powered-By');

        if (Config::isProduction()) {
            header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
            header(
                "Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
            );
            header('Permissions-Policy: geolocation=(), microphone=(), camera=()');
        }
    }

    /**
     * CORS a lista bianca. In sviluppo, se non configurata, resta aperto per
     * comodita' — in produzione Config::allowedOrigins() fallisce se manca.
     */
    public static function applyCors(): void
    {
        if (headers_sent()) {
            return;
        }

        header('Vary: Origin');
        header('Access-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS');
        header(
            'Access-Control-Allow-Headers: Content-Type, Authorization, X-App-Key, X-App-Timestamp, X-App-Signature'
        );
        header('Access-Control-Max-Age: 600');

        $origin = $_SERVER['HTTP_ORIGIN'] ?? null;
        if ($origin === null) {
            return;
        }

        $allowed = Config::allowedOrigins();
        if (in_array('*', $allowed, true)) {
            header('Access-Control-Allow-Origin: *');
            return;
        }
        if (in_array($origin, $allowed, true)) {
            header('Access-Control-Allow-Origin: ' . $origin);
            header('Access-Control-Allow-Credentials: true');
        }
    }

    public static function json(array $payload, int $status = 200): void
    {
        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=UTF-8');
            header('Cache-Control: no-store');
        }
        echo json_encode(
            $payload,
            JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE
        );
    }

    public static function success($data = null, array $extra = []): void
    {
        self::json(array_merge(['success' => true, 'data' => $data], $extra));
    }

    public static function error(string $message, int $status = 400, array $extra = []): void
    {
        self::json(array_merge(['success' => false, 'error' => $message], $extra), $status);
    }

    public static function preflightIfNeeded(): bool
    {
        if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'OPTIONS') {
            return false;
        }
        http_response_code(204);
        exit;
    }

    public static function method(): string
    {
        return strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
    }

    public static function body(): string
    {
        $raw = file_get_contents('php://input');
        return $raw === false ? '' : $raw;
    }

    public static function jsonBody(): array
    {
        $decoded = json_decode(self::body(), true);
        return is_array($decoded) ? $decoded : [];
    }

    public static function query(string $key, ?string $default = null): ?string
    {
        $value = $_GET[$key] ?? null;
        if (!is_string($value)) {
            return $default;
        }
        return trim($value);
    }

    /**
     * Header Authorization Bearer. Rimuove il prefisso e normalizza.
     */
    public static function bearerToken(): ?string
    {
        $header = $_SERVER['HTTP_AUTHORIZATION']
            ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
            ?? null;
        if (!is_string($header)) {
            return null;
        }
        if (preg_match('/^Bearer\s+(\S+)$/i', trim($header), $matches) !== 1) {
            return null;
        }
        return $matches[1];
    }

    /**
     * Rate limit a finestra scorrevole, con chiave arbitraria.
     * Restituisce i secondi residui quando il limite e' superato, 0 altrimenti.
     */
    public static function rateLimit(string $key, int $maxAttempts, int $windowSeconds): int
    {
        if (!Db::tableExists('rate_limit_events')) {
            return 0;
        }

        $now = time();
        $threshold = $now - $windowSeconds;

        try {
            Db::execute(
                'DELETE FROM rate_limit_events WHERE occurred_at < ?',
                [gmdate('Y-m-d H:i:s', $threshold)]
            );
            Db::execute(
                'INSERT INTO rate_limit_events (bucket_key, occurred_at) VALUES (?, ?)',
                [$key, gmdate('Y-m-d H:i:s', $now)]
            );
            $count = (int)Db::fetchOne(
                'SELECT COUNT(*) AS c FROM rate_limit_events WHERE bucket_key = ? AND occurred_at >= ?',
                [$key, gmdate('Y-m-d H:i:s', $threshold)]
            )['c'];
        } catch (\Throwable $e) {
            // Il rate limit non deve mai bloccare il servizio: se la tabella
            // non e' disponibile si prosegue senza limitare.
            return 0;
        }

        if ($count > $maxAttempts) {
            return max(1, $windowSeconds - ($now - $threshold));
        }
        return 0;
    }

    public static function retryAfter(int $seconds): void
    {
        if (!headers_sent()) {
            header('Retry-After: ' . $seconds);
        }
    }
}
