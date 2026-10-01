<?php
/**
 * resources/chat.php — Lettura e invio dei messaggi di una chat.
 *
 * L'identita' del mittente arriva esclusivamente dal token di sessione
 * risolto in index.php. Non esiste piu' alcun `reciverID`/`senderID` accettato
 * dall'esterno: l'impostazione era gia' fatta dal server, ma la mancanza di
 * autenticazione permetteva di inviare messaggi con l'identita' di altri.
 */

declare(strict_types=1);

require_once __DIR__ . '/../lib/retention.php';

require_authentication();

$method = Http::method();

/** Verifica che l'utente appartenga alla chat. Usata in lettura e scrittura. */
function assert_chat_membership(string $chatId, string $userId): void
{
    $row = Db::fetchOne(
        'SELECT 1 AS ok FROM chat
         WHERE IDchat = ?
           AND (utente1 = ? OR utente2 = ?
                OR IDchat IN (SELECT chat_id FROM chat_members WHERE user_id = ?))',
        [$chatId, $userId, $userId, $userId]
    );
    if ($row === null) {
        Logger::audit('chat.access_denied', $userId, 'chat', $chatId, 'denied');
        Http::error('Accesso negato a questa chat', 403);
    }
}

if ($method === 'GET') {
    $chatId = Http::query('chat_id');
    if ($chatId === null || !Auth::isValidUserId($chatId)) {
        Http::error('chat_id deve essere numerico e di 10 cifre', 400);
    }

    assert_chat_membership($chatId, $current_user_id);

    /*
     * Contrassegna come letti i messaggi ricevuti. La clausola AND status != 'read'
     * e' quello che rende l'UPDATE idempotente: senza, ogni polling (ogni 8 s, o
     * 2 s quando la chat e' aperta) riscriverebbe l'intera tabella.
     */
    Db::execute(
        "UPDATE messaggi SET status = 'read', read_at = UTC_TIMESTAMP()
         WHERE chat_id = ? AND senderID != ? AND status != 'read' AND deleted_at IS NULL",
        [$chatId, $current_user_id]
    );

    // Percorso legacy: messaggi pre-registrazione dei chat_id, che avevano
    // reciverID valorizzato e chat_id NULL.
    Db::execute(
        "UPDATE messaggi SET status = 'read', read_at = UTC_TIMESTAMP()
         WHERE chat_id IS NULL
           AND ((senderID = (SELECT utente1 FROM chat WHERE IDchat = ?)
                 AND reciverID = (SELECT utente2 FROM chat WHERE IDchat = ?))
             OR (senderID = (SELECT utente2 FROM chat WHERE IDchat = ?)
                 AND reciverID = (SELECT utente1 FROM chat WHERE IDchat = ?)))
           AND senderID != ? AND status != 'read' AND deleted_at IS NULL",
        [$chatId, $chatId, $chatId, $chatId, $current_user_id]
    );

    // Stato di scrittura/registrazione, valido pochi secondi.
    $typing = Db::fetchAll(
        "SELECT ts.user_id, ts.status, u.nickname, u.nome
         FROM chat_typing_status ts
         JOIN utenti u ON ts.user_id = u.IDutente
         WHERE ts.chat_id = ? AND ts.status != 'idle'
           AND ts.updated_at >= (UTC_TIMESTAMP() - INTERVAL 6 SECOND)
           AND ts.user_id != ?",
        [$chatId, $current_user_id]
    );

    $messages = Db::fetchAll(
        'SELECT m.id, m.textmessage, m.senderID, m.reciverID, m.chat_id,
                m.file_attachment_id, m.timenow, m.status, m.is_certified,
                m.deleted_at, m.edited_at,
                sf.file_name, sf.mime_type, sf.storage_key, sf.source_url,
                sf.preview_type, sf.preview_payload, sf.size_bytes
         FROM messaggi m
         LEFT JOIN shared_files sf ON m.file_attachment_id = sf.id
         WHERE m.chat_id = ?
         ORDER BY m.timenow ASC, m.id ASC',
        [$chatId]
    );

    if ($messages === []) {
        $messages = Db::fetchAll(
            'SELECT m.id, m.textmessage, m.senderID, m.reciverID, m.chat_id,
                    m.file_attachment_id, m.timenow, m.status, m.is_certified,
                    m.deleted_at, m.edited_at,
                    sf.file_name, sf.mime_type, sf.storage_key, sf.source_url,
                    sf.preview_type, sf.preview_payload, sf.size_bytes
             FROM messaggi m
             LEFT JOIN shared_files sf ON m.file_attachment_id = sf.id
             WHERE (senderID = (SELECT utente1 FROM chat WHERE IDchat = ?)
                AND reciverID = (SELECT utente2 FROM chat WHERE IDchat = ?))
                OR (senderID = (SELECT utente2 FROM chat WHERE IDchat = ?)
                AND reciverID = (SELECT utente1 FROM chat WHERE IDchat = ?))
             ORDER BY m.timenow ASC, m.id ASC',
            [$chatId, $chatId, $chatId, $chatId]
        );
    }

    $normalized = array_map(static function (array $row) use ($current_user_id): array {
        $deleted = $row['deleted_at'] !== null;
        $row['id'] = strval($row['id']);
        $row['senderID'] = $row['senderID'] === null ? null : strval($row['senderID']);
        $row['reciverID'] = $row['reciverID'] === null ? null : strval($row['reciverID']);
        $row['chat_id'] = $row['chat_id'] === null ? null : strval($row['chat_id']);
        $row['file_attachment_id'] = $row['file_attachment_id'] === null
            ? null
            : strval($row['file_attachment_id']);
        $row['is_certified'] = boolval($row['is_certified']);
        $row['deleted'] = $deleted;
        $row['is_mine'] = $row['senderID'] !== null && $row['senderID'] === $current_user_id;
        $row['textmessage'] = $deleted ? null : $row['textmessage'];
        if ($deleted) {
            // Il contenuto cancellato non viene proprio trasmesso, non viene
            // solo nascosto dal client: una volta cancellato non deve piu'
            // viaggiare sulla rete.
            $row['file_name'] = null;
            $row['storage_key'] = null;
            $row['source_url'] = null;
        }
        $row['preview_payload'] = isset($row['preview_payload']) && $row['preview_payload'] !== null
            ? json_decode(strval($row['preview_payload']), true)
            : null;
        return $row;
    }, $messages);

    Http::success($normalized, ['typing' => $typing]);
}

