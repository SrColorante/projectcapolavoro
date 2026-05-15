<?php
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS");

require_once 'db.php';

// Estrai l'endpoint dall'URL
$request_uri = explode('?', $_SERVER['REQUEST_URI'], 2)[0];
$resource = basename($request_uri);
$method = $_SERVER['REQUEST_METHOD'];

// Simulazione utente autenticato (in un'app reale lo prenderesti da un token JWT o sessione)
// Per testare aggiungi ?user_id=1 all'URL
$current_user_id = isset($_GET['user_id']) ? (int)$_GET['user_id'] : null;

// Routing
switch ($resource) {
    case 'chats':
        require 'resources/chats.php';
        break;
    case 'chat':
        require 'resources/chat.php';
        break;
    case 'settings':
        require 'resources/settings.php';
        break;
    default:
        http_response_code(404);
        echo json_encode(["error" => "Risorsa non trovata. Endpoint validi: /chats, /chat, /settings"]);
        break;
}
?>