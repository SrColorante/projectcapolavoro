<?php
if (!$current_user_id) {
    http_response_code(401);
    echo json_encode(["error" => "Utente non autenticato"]);
    exit;
}

if ($method === 'GET') {
    // Riceve i messaggi della chat
    $chat_id = $_GET['chat_id'] ?? null;
    if (!$chat_id) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare chat_id"]);
        exit;
    }
    if (!is_ten_digit_id(strval($chat_id))) {
        http_response_code(400);
        echo json_encode(["error" => "chat_id deve essere numerico e di 10 cifre"]);
        exit;
    }

    // Verifica che l'utente appartenga alla chat
    $stmt = $pdo->prepare("
        SELECT 1 FROM chat
        WHERE IDchat = ? AND (
            utente1 = ? OR utente2 = ? OR IDchat IN (
                SELECT chat_id FROM chat_members WHERE user_id = ?
            )
        )
    ");
    $stmt->execute([$chat_id, $current_user_id, $current_user_id, $current_user_id]);
    if (!$stmt->fetch()) {
        http_response_code(403);
        echo json_encode(["error" => "Accesso negato a questa chat"]);
        exit;
    }

    // Recupera i messaggi per chat_id (nuovo) oppure per sender/receiver (retrocompatibilità)
    $stmt = $pdo->prepare("
        SELECT m.*, sf.file_name, sf.mime_type, sf.source_url, sf.preview_type, sf.preview_payload
        FROM messaggi m
        LEFT JOIN shared_files sf ON m.file_attachment_id = sf.id
        WHERE m.chat_id = ?
        ORDER BY m.timenow ASC
    ");
    $stmt->execute([$chat_id]);
    $messaggi = $stmt->fetchAll();

    // Se non ci sono messaggi con chat_id, prova la query legacy per retrocompatibilità
    if (empty($messaggi)) {
        $stmt = $pdo->prepare("
            SELECT m.*, sf.file_name, sf.mime_type, sf.source_url, sf.preview_type, sf.preview_payload
            FROM messaggi m
            LEFT JOIN shared_files sf ON m.file_attachment_id = sf.id
            WHERE (senderID = (SELECT utente1 FROM chat WHERE IDchat = ?)
               AND reciverID = (SELECT utente2 FROM chat WHERE IDchat = ?))
               OR (senderID = (SELECT utente2 FROM chat WHERE IDchat = ?)
               AND reciverID = (SELECT utente1 FROM chat WHERE IDchat = ?))
            ORDER BY m.timenow ASC
        ");
        $stmt->execute([$chat_id, $chat_id, $chat_id, $chat_id]);
        $messaggi = $stmt->fetchAll();
    }

    // Decodifica preview_payload JSON
    foreach ($messaggi as &$msg) {
        if (!empty($msg['preview_payload'])) {
            $msg['preview_payload'] = json_decode($msg['preview_payload'], true);
        }
    }
    unset($msg);

    echo json_encode(["success" => true, "data" => $messaggi]);

} elseif ($method === 'POST') {
    // Inserisce un nuovo messaggio
    $text = $input['textmessage'] ?? '';
    $encrypted_payload = $input['encrypted_payload'] ?? null;
    $message_signature = trim($input['message_signature'] ?? '');
    $is_certified = ($input['is_certified'] ?? false) ? 1 : 0;
    $receiver_id = $input['reciverID'] ?? null;
    $chat_id = $input['chat_id'] ?? null;
    $file_attachment_id = $input['file_attachment_id'] ?? null;

    // Almeno uno tra text ed encrypted_payload deve essere presente (a meno che ci sia solo un allegato)
    $has_content = ($text !== '' || $encrypted_payload !== null || $file_attachment_id !== null);

    if (!$has_content) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare textmessage, encrypted_payload o file_attachment_id"]);
        exit;
    }

    // Se è un gruppo, chat_id è obbligatorio
    if ($chat_id) {
        if (!is_ten_digit_id(strval($chat_id))) {
            http_response_code(400);
            echo json_encode(["error" => "chat_id deve essere numerico e di 10 cifre"]);
            exit;
        }
        // Verifica appartenenza
        $stmt = $pdo->prepare("
            SELECT 1 FROM chat
            WHERE IDchat = ? AND (
                utente1 = ? OR utente2 = ? OR IDchat IN (
                    SELECT chat_id FROM chat_members WHERE user_id = ?
                )
            )
        ");
        $stmt->execute([$chat_id, $current_user_id, $current_user_id, $current_user_id]);
        if (!$stmt->fetch()) {
            http_response_code(403);
            echo json_encode(["error" => "Accesso negato a questa chat"]);
            exit;
        }
    } elseif ($receiver_id) {
        if (!is_ten_digit_id(strval($receiver_id))) {
            http_response_code(400);
            echo json_encode(["error" => "reciverID deve essere numerico e di 10 cifre"]);
            exit;
        }
    } else {
        http_response_code(400);
        echo json_encode(["error" => "Specificare chat_id (gruppi) o reciverID (1-to-1)"]);
        exit;
    }

    $payload = $text;
    $e2ee_metadata = null;
    if ($encrypted_payload !== null) {
        $payload = json_encode([
            "encrypted_payload" => $encrypted_payload
        ], JSON_UNESCAPED_SLASHES);
        $e2ee_metadata = json_encode([
            "encrypted" => true,
            "sender_id" => strval($current_user_id),
            "receiver_id" => strval($receiver_id ?? ''),
            "created_at" => gmdate('c')
        ], JSON_UNESCAPED_SLASHES);
    }

    $stmt = $pdo->prepare("INSERT INTO messaggi (
                               textmessage, senderID, reciverID, chat_id, file_attachment_id, timenow,
                               is_certified, message_signature, e2ee_metadata
                           ) VALUES (?, ?, ?, ?, ?, NOW(), ?, ?, ?)");
    $stmt->execute([
        $payload,
        $current_user_id,
        $receiver_id,
        $chat_id,
        $file_attachment_id,
        $is_certified,
        $message_signature === '' ? null : $message_signature,
        $e2ee_metadata
    ]);

    $new_message_id = $pdo->lastInsertId();

    // Se c'è un file_attachment_id senza message_id, aggiornalo
    if ($file_attachment_id) {
        $stmt = $pdo->prepare("UPDATE shared_files SET message_id = ? WHERE id = ? AND message_id IS NULL");
        $stmt->execute([$new_message_id, $file_attachment_id]);
    }

    echo json_encode(["success" => true, "message" => "Messaggio inviato", "message_id" => strval($new_message_id)]);

} elseif ($method === 'PATCH') {
    // Modifica le informazioni sull'utente (es. nickname)
    $new_nickname = $input['nickname'] ?? null;

    if ($new_nickname) {
        $stmt = $pdo->prepare("UPDATE utenti SET nickname = ? WHERE IDutente = ?");
        $stmt->execute([$new_nickname, $current_user_id]);
        echo json_encode(["success" => true, "message" => "Utente aggiornato"]);
    } else {
        http_response_code(400);
        echo json_encode(["error" => "Nessun dato da aggiornare fornito"]);
    }
} else {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
}
?>
