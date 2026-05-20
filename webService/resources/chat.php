<?php
if (!$current_user_id) {
    http_response_code(401);
    echo json_encode(["error" => "Utente non autenticato"]);
    exit;
}

if ($method === 'GET') {
    // Riceve i messaggi della chat e info sull'utente target
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

    // Recupera i messaggi (usando sender e receiver)
    // NB: Nel tuo schema, 'messaggi' non ha un collegamento diretto a 'IDchat', 
    // quindi uniamo tramite gli utenti della chat.
    $stmt = $pdo->prepare("SELECT * FROM messaggi 
                           WHERE (senderID = (SELECT utente1 FROM chat WHERE IDchat = ?) 
                           AND reciverID = (SELECT utente2 FROM chat WHERE IDchat = ?))
                           OR (senderID = (SELECT utente2 FROM chat WHERE IDchat = ?) 
                           AND reciverID = (SELECT utente1 FROM chat WHERE IDchat = ?))
                           ORDER BY timenow ASC");
    $stmt->execute([$chat_id, $chat_id, $chat_id, $chat_id]);
    $messaggi = $stmt->fetchAll();

    echo json_encode(["success" => true, "data" => $messaggi]);

} elseif ($method === 'POST') {
    // Inserisce un nuovo messaggio
    $text = $input['textmessage'] ?? '';
    $encrypted_payload = $input['encrypted_payload'] ?? null;
    $message_signature = trim($input['message_signature'] ?? '');
    $is_certified = ($input['is_certified'] ?? false) ? 1 : 0;
    $receiver_id = $input['reciverID'] ?? null;

    if ((!$text && $encrypted_payload === null) || !$receiver_id) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare textmessage (o encrypted_payload) e reciverID"]);
        exit;
    }
    if (!is_ten_digit_id(strval($receiver_id))) {
        http_response_code(400);
        echo json_encode(["error" => "reciverID deve essere numerico e di 10 cifre"]);
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
            "receiver_id" => strval($receiver_id),
            "created_at" => gmdate('c')
        ], JSON_UNESCAPED_SLASHES);
    }

    $stmt = $pdo->prepare("INSERT INTO messaggi (
                               textmessage, senderID, reciverID, timenow,
                               is_certified, message_signature, e2ee_metadata
                           ) VALUES (?, ?, ?, NOW(), ?, ?, ?)");
    $stmt->execute([
        $payload,
        $current_user_id,
        $receiver_id,
        $is_certified,
        $message_signature === '' ? null : $message_signature,
        $e2ee_metadata
    ]);
    
    echo json_encode(["success" => true, "message" => "Messaggio inviato"]);

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
