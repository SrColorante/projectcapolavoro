<?php
/**
 * resources/files.php — Caricamento e metadati dei file condivisi.
 *
 * Il file salvato su disco non ha piu' il nome originale: si chiama
 * `<chiave casuale>.<estensione decisa dal server>`, dentro una sottocartella
 * datata. Il nome originale resta solo come metadato e come intestazione della
 * risposta di download.
 */

declare(strict_types=1);

require_once __DIR__ . '/../lib/upload.php';
require_once __DIR__ . '/../lib/retention.php';

require_authentication();

$method = Http::method();

/** Classifica il tipo di anteprima a partire da MIME reale ed estensione. */
function resolve_preview_type(string $mimeType, string $fileName, ?string $sourceUrl): string
{
    $mime = strtolower(trim($mimeType));
    $name = strtolower(trim($fileName));

    if ($sourceUrl !== null && preg_match('#^https?://#i', $sourceUrl) === 1) {
        return 'link';
    }
    if (str_starts_with($mime, 'audio/')) {
        return 'audio';
    }
    if ($mime === 'application/pdf' || str_ends_with($name, '.pdf')) {
        return 'pdf';
    }
    if ($mime === 'image/gif' || str_ends_with($name, '.gif')) {
        return 'gif';
    }
    if (str_starts_with($mime, 'image/')) {
        return 'image';
    }
    if (str_starts_with($mime, 'video/')) {
        return 'video';
    }
    return 'file';
}

function build_preview_payload(
    string $previewType,
    string $fileName,
    string $mimeType,
    ?string $storageKey
): array {
    $payload = [
        'title' => $fileName,
        'mime_type' => $mimeType,
    ];
    if ($storageKey !== null) {
        $payload['storage_key'] = $storageKey;
    }
    if ($previewType === 'link') {
        $payload['host'] = parse_url($storageKey ?? '', PHP_URL_HOST);
    }
    return $payload;
}

/** Serializza una riga di shared_files per il client. */
function serialize_file_row(array $row): array
{
    return [
        'id' => strval($row['id']),
        'file_name' => $row['file_name'],
        'mime_type' => $row['mime_type'],
        'size_bytes' => intval($row['size_bytes']),
        'preview_type' => $row['preview_type'],
        'preview_payload' => json_decode(strval($row['preview_payload'] ?? '{}'), true),
        'bypassed_limit' => boolval($row['bypassed_limit']),
        'created_at' => $row['created_at'],
        'message_id' => $row['message_id'] === null ? null : strval($row['message_id']),
        'deleted' => $row['deleted_at'] !== null,
        'download_url' => $row['deleted_at'] === null
            ? '/serve_file.php?file=' . rawurlencode(strval($row['storage_key'] ?? ''))
            : null,
    ];
}

