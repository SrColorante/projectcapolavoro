<?php
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once 'db.php';

function is_ten_digit_id($value): bool {
    return is_string($value) && preg_match('/^\d{10}$/', $value) === 1;
}

function get_signing_secrets(): array {
    $configured_secret = getenv('CRIMSON_CHAT_APP_SECRET');
    if ($configured_secret === false || $configured_secret === '') {
        $configured_secret = 'SEGRETO_DA_RUOTARE';
    }

    return [
        'crimson-chat-v1' => $configured_secret
    ];
}

function build_normalized_query(string $query_string): string {
    if ($query_string === '') {
        return '';
    }

    parse_str($query_string, $query_params);
    if (!is_array($query_params)) {
        return '';
    }

    ksort($query_params);
    return http_build_query($query_params, '', '&', PHP_QUERY_RFC3986);
}

function build_canonical_request(string $method, string $path, string $query_string, string $timestamp, string $body): string {
    return implode("\n", [
        strtoupper($method),
        $path,
        build_normalized_query($query_string),
        $timestamp,
        $body
    ]);
}

function reject_unsigned_request(string $message): void {
    http_response_code(401);
    echo json_encode(["error" => $message]);
    exit;
}

function validate_app_signature(string $raw_input): void {
    $provided_key = $_SERVER['HTTP_X_APP_KEY'] ?? '';
    $provided_timestamp = $_SERVER['HTTP_X_APP_TIMESTAMP'] ?? '';
    $provided_signature = $_SERVER['HTTP_X_APP_SIGNATURE'] ?? '';

    if ($provided_key === '' || $provided_timestamp === '' || $provided_signature === '') {
        reject_unsigned_request("Richiesta non autorizzata");
    }

    if (!ctype_digit($provided_timestamp)) {
        reject_unsigned_request("Timestamp richiesta non valido");
    }

    $timestamp = intval($provided_timestamp);
    if (abs(time() - $timestamp) > 300) {
        reject_unsigned_request("Richiesta scaduta");
    }

    $secrets = get_signing_secrets();
    $secret = $secrets[$provided_key] ?? null;
    if ($secret === null) {
        reject_unsigned_request("Chiave app non valida");
    }

    $request_path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?? '';
    $request_query = parse_url($_SERVER['REQUEST_URI'], PHP_URL_QUERY) ?? '';
    $canonical_request = build_canonical_request(
        $_SERVER['REQUEST_METHOD'],
        $request_path,
        $request_query,
        $provided_timestamp,
        $raw_input
    );
    $expected_signature = base64_encode(hash_hmac('sha256', $canonical_request, $secret, true));

    if (!hash_equals($expected_signature, $provided_signature)) {
        reject_unsigned_request("Firma richiesta non valida");
    }
}

// LOG per debuggare le richieste in arrivo (visibili nel file error_log di XAMPP/Apache)
error_log("=== NUOVA RICHIESTA ===");
error_log("Metodo: " . $_SERVER['REQUEST_METHOD']);
error_log("URI: " . $_SERVER['REQUEST_URI']);
$raw_input = file_get_contents('php://input');
$input = json_decode($raw_input, true);
if (!is_array($input)) {
    $input = [];
}
if ($raw_input !== '') {
    error_log("Body length: " . strlen($raw_input));
}
validate_app_signature($raw_input);

// Estrai l'endpoint dall'URL
$request_uri = explode('?', $_SERVER['REQUEST_URI'], 2)[0];
$resource = basename($request_uri);

// Fix per server senza mod_rewrite abilitato (.htaccess ignorato)
// Se la richiesta arriva a index.php, guardiamo il parametro ?route=...
if ($resource === 'index.php' || $resource === 'webService') {
    $resource = $_GET['route'] ?? 'auth';
}

error_log("Risorsa calcolata per il routing: " . $resource);

// Simulazione utente autenticato
$current_user_id = $_GET['user_id'] ?? null;

if ($current_user_id !== null && !is_ten_digit_id($current_user_id)) {
    error_log("Errore: user_id non valido");
    http_response_code(400);
    echo json_encode(["error" => "user_id deve essere numerico e di 10 cifre"]);
    exit;
}

// Routing
switch ($resource) {
    case 'chats':
        error_log("Routing verso: chats.php");
        require 'resources/chats.php';
        break;
    case 'chat':
        error_log("Routing verso: chat.php");
        require 'resources/chat.php';
        break;
    case 'settings':
        error_log("Routing verso: settings.php");
        require 'resources/settings.php';
        break;
    case 'auth':
        error_log("Routing verso: auth.php");
        require 'resources/auth.php';
        break;
    case 'security':
        error_log("Routing verso: security.php");
        require 'resources/security.php';
        break;
    case 'files':
        error_log("Routing verso: files.php");
        require 'resources/files.php';
        break;
    default:
        error_log("Errore 404: Risorsa '$resource' non trovata.");
        http_response_code(404);
        echo json_encode(["error" => "Risorsa non trovata. Endpoint validi: /chats, /chat, /settings, /auth, /security, /files"]);
        break;
}
error_log("=== FINE RICHIESTA ===");
?>
