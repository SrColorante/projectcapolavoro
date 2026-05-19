<?php
if (!$current_user_id) {
    http_response_code(401);
    echo json_encode(["error" => "Utente non autenticato"]);
    exit;
}

function generate_ten_digit_id(): string {
    return strval(random_int(1000000000, 9999999999));
}

if ($method === 'GET') {
    // Restituisce le chat aperte dall'utente
    $stmt = $pdo->prepare("SELECT * FROM chat WHERE utente1 = ? OR utente2 = ?");
    $stmt->execute([$current_user_id, $current_user_id]);
    $chats = $stmt->fetchAll();
    
    echo json_encode(["success" => true, "data" => $chats]);

} elseif ($method === 'POST') {
    // Crea una nuova chat se non esiste
    $target_user_id = $input['target_user_id'] ?? null;

    if (!$target_user_id) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare target_user_id"]);
        exit;
    }
    if (!is_ten_digit_id(strval($target_user_id))) {
        http_response_code(400);
        echo json_encode(["error" => "target_user_id deve essere numerico e di 10 cifre"]);
        exit;
    }

    // Controlla se la chat esiste già
    $stmt = $pdo->prepare("SELECT IDchat FROM chat WHERE (utente1 = ? AND utente2 = ?) OR (utente1 = ? AND utente2 = ?)");
    $stmt->execute([$current_user_id, $target_user_id, $target_user_id, $current_user_id]);
    $existing_chat = $stmt->fetch();

    if ($existing_chat) {
        echo json_encode(["success" => false, "message" => "Chat già esistente", "IDchat" => $existing_chat['IDchat']]);
    } else {
        $chat_id = generate_ten_digit_id();
        $stmt = $pdo->prepare("INSERT INTO chat (IDchat, utente1, utente2) VALUES (?, ?, ?)");
        $stmt->execute([$chat_id, $current_user_id, $target_user_id]);
        echo json_encode(["success" => true, "message" => "Chat creata", "IDchat" => $chat_id]);
    }
} else {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
}
?>