if ($method === 'POST') {
    // Aggiornamento dello stato di presenza: non e' contenuto, quindi
    // consento l'invio anche quando il trattamento e' limitato.
    if (isset($input['typing_status'])) {
        $chatId = strval($input['chat_id'] ?? '');
        $status = strval($input['typing_status']);
        if (!Auth::isValidUserId($chatId)) {
            Http::error('chat_id deve essere numerico e di 10 cifre', 400);
        }
        if (!in_array($status, ['typing', 'recording', 'idle'], true)) {
            Http::error('typing_status non valido', 400);
        }
        assert_chat_membership($chatId, $current_user_id);

        $existing = Db::fetchOne(
            'SELECT 1 AS ok FROM chat_typing_status WHERE chat_id = ? AND user_id = ?',
            [$chatId, $current_user_id]
        );
        if ($existing === null) {
            Db::execute(
                'INSERT INTO chat_typing_status (chat_id, user_id, status, updated_at)
                 VALUES (?, ?, ?, UTC_TIMESTAMP())',
                [$chatId, $current_user_id, $status]
            );
        } else {
            Db::execute(
                'UPDATE chat_typing_status SET status = ?, updated_at = UTC_TIMESTAMP()
                 WHERE chat_id = ? AND user_id = ?',
                [$status, $chatId, $current_user_id]
            );
        }

        Http::success(['status' => $status]);
        exit;
    }

    require_processing_allowed();

    $text = strval($input['textmessage'] ?? '');
    $chatId = isset($input['chat_id']) ? strval($input['chat_id']) : null;
    $receiverId = isset($input['reciverID'])
        ? str_replace(' ', '', strval($input['reciverID']))
        : null;
    $fileAttachmentId = $input['file_attachment_id'] ?? null;
    $encryptedPayload = $input['encrypted_payload'] ?? null;
    $messageSignature = trim(strval($input['message_signature'] ?? ''));
    $isCertified = ($input['is_certified'] ?? false) ? 1 : 0;

    if (mb_strlen($text) > 15000) {
        Http::error('Il messaggio supera i 15000 caratteri', 400);
    }
    if ($text === '' && $encryptedPayload === null && $fileAttachmentId === null) {
        Http::error('Specificare textmessage, encrypted_payload o file_attachment_id', 400);
    }

    if ($chatId !== null && $chatId !== '') {
        if (!Auth::isValidUserId($chatId)) {
            Http::error('chat_id deve essere numerico e di 10 cifre', 400);
        }
        assert_chat_membership($chatId, $current_user_id);
    } elseif ($receiverId !== null && $receiverId !== '') {
        if (!Auth::isValidUserId($receiverId)) {
            Http::error('reciverID deve essere numerico e di 10 cifre', 400);
        }
        // Il destinatario deve esistere ed essere attivo: altrimenti si
        // accumulerebbero messaggi verso identificativi inesistenti.
        $target = Db::fetchOne(
            'SELECT IDutente FROM utenti WHERE IDutente = ? AND erased_at IS NULL',
            [$receiverId]
        );
        if ($target === null) {
            Http::error('Destinatario non trovato', 404);
        }
    } else {
        Http::error('Specificare chat_id (gruppi) o reciverID (1-to-1)', 400);
    }

    // Un allegato puo' essere agganciato solo a un messaggio propri: altrimenti
    // un utente potrebbe allegare il file di un altro.
    if ($fileAttachmentId !== null) {
        $file = Db::fetchOne(
            'SELECT id, owner_user_id, deleted_at FROM shared_files WHERE id = ?',
            [intval($fileAttachmentId)]
        );
        if ($file === null) {
            Http::error('Allegato non trovato', 404);
        }
        if (strval($file['owner_user_id']) !== $current_user_id) {
            Http::error('Non puoi allegare un file di cui non sei proprietario', 403);
        }
        if ($file['deleted_at'] !== null) {
            Http::error('L\'allegato e\' stato eliminato', 410);
        }
    }

    $payload = $text;
    $e2eeMetadata = null;
    if ($encryptedPayload !== null) {
        $payload = json_encode(
            ['encrypted_payload' => $encryptedPayload],
            JSON_UNESCAPED_SLASHES
        );
        $e2eeMetadata = json_encode([
            'encrypted' => true,
            'sender_id' => $current_user_id,
            'receiver_id' => $receiverId ?? '',
            'created_at' => gmdate('c'),
        ], JSON_UNESCAPED_SLASHES);
    }

    Db::execute(
        'INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id, file_attachment_id,
                               timenow, is_certified, message_signature, e2ee_metadata)
         VALUES (?, ?, ?, ?, ?, UTC_TIMESTAMP(), ?, ?, ?)',
        [
            $payload,
            $current_user_id,
            $receiverId,
            $chatId,
            $fileAttachmentId,
            $isCertified,
            $messageSignature === '' ? null : $messageSignature,
            $e2eeMetadata,
        ]
    );

    $messageId = Db::lastInsertId();

    if ($fileAttachmentId !== null) {
        Db::execute(
            'UPDATE shared_files SET message_id = ? WHERE id = ? AND message_id IS NULL',
            [intval($messageId), intval($fileAttachmentId)]
        );
    }

    // Imposta il termine di conservazione: da questo momento il messaggio
    // ha una scadenza certa (Art. 5(1)(e)).
    Retention::stampMessages([intval($messageId)]);

    Http::success(['message' => 'Messaggio inviato', 'message_id' => $messageId], [
        'purge_after' => gmdate('c', time() + Config::retentionDays('messaggi') * 86400),
    ]);
}

