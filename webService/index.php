<?php
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS");

// LOG per debuggare le richieste in arrivo (visibili nel file error_log di XAMPP/Apache)
error_log("=== NUOVA RICHIESTA ===");
error_log("Metodo: " . $_SERVER['REQUEST_METHOD']);
error_log("URI: " . $_SERVER['REQUEST_URI']);
$raw_input = file_get_contents('php://input');
error_log("Body: " . $raw_input);

require_once 'db.php';

function is_ten_digit_id($value): bool {
    return is_string($value) && preg_match('/^\d{10}$/', $value) === 1;
}

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
    default:
        error_log("Errore 404: Risorsa '$resource' non trovata.");
        http_response_code(404);
        echo json_encode(["error" => "Risorsa non trovata. Endpoint validi: /chats, /chat, /settings, /auth"]);
        break;
}
error_log("=== FINE RICHIESTA ===");
?>