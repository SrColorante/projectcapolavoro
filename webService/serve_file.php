<?php
/**
 * serve_file.php — Serve file binari dallo storage uploads/
 * 
 * Questo endpoint NON richiede autenticazione HMAC.
 * I file caricati sono considerati pubblici una volta uploadati.
 * 
 * Uso: ?file=nomefile.ext
 */

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, ngrok-skip-browser-warning, User-Agent");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    header("Content-Type: application/json");
    echo json_encode(["error" => "Metodo non consentito"]);
    exit;
}

$requested_file = $_GET['file'] ?? '';

if ($requested_file === '') {
    http_response_code(400);
    header("Content-Type: application/json");
    echo json_encode(["error" => "Specificare il parametro 'file'"]);
    exit;
}

// Sanitize: solo basename, nessun directory traversal
$safe_name = basename($requested_file);
$upload_dir = __DIR__ . '/uploads/';
$file_path = $upload_dir . $safe_name;

if (!file_exists($file_path) || !is_file($file_path)) {
    http_response_code(404);
    header("Content-Type: application/json");
    echo json_encode(["error" => "File non trovato"]);
    exit;
}

// Determina MIME type
$finfo = finfo_open(FILEINFO_MIME_TYPE);
$mime_type = finfo_file($finfo, $file_path);
finfo_close($finfo);

if ($mime_type === false || $mime_type === '') {
    $mime_type = 'application/octet-stream';
}

// Serve il file
header("Content-Type: $mime_type");
header("Content-Length: " . filesize($file_path));
header("Content-Disposition: inline; filename=\"$safe_name\"");
header("Cache-Control: public, max-age=86400");

readfile($file_path);
exit;
