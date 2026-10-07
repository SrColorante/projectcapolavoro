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
    // Aggiorna lo stato dei messaggi a 'delivered' per le chat di cui fa parte l'utente
    try {
        $stmtDelivered1 = $pdo->prepare("
            UPDATE messaggi
            SET status = 'delivered'
            WHERE reciverID = ? AND status = 'sent'
        ");
        $stmtDelivered1->execute([$current_user_id]);

        $stmtDelivered2 = $pdo->prepare("
            UPDATE messaggi
            SET status = 'delivered'
            WHERE chat_id IN (
                SELECT chat_id FROM chat_members WHERE user_id = ?
            ) AND senderID != ? AND status = 'sent'
        ");
        $stmtDelivered2->execute([$current_user_id, $current_user_id]);
    } catch (\Exception $e) {
        // Silenzioso
    }

    // Restituisce le chat (1-to-1 e gruppi) aperte dall'utente
    $stmt = $pdo->prepare("
        SELECT c.* FROM chat c
        LEFT JOIN chat_members cm ON c.IDchat = cm.chat_id
        WHERE (c.utente1 = ? OR c.utente2 = ? OR cm.user_id = ?)
        GROUP BY c.IDchat
    ");
    $stmt->execute([$current_user_id, $current_user_id, $current_user_id]);
    $chats = $stmt->fetchAll();

    // Per ogni chat, aggiungi i membri se è un gruppo, altrimenti le info dell'altro partecipante
    foreach ($chats as &$chat) {
        if (intval($chat['is_group'] ?? 0) === 1) {
            $stmt2 = $pdo->prepare("
                SELECT u.IDutente, u.nome, u.nickname, u.profile_photo_url, cm.role
                FROM chat_members cm
                JOIN utenti u ON cm.user_id = u.site_email
                WHERE cm.chat_id = ?
            ");
            $stmt2->execute([$chat['IDchat']]);
            $chat['members'] = $stmt2->fetchAll();
        } else {
            $other_user_id = (strval($chat['utente1']) === strval($current_user_id)) ? $chat['utente2'] : $chat['utente1'];
            $stmt2 = $pdo->prepare("SELECT nome, nickname, profile_photo_url FROM utenti WHERE IDutente = ?");
            $stmt2->execute([$other_user_id]);
            $other_user = $stmt2->fetch();
            if ($other_user) {
                $chat['other_user_name'] = $other_user['nome'];
                $chat['other_user_nickname'] = $other_user['nickname'];
                $chat['other_user_avatar'] = $other_user['profile_photo_url'];
            }
        }

        // Recupera l'ultimo messaggio per questa chat
        $stmt_msg = $pdo->prepare("
            SELECT textmessage, senderID, timenow 
            FROM messaggi 
            WHERE chat_id = ? OR (chat_id IS NULL AND ((senderID = ? AND reciverID = ?) OR (senderID = ? AND reciverID = ?)))
            ORDER BY timenow DESC, id DESC 
            LIMIT 1
        ");
        if (intval($chat['is_group'] ?? 0) === 1) {
            $stmt_msg->execute([$chat['IDchat']]);
        } else {
            $stmt_msg->execute([$chat['IDchat'], $chat['utente1'], $chat['utente2'], $chat['utente2'], $chat['utente1']]);
        }
        $last_msg = $stmt_msg->fetch();
        if ($last_msg) {
            $chat['last_message'] = $last_msg['textmessage'];
            $chat['last_message_sender'] = strval($last_msg['senderID']);
            $chat['last_message_time'] = $last_msg['timenow'];
        } else {
            $chat['last_message'] = null;
            $chat['last_message_sender'] = null;
            $chat['last_message_time'] = null;
        }
    }
    unset($chat);

    echo json_encode(["success" => true, "data" => $chats]);

} elseif ($method === 'POST') {
    // `is_group` e' una colonna BOOLEAN. La variabile resta numerica perche'
    // sotto viene confrontata con `=== 1`, ma il valore passato al database
    // deve essere `TRUE`/`FALSE`: `1` su una colonna boolean e' un errore di
    // tipo che fallisce a runtime, non in scrittura. Vedi resources/bool.php.
    $is_group = ($input['is_group'] ?? false) ? 1 : 0;

    if ($is_group === 1) {
        // Creazione gruppo
        $name = trim($input['name'] ?? '');
        $member_ids = isset($input['member_ids']) && is_array($input['member_ids']) 
            ? array_map(function($id) { return str_replace(' ', '', trim(strval($id))); }, $input['member_ids']) 
            : [];

        if ($name === '') {
            http_response_code(400);
            echo json_encode(["error" => "Specificare name per il gruppo"]);
            exit;
        }
        if (count($member_ids) === 0) {
            http_response_code(400);
            echo json_encode(["error" => "Specificare almeno un membro (member_ids)"]);
            exit;
        }

        $chat_id = generate_ten_digit_id();
        // `is_group` e' BOOLEAN: il letterale va scritto TRUE, non 1, altrimenti
        // pdo_pgsql lo legge come la stringa "1" e rifiuta l'inserimento.
        $stmt = $pdo->prepare("INSERT INTO chat (IDchat, is_group, name, created_by, utente1, utente2) VALUES (?, TRUE, ?, ?, NULL, NULL)");
        $stmt->execute([$chat_id, $name, $current_user_id]);

        // Inserisci il creatore come admin
        $stmt = $pdo->prepare("INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, 'admin')");
        $stmt->execute([$chat_id, $current_user_id]);

        // Inserisci gli altri membri
        $stmt = $pdo->prepare("INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, 'member')");
        foreach ($member_ids as $mid) {
            $mid = strval($mid);
            if (is_valid_phone_id($mid) && $mid !== strval($current_user_id)) {
                $stmt->execute([$chat_id, $mid]);
            }
        }

        echo json_encode(["success" => true, "message" => "Gruppo creato", "IDchat" => $chat_id]);
    } else {
        // Crea una nuova chat 1-to-1 se non esiste
        $target_user_id = isset($input['target_user_id']) ? str_replace(' ', '', trim(strval($input['target_user_id']))) : null;

        if (!$target_user_id) {
            http_response_code(400);
            echo json_encode(["error" => "Specificare target_user_id"]);
            exit;
        }
        if (!is_valid_phone_id(strval($target_user_id))) {
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
