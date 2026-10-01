<?php
/**
 * index.php — Front controller di Quice.
 *
 * Differenze rispetto alla versione precedente:
 *  - l'identita' dell'utente NON arriva piu' da `?user_id=`. Viene risolta da
 *    un token Bearer; se manca, la richiesta e' anonima e solo gli endpoint
 *    pubblici (auth, privacy info) rispondono.
 *  - il log non riporta piu' la query string, che conteneva il numero di
 *    telefono dell'utente. Si registra solo metodo, risorsa e correlation id.
 *  - le eccezioni non riversano piu' il proprio messaggio al client in
 *    produzione: prima ogni errore interno veniva risposto testualmente,
 *    esponendo struttura del database e dettagli di connessione.
 *  - il routing e' una mappa esplicita: nessun `require` costruito da input.
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/config.php';
require_once __DIR__ . '/lib/db.php';
require_once __DIR__ . '/lib/http.php';
require_once __DIR__ . '/lib/logging.php';
require_once __DIR__ . '/lib/auth.php';
require_once __DIR__ . '/lib/privacy.php';
require_once __DIR__ . '/lib/consent.php';
require_once __DIR__ . '/lib/upload.php';

Config::bootstrap();

// Gli header vanno emessi prima di qualunque output.
Http::applySecurityHeaders();
Http::applyCors();
Http::preflightIfNeeded();

/**
 * Traduce un'eccezione non gestita in una risposta JSON.
 *
 * In produzione il messaggio e' generico: il dettaglio va nel log tecnico,
 * non nella risposta, perche' contiene informazioni sulla struttura del
 * sistema. In sviluppo resta leggibile per il debug.
 */
set_exception_handler(static function (Throwable $e): void {
    $status = 500;
    $message = 'Errore interno del server.';

    if ($e instanceof PDOException) {
        Logger::technical('error', 'Errore database', [
            'type' => get_class($e),
            'message' => $e->getMessage(),
        ]);
    } else {
        Logger::technical('error', 'Eccezione non gestita', [
            'type' => get_class($e),
            'message' => $e->getMessage(),
            'file' => basename($e->getFile()) . ':' . $e->getLine(),
        ]);
    }

    if (!Config::isProduction()) {
        $message .= ' [' . get_class($e) . ': ' . $e->getMessage() . ']';
    }

    Logger::audit('request.failed', null, 'http', null, 'error', [
        'cid' => Logger::correlationId(),
    ]);

    Http::error($message, $status);
});

// Gli warning e i notice diventano eccezioni, ma senza interrompere la
// richiesta su E_DEPRECATED/E_NOTICE, che nel codice legacy sono frequenti.
set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
    if ((error_reporting() & $severity) === 0) {
        return false;
    }
    if ($severity === E_DEPRECATED || $severity === E_USER_DEPRECATED) {
        Logger::technical('debug', 'Deprecato: ' . $message, [
            'file' => basename($file) . ':' . $line,
        ]);
        return true;
    }
    throw new ErrorException($message, 0, $severity, $file, $line);
});

try {
    Config::assertConfigured();
} catch (RuntimeException $e) {
    Http::error(
        'Configurazione del server incompleta. Contatta l\'amministratore.',
        503
    );
    Logger::technical('critical', 'Configurazione incompleta', ['reason' => $e->getMessage()]);
    exit;
}

$requestPath = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$requestQuery = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_QUERY) ?: '';
$rawBody = Http::body();
$input = json_decode($rawBody, true);
if (!is_array($input)) {
    $input = [];
}

/*
 * `serve_file` e' instradato prima di ogni altra cosa: e' l'unico endpoint
 * che non accetta un corpo JSON e che serve byte, non JSON.
 *
 * La lettura di `$_GET['route']` e' protetta: senza controllo, ogni richiesta
 * priva del parametro produceva un avviso "Undefined array key", che il
 * gestore degli errori trasformava in eccezione e quindi in HTTP 500.
 */
$routeParam = is_string($_GET['route'] ?? null) ? strval($_GET['route']) : '';
$scriptName = basename(explode('?', $_SERVER['REQUEST_URI'] ?? '/')[0]);

if ($routeParam === 'auth' || $routeParam === 'index' || $routeParam === 'webService') {
    $routeParam = 'auth';
}
$resource = in_array($scriptName, ['index.php', 'index', 'webService', ''], true)
    ? ($routeParam === '' ? 'auth' : $routeParam)
    : $scriptName;

if ($scriptName === 'serve_file' || $routeParam === 'serve_file') {
    require __DIR__ . '/serve_file.php';
    exit;
}

