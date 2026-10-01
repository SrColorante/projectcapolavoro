<?php
/**
 * serve_file.php — Consegna dei file caricati.
 *
 * PRIMA (vulnerabile): nessuna autenticazione, `Access-Control-Allow-Origin: *`,
 * e il nome del file era sufficiente per ottenere qualunque contenuto. Chiunque
 * conoscesse (o indovinasse) un nome poteva scaricare foto e audio caricati da
 * altri utenti. Con un repository pubblico quei nomi erano letteralmente leggibili
 * nei commit: si trattava di dati personali esposti a chiunque.
 *
 * ADESSO: serve una sessione valida, e il richiedente deve essere il proprietario
 * del file oppure un partecipante della chat in cui il file e' stato condiviso.
 * Inoltre si inviano header che impediscono al browser di interpretare il
 * contenuto come documento attivo.
 *
 * Il file viene indicato con la sua chiave di archiviazione casuale
 * (`20260930/a1b2..._c3d4...jpg`) o, per i file precedenti alla migrazione,
 * con il vecchio `source_url` relativo.
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/config.php';
require_once __DIR__ . '/lib/db.php';
require_once __DIR__ . '/lib/http.php';
require_once __DIR__ . '/lib/logging.php';
require_once __DIR__ . '/lib/auth.php';
require_once __DIR__ . '/lib/upload.php';

Config::bootstrap();
Http::applySecurityHeaders();

/** Tipi che il browser puo' rappresentare senza rischi se serviti inline. */
const INLINE_SAFE_MIMES = [
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp',
    'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/aac', 'audio/ogg', 'audio/wav',
    'video/mp4', 'video/webm',
    'application/pdf',
    'text/plain',
];

if (Http::method() !== 'GET' && Http::method() !== 'HEAD') {
    Http::error('Metodo non consentito', 405);
}

$bearer = Http::bearerToken();
$session = Auth::resolveToken($bearer);
if ($session === null) {
    Logger::audit('file.denied', null, 'shared_files', null, 'denied', [
        'reason' => 'unauthenticated',
    ]);
    Http::error('Sessione mancante o scaduta.', 401);
}
$requesterId = $session['user_id'];

// Il rate limit e' volutamente generoso: un allegato video genera piu' richieste.
$retry = Http::rateLimit('file:' . substr($bearer ?? '', 0, 32), 600, 60);
if ($retry > 0) {
    Http::retryAfter($retry);
    Http::error('Troppe richieste di file in breve tempo.', 429);
}

$requested = Http::query('file');
if ($requested === null || $requested === '') {
    Http::error("Specificare il parametro 'file'", 400);
}

// Non accettare percorsi: solo chiavi piatte o con il prefisso data YYYYMMDD.
if (str_contains($requested, '..') || str_starts_with($requested, '/')) {
    Http::error('Identificatore file non valido', 400);
}

$record = Db::fetchOne(
    'SELECT sf.id, sf.storage_key, sf.source_url, sf.file_name, sf.mime_type,
            sf.message_id, sf.owner_user_id
     FROM shared_files sf
     WHERE (sf.storage_key = ? OR sf.source_url = ?)
       AND sf.deleted_at IS NULL
     LIMIT 1',
    [$requested, '/' . ltrim($requested, '/'), $requested]
);

if ($record === null) {
    Http::error('File non trovato', 404);
}

/**
 * Autorizzazione: proprietario, oppure un membro della chat che contiene il
 * messaggio cui il file e' agganciato.
 */
function can_access_file(array $record, string $requesterId): bool
{
    if (strval($record['owner_user_id']) === $requesterId) {
        return true;
    }

    $messageId = $record['message_id'];
    if ($messageId === null) {
        return false;
    }

    $message = Db::fetchOne(
        'SELECT senderID, reciverID, chat_id FROM messaggi WHERE id = ?',
        [$messageId]
    );
    if ($message === null) {
        return false;
    }
    if (strval($message['senderID']) === $requesterId
        || ($message['reciverID'] !== null && strval($message['reciverID']) === $requesterId)) {
        return true;
    }

    if ($message['chat_id'] === null) {
        return false;
    }

    $member = Db::fetchOne(
        'SELECT 1 AS ok FROM chat_members WHERE chat_id = ? AND user_id = ?',
        [$message['chat_id'], $requesterId]
    );
    if ($member !== null) {
        return true;
    }

    // Chat 1-to-1 legacy: i partecipanti sono in utente1/utente2.
    $pair = Db::fetchOne(
        'SELECT 1 AS ok FROM chat
         WHERE IDchat = ? AND (utente1 = ? OR utente2 = ?)',
        [$message['chat_id'], $requesterId, $requesterId]
    );
    return $pair !== null;
}

if (!can_access_file($record, $requesterId)) {
    Logger::audit('file.denied', $requesterId, 'shared_files', strval($record['id']), 'denied', [
        'reason' => 'not_participant',
    ]);
    Http::error('File non trovato', 404);
}

$storageKey = $record['storage_key'] ?: ltrim(strval($record['source_url'] ?? ''), '/');
if ($storageKey === '') {
    Http::error('File non trovato', 404);
}

try {
    $path = Upload::absolutePathFor($storageKey);
} catch (Throwable $e) {
    Http::error('File non trovato', 404);
}

if (!is_file($path)) {
    Http::error('File non trovato', 404);
}

$mime = strval($record['mime_type']);
if ($mime === '' || $mime === 'application/octet-stream') {
    $mime = Upload::detectMime($path);
}
$inline = in_array($mime, INLINE_SAFE_MIMES, true);

// Il nome originale viene reinserito solo come intestazione, mai come percorso.
$downloadName = Upload::sanitizeDisplayName(strval($record['file_name']));
$downloadName = str_replace(['"', "\r", "\n"], '', $downloadName);

header('Content-Type: ' . $mime);
header('Content-Length: ' . filesize($path));
header('Content-Disposition: ' . ($inline ? 'inline' : 'attachment')
    . '; filename="' . $downloadName . '"'
    . "; filename*=UTF-8''" . rawurlencode($downloadName));
// I file caricati non devono mai essere indicizzati ne' memorizzati da proxy.
header('Cache-Control: private, no-store, max-age=0');
header('X-Content-Type-Options: nosniff');
// Disattiva il rendering attivo per i PDF.
header('Content-Security-Policy: "default-src \'none\'; sandbox"');
header_remove('X-Powered-By');

if (Http::method() === 'HEAD') {
    exit;
}

Logger::audit('file.served', $requesterId, 'shared_files', strval($record['id']), 'ok');

readfile($path);
exit;
