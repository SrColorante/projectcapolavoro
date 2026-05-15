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
    $input = json_decode(file_get_contents('php://input'), true);
    $text = $input['textmessage'] ?? '';
    $receiver_id = $input['reciverID'] ?? null;

    if (!$text || !$receiver_id) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare textmessage e reciverID"]);
        exit;
    }
    if (!is_ten_digit_id(strval($receiver_id))) {
        http_response_code(400);
        echo json_encode(["error" => "reciverID deve essere numerico e di 10 cifre"]);
        exit;
    }

    $stmt = $pdo->prepare("INSERT INTO messaggi (textmessage, senderID, reciverID, timenow) VALUES (?, ?, ?, NOW())");
    $stmt->execute([$text, $current_user_id, $receiver_id]);
    
    echo json_encode(["success" => true, "message" => "Messaggio inviato"]);

} elseif ($method === 'PATCH') {
    // Modifica le informazioni sull'utente (es. nickname)
    $input = json_decode(file_get_contents('php://input'), true);
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