// Log tecnico senza dati personali: niente query string (contiene identificativi).
Logger::technical('info', 'Richiesta ricevuta', [
    'method' => Http::method(),
    'resource' => $resource,
    'cid' => Logger::correlationId(),
]);

/*
 * Verifica della firma HMAC.
 *
 * Il segreto vive nel binario del client, quindi NON e' un segreto: questa
 * verifica protegge da manomissione e replay, non autentica. L'autenticazione
 * e' il token di sessione. La firma resta utile perche' rende non immediatamente
 * utilizzabile un endpoint catturato da un terzo.
 */
if (!validate_request_signature($rawBody, $requestPath, $requestQuery)) {
    Logger::audit('request.rejected', null, 'http', $resource, 'denied', [
        'reason' => 'bad_signature',
    ]);
    exit;
}

/**
 * Verifica la firma HMAC della richiesta e la freschezza del timestamp.
 */
function validate_request_signature(string $rawBody, string $requestPath, string $requestQuery): bool
{
    $key = $_SERVER['HTTP_X_APP_KEY'] ?? '';
    $timestamp = $_SERVER['HTTP_X_APP_TIMESTAMP'] ?? '';
    $signature = $_SERVER['HTTP_X_APP_SIGNATURE'] ?? '';

    if ($key === '' || $timestamp === '' || $signature === '') {
        reject_signed_request('Richiesta non autorizzata');
    }
    if (!ctype_digit(strval($timestamp))) {
        reject_signed_request('Timestamp non valido');
    }
    if (abs(time() - intval($timestamp)) > 300) {
        reject_signed_request('Richiesta scaduta');
    }
    if (hash_equals('crimson-chat-v1', strval($key)) === false) {
        reject_signed_request('Chiave app non valida');
    }

    $canonical = implode("\n", [
        strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET'),
        $requestPath,
        build_normalized_query(strval($requestQuery)),
        strval($timestamp),
        $rawBody,
    ]);

    $expected = base64_encode(
        hash_hmac('sha256', $canonical, Config::appSigningSecret(), true)
    );

    if (!hash_equals($expected, strval($signature))) {
        reject_signed_request('Firma non valida');
    }

    return true;
}

function build_normalized_query(string $queryString): string
{
    if ($queryString === '') {
        return '';
    }
    parse_str($queryString, $params);
    if (!is_array($params)) {
        return '';
    }
    ksort($params);
    return http_build_query($params, '', '&', PHP_QUERY_RFC3986);
}

function reject_signed_request(string $message): void
{
    Http::error($message, 401);
    exit;
}

/*
 * Risoluzione dell'identita' dal token Bearer.
 *
 * `$current_user_id` viene impostato SOLO qui. Nessun endpoint lo legge dalla
 * query string: era esattamente il buco che permetteva l'impersonazione.
 */
$current_user_id = null;
$current_session = null;
$current_user = null;

$bearer = Http::bearerToken();
if ($bearer !== null) {
    $resolved = Auth::resolveToken($bearer);
    if ($resolved !== null) {
        $current_user_id = $resolved['user_id'];
        $current_session = $resolved;
        $current_user = $resolved['user'];
    }
}

/** Endpoint che richiedono una sessione valida. */
function require_authentication(): void
{
    global $current_user_id;
    if ($current_user_id === null) {
        Logger::audit('request.unauthenticated', null, 'http', null, 'denied');
        Http::error('Sessione mancante o scaduta. Accedi di nuovo.', 401);
    }
}

/** Blocca le richieste se l'utente ha chiesto la limitazione del trattamento. */
function require_processing_allowed(): void
{
    global $current_user_id;
    if ($current_user_id === null) {
        return;
    }
    if (Privacy::isRestricted($current_user_id)) {
        Http::error(
            'Il trattamento dei tuoi dati e\' limitato. Riattivalo dalle impostazioni '
            . 'sulla privacy per inviare nuovi messaggi.',
            403
        );
    }
}

$routes = [
    'auth'       => __DIR__ . '/resources/auth.php',
    'chats'      => __DIR__ . '/resources/chats.php',
    'chat'       => __DIR__ . '/resources/chat.php',
    'settings'   => __DIR__ . '/resources/settings.php',
    'security'   => __DIR__ . '/resources/security.php',
    'files'      => __DIR__ . '/resources/files.php',
    'privacy'    => __DIR__ . '/resources/privacy.php',
    'users'      => __DIR__ . '/resources/users.php',
];

$target = $routes[$resource] ?? null;
if ($target === null) {
    Http::error(
        'Risorsa non trovata. Endpoint validi: ' . implode(', ', array_keys($routes)),
        404
    );
    exit;
}

require $target;
