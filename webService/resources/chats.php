<?php
if (!$current_user_id) {
    http_response_code(401);
    echo json_encode(["error" => "Utente non autenticato"]);
    exit;
}

if ($method === 'GET') {
    // Restituisce le chat aperte dall'utente
    $stmt = $pdo->prepare("SELECT * FROM chat WHERE utente1 = ? OR utente2 = ?");
    $stmt->execute([$current_user_id, $current_user_id]);
    $chats = $stmt->fetchAll();
    
    echo json_encode(["success" => true, "data" => $chats]);

} elseif ($method === 'POST') {
    // Crea una nuova chat se non esiste
    $input = json_decode(file_get_contents('php://input'), true);
    $target_user_id = $input['target_user_id'] ?? null;

    if (!$target_user_id) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare target_user_id"]);
        exit;
    }

    // Controlla se la chat esiste già
    $stmt = $pdo->prepare("SELECT IDchat FROM chat WHERE (utente1 = ? AND utente2 = ?) OR (utente1 = ? AND utente2 = ?)");
    $stmt->execute([$current_user_id, $target_user_id, $target_user_id, $current_user_id]);
    $existing_chat = $stmt->fetch();

    if ($existing_chat) {
        echo json_encode(["success" => false, "message" => "Chat già esistente", "IDchat" => $existing_chat['IDchat']]);
    } else {
        $stmt = $pdo->prepare("INSERT INTO chat (utente1, utente2) VALUES (?, ?)");
        $stmt->execute([$current_user_id, $target_user_id]);
        echo json_encode(["success" => true, "message" => "Chat creata", "IDchat" => $pdo->lastInsertId()]);
    }
} else {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
}
?>