if ($method === 'POST') {
    require_processing_allowed();

    $hasBinary = !empty($_FILES['file']);

    if ($hasBinary) {
        $uploaded = $_FILES['file'];
        if ($uploaded['error'] !== UPLOAD_ERR_OK) {
            $messages = [
                UPLOAD_ERR_INI_SIZE   => 'Il file supera il limite del server.',
                UPLOAD_ERR_FORM_SIZE  => 'Il file supera il limite consentito.',
                UPLOAD_ERR_PARTIAL    => 'Caricamento incompleto, riprova.',
                UPLOAD_ERR_NO_FILE    => 'Nessun file ricevuto.',
            ];
            Http::error(
                $messages[$uploaded['error']] ?? 'Errore durante il caricamento del file',
                400
            );
        }

        $retry = Http::rateLimit('upload:' . $current_user_id, 30, 300);
        if ($retry > 0) {
            Http::retryAfter($retry);
            Http::error('Troppi caricamenti in breve tempo.', 429);
        }

        try {
            $validated = Upload::validateReceivedFile($uploaded);
            $storageKey = Upload::storeReceivedFile($uploaded, $validated);
        } catch (RuntimeException $e) {
            Logger::audit('file.rejected', $current_user_id, 'shared_files', null, 'denied', [
                'reason' => $e->getMessage(),
            ]);
            Http::error($e->getMessage(), 400);
        }

        $messageId = isset($input['message_id']) ? intval($input['message_id']) : null;
        $previewType = resolve_preview_type(
            $validated['mime_type'],
            $validated['original_name'],
            null
        );
        $previewPayload = build_preview_payload(
            $previewType,
            $validated['original_name'],
            $validated['mime_type'],
            $storageKey
        );

        Db::execute(
            'INSERT INTO shared_files (owner_user_id, file_name, mime_type, size_bytes,
                                       storage_key, preview_type, preview_payload,
                                       message_id, bypassed_limit)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
            [
                $current_user_id,
                $validated['original_name'],
                $validated['mime_type'],
                $validated['size_bytes'],
                $storageKey,
                $previewType,
                json_encode($previewPayload, JSON_UNESCAPED_SLASHES),
                $messageId,
            ]
        );

        $fileId = Db::lastInsertId();
        Retention::stampFiles([intval($fileId)]);

        Logger::audit('file.uploaded', $current_user_id, 'shared_files', $fileId, 'ok', [
            'mime_type' => $validated['mime_type'],
            'size_bytes' => $validated['size_bytes'],
        ]);

        $row = Db::fetchOne('SELECT * FROM shared_files WHERE id = ?', [intval($fileId)]);
        Http::success(serialize_file_row($row ?? []));
        exit;
    }

    // Metadati senza binario: solo riferimenti esterni (link).
    $fileName = trim(strval($input['file_name'] ?? ''));
    $mimeType = trim(strval($input['mime_type'] ?? 'application/octet-stream'));
    $sizeBytes = intval($input['size_bytes'] ?? 0);
    $sourceUrl = trim(strval($input['source_url'] ?? ''));
    $messageId = isset($input['message_id']) ? intval($input['message_id']) : null;

    if ($fileName === '' || $sizeBytes <= 0) {
        Http::error('Specificare file_name e size_bytes > 0', 400);
    }

    // Un riferimento esterno non porta dati dentro il nostro sistema: si
    // conserva solo l'URL. La validazione del contenuto non e' applicabile.
    $previewType = resolve_preview_type($mimeType, $fileName, $sourceUrl === '' ? null : $sourceUrl);
    $previewPayload = build_preview_payload(
        $previewType,
        Upload::sanitizeDisplayName($fileName),
        $mimeType,
        $sourceUrl === '' ? null : $sourceUrl
    );

    Db::execute(
        'INSERT INTO shared_files (owner_user_id, file_name, mime_type, size_bytes,
                                   source_url, preview_type, preview_payload,
                                   message_id, bypassed_limit)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
            $current_user_id,
            Upload::sanitizeDisplayName($fileName),
            $mimeType,
            $sizeBytes,
            $sourceUrl === '' ? null : $sourceUrl,
            $previewType,
            json_encode($previewPayload, JSON_UNESCAPED_SLASHES),
            $messageId,
        ]
    );

    $fileId = Db::lastInsertId();
    Retention::stampFiles([intval($fileId)]);
    $row = Db::fetchOne('SELECT * FROM shared_files WHERE id = ?', [intval($fileId)]);
    Http::success(serialize_file_row($row ?? []));
}

if ($method === 'GET') {
    $rows = Db::fetchAll(
        'SELECT * FROM shared_files
         WHERE owner_user_id = ?
         ORDER BY created_at DESC
         LIMIT 200',
        [$current_user_id]
    );
    Http::success(array_map('serialize_file_row', $rows));
}

if ($method === 'DELETE') {
    $fileId = Http::query('file_id');
    if ($fileId === null || !ctype_digit($fileId)) {
        Http::error('file_id non valido', 400);
    }

    $row = Db::fetchOne(
        'SELECT id, storage_key, source_url, owner_user_id, deleted_at FROM shared_files WHERE id = ?',
        [intval($fileId)]
    );
    if ($row === null) {
        Http::error('File non trovato', 404);
    }
    if (strval($row['owner_user_id']) !== $current_user_id) {
        Http::error('Puoi eliminare solo i tuoi file', 403);
    }
    if ($row['deleted_at'] !== null) {
        Http::error('File gia\' eliminato', 409);
    }

    $retentionDays = Config::retentionDays('shared_files');
    Db::execute(
        'UPDATE shared_files SET deleted_at = UTC_TIMESTAMP(), purge_after = ? WHERE id = ?',
        [gmdate('Y-m-d H:i:s', time() + $retentionDays * 86400), intval($fileId)]
    );

    Logger::audit('file.deleted', $current_user_id, 'shared_files', $fileId, 'ok');
    Http::success([
        'deleted' => true,
        'file_id' => $fileId,
        'purged_at' => gmdate('c', time() + $retentionDays * 86400),
    ]);
}

Http::error('Metodo non consentito', 405);
