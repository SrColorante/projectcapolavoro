<?php
if (!$current_user_id) {
    http_response_code(401);
    echo json_encode(["error" => "Utente non autenticato"]);
    exit;
}

function generate_ten_digit_id(): string {
    return strval(random_int(1000000000, 9999999999));
}

$method = $_SERVER['REQUEST_METHOD'];
if ($method === 'GET') {
    // Restituisce le chat (1-to-1 e gruppi) aperte dall'utente
    $stmt = $pdo->prepare("
        SELECT c.* FROM chat c
        LEFT JOIN chat_members cm ON c.IDchat = cm.chat_id
        WHERE (c.utente1 = ? OR c.utente2 = ? OR cm.user_id = ?)
        GROUP BY c.IDchat
    ");
    $stmt->execute([$current_user_id, $current_user_id, $current_user_id]);
    $chats = $stmt->fetchAll();

    // Per ogni chat, aggiungi i membri se è un gruppo
    foreach ($chats as &$chat) {
        if (intval($chat['is_group'] ?? 0) === 1) {
            $stmt2 = $pdo->prepare("
                SELECT u.IDutente, u.nome, u.nickname, u.profile_photo_url, cm.role
                FROM chat_members cm
                JOIN utenti u ON cm.user_id = u.IDutente
                WHERE cm.chat_id = ?
            ");
            $stmt2->execute([$chat['IDchat']]);
            $chat['members'] = $stmt2->fetchAll();
        }
    }
    unset($chat);

    echo json_encode(["success" => true, "data" => $chats]);

} elseif ($method === 'POST') {
    $is_group = ($input['is_group'] ?? false) ? 1 : 0;

    if ($is_group === 1) {
        // Creazione gruppo
        $name = trim($input['name'] ?? '');
        $member_ids = $input['member_ids'] ?? [];

        if ($name === '') {
            http_response_code(400);
            echo json_encode(["error" => "Specificare name per il gruppo"]);
            exit;
        }
        if (!is_array($member_ids) || count($member_ids) === 0) {
            http_response_code(400);
            echo json_encode(["error" => "Specificare almeno un membro (member_ids)"]);
            exit;
        }

        $chat_id = generate_ten_digit_id();
        $stmt = $pdo->prepare("INSERT INTO chat (IDchat, is_group, name, created_by, utente1, utente2) VALUES (?, 1, ?, ?, NULL, NULL)");
        $stmt->execute([$chat_id, $name, $current_user_id]);

        // Inserisci il creatore come admin
        $stmt = $pdo->prepare("INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, 'admin')");
        $stmt->execute([$chat_id, $current_user_id]);

        // Inserisci gli altri membri
        $stmt = $pdo->prepare("INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, 'member')");
        foreach ($member_ids as $mid) {
            $mid = strval($mid);
            if (is_ten_digit_id($mid) && $mid !== strval($current_user_id)) {
                $stmt->execute([$chat_id, $mid]);
            }
        }

        echo json_encode(["success" => true, "message" => "Gruppo creato", "IDchat" => $chat_id]);
    } else {
        // Crea una nuova chat 1-to-1 se non esiste
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
    }
} else {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
}
?>