if ($method === 'PATCH') {
    // Modifica di un proprio messaggio, entro una finestra breve.
    $messageId = strval($input['message_id'] ?? '');
    $newText = strval($input['textmessage'] ?? '');

    if (!ctype_digit($messageId)) {
        Http::error('message_id non valido', 400);
    }
    if (mb_strlen($newText) > 15000) {
        Http::error('Il messaggio supera i 15000 caratteri', 400);
    }

    $existing = Db::fetchOne(
        'SELECT id, senderID, timenow, deleted_at FROM messaggi WHERE id = ?',
        [intval($messageId)]
    );
    if ($existing === null) {
        Http::error('Messaggio non trovato', 404);
    }
    if (strval($existing['senderID']) !== $current_user_id) {
        Http::error('Puoi modificare solo i tuoi messaggi', 403);
    }

    $affected = Db::execute(
        'UPDATE messaggi SET textmessage = ?, edited_at = UTC_TIMESTAMP()
         WHERE id = ? AND senderID = ? AND deleted_at IS NULL',
        [$newText, intval($messageId), $current_user_id]
    );
    if ($affected === 0) {
        Http::error('Messaggio non modificabile', 409);
    }

    Http::success(['message' => 'Messaggio modificato', 'message_id' => $messageId]);
}

if ($method === 'DELETE') {
    // Cancellazione di un proprio messaggio: soft delete immediato, il
    // contenuto sparisce dalle risposte e viene rimosso definitivamente alla
    // scadenza di conservazione.
    $messageId = Http::query('message_id');
    if ($messageId === null || !ctype_digit($messageId)) {
        Http::error('message_id non valido', 400);
    }

    $existing = Db::fetchOne(
        'SELECT id, senderID FROM messaggi WHERE id = ?',
        [intval($messageId)]
    );
    if ($existing === null) {
        Http::error('Messaggio non trovato', 404);
    }
    if (strval($existing['senderID']) !== $current_user_id) {
        Http::error('Puoi eliminare solo i tuoi messaggi', 403);
    }

    $retentionDays = Config::retentionDays('messaggi');
    Db::execute(
        'UPDATE messaggi
         SET deleted_at = UTC_TIMESTAMP(), deleted_by = ?, purge_after = ?
         WHERE id = ? AND deleted_at IS NULL',
        [$current_user_id, gmdate('Y-m-d H:i:s', time() + $retentionDays * 86400), intval($messageId)]
    );

    // Anche i file allegati al messaggio vanno in soft delete.
    Db::execute(
        'UPDATE shared_files
         SET deleted_at = UTC_TIMESTAMP(),
             purge_after = ?
         WHERE message_id = ? AND deleted_at IS NULL',
        [gmdate('Y-m-d H:i:s', time() + Config::retentionDays('shared_files') * 86400), intval($messageId)]
    );

    Logger::audit('message.deleted', $current_user_id, 'messaggi', $messageId, 'ok');

    Http::success([
        'deleted' => true,
        'message_id' => $messageId,
        'purged_at' => gmdate('c', time() + $retentionDays * 86400),
    ]);
}

Http::error('Metodo non consentito', 405);
