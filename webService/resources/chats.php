<?php
/**
 * resources/chats.php — Elenco delle chat dell'utente.
 *
 * NOTA SULLE PRESTAZIONI
 * ----------------------
 * La versione precedente eseguiva, per OGNI chat restituita, due query aggiuntive
 * (membri/altro partecipante + ultimo messaggio) dentro un ciclo. Con 30 chat
 * erano 61 query a ogni polling: il client interroga questa rotta ogni 8 secondi
 * (ogni 2 con la chat aperta), quindi la tabella `chat` veniva setacciata
 * centinaia di volte al minuto per utente.
 *
 * Qui le informazioni di riepilogo sono calcolate in SQL con aggregazione e
 * LEFT JOIN, in numero costante di query. Indicizzate le colonne usate nei
 * filtri (vedi migration 003).
 */

declare(strict_types=1);

require_authentication();

$method = Http::method();

/** Genera un ID chat a 10 cifre non ancora presente. */
function generate_chat_id(PDO $pdo): string
{
    do {
        $candidate = strval(random_int(1000000000, 9999999999));
        $stmt = $pdo->prepare('SELECT 1 AS ok FROM chat WHERE IDchat = ?');
        $stmt->execute([$candidate]);
        $exists = $stmt->fetchColumn();
    } while ($exists);
    return $candidate;
}

if ($method === 'GET') {
    /*
     * Contrassegna come consegnati i messaggi in attesa. Due soli UPDATE con
     * `status = 'sent'` nella WHERE: senza quel filtro ogni polling riscriverebbe
     * le stesse righe e bloccare la tabella.
     */
    Db::execute(
        "UPDATE messaggi SET status = 'delivered'
         WHERE reciverID = ? AND status = 'sent' AND deleted_at IS NULL",
        [$current_user_id]
    );
    Db::execute(
        "UPDATE messaggi m
         SET m.status = 'delivered'
         WHERE m.status = 'sent' AND m.deleted_at IS NULL
           AND m.chat_id IN (SELECT chat_id FROM chat_members WHERE user_id = ?)
           AND m.senderID != ?",
        [$current_user_id, $current_user_id]
    );

    /*
     * Elenco chat con dati derivati aggregati.
     *
     * `last_message` e `last_message_time` arrivano da una correlazione su una
     * sottoquery che seleziona l'ultimo messaggio per chat: MySQL la valuta una
     * volta sola invece di una volta per riga.
     */
    $chats = Db::fetchAll(
        "SELECT c.IDchat, c.is_group, c.name, c.created_at, c.avatar_url,
                c.utente1, c.utente2,
                u1.nickname AS peer_nickname,
                u1.nome AS peer_name,
                u1.profile_photo_url AS peer_photo,
                lm.textmessage AS last_message,
                lm.senderID AS last_message_sender,
                lm.timenow AS last_message_time,
                (SELECT COUNT(*) FROM chat_members cm WHERE cm.chat_id = c.IDchat)
                    AS member_count
         FROM chat c
         LEFT JOIN utenti u1 ON u1.IDutente = CASE
             WHEN CAST(c.utente1 AS CHAR) = ? THEN c.utente2
             WHEN CAST(c.utente2 AS CHAR) = ? THEN c.utente1
             ELSE NULL END
         LEFT JOIN (
             SELECT m.chat_id, m.textmessage, m.senderID, m.timenow
             FROM messaggi m
             INNER JOIN (
                 SELECT chat_id, MAX(id) AS last_id
                 FROM messaggi
                 WHERE chat_id IS NOT NULL AND deleted_at IS NULL
                 GROUP BY chat_id
             ) x ON x.last_id = m.id
         ) lm ON lm.chat_id = c.IDchat
         WHERE c.utente1 = ? OR c.utente2 = ?
            OR c.IDchat IN (SELECT chat_id FROM chat_members WHERE user_id = ?)
         ORDER BY COALESCE(lm.timenow, c.created_at) DESC, c.IDchat DESC",
        [
            $current_user_id, $current_user_id,
            $current_user_id, $current_user_id, $current_user_id,
        ]
    );

    // I membri dei gruppi si caricano con UNA sola query per tutte le chat.
    $groupIds = array_values(array_filter(array_map(
        static fn(array $c): ?string => intval($c['is_group']) === 1 ? strval($c['IDchat']) : null,
        $chats
    )));

    $membersByChat = [];
    if ($groupIds !== []) {
        $placeholders = implode(',', array_fill(0, count($groupIds), '?'));
        $memberRows = Db::fetchAll(
            "SELECT cm.chat_id, u.IDutente, u.nome, u.nickname, u.profile_photo_url, cm.role
             FROM chat_members cm
             JOIN utenti u ON u.IDutente = cm.user_id
             WHERE cm.chat_id IN ($placeholders)",
            $groupIds
        );
        foreach ($memberRows as $row) {
            $membersByChat[strval($row['chat_id'])][] = [
                'id' => strval($row['IDutente']),
                'name' => $row['nome'],
                'nickname' => $row['nickname'],
                'avatar' => $row['profile_photo_url'],
                'role' => $row['role'],
            ];
        }
    }

    $result = array_map(static function (array $chat) use ($current_user_id, $membersByChat): array {
        $id = strval($chat['IDchat']);
        $isGroup = intval($chat['is_group']) === 1;

        $entry = [
            'id' => $id,
            'is_group' => $isGroup,
            'name' => $chat['name'],
            'avatar_url' => $chat['avatar_url'],
            'created_at' => $chat['created_at'],
            'last_message' => $chat['last_message'],
            'last_message_sender' => $chat['last_message_sender'] === null
                ? null
                : strval($chat['last_message_sender']),
            'last_message_time' => $chat['last_message_time'],
        ];

        if ($isGroup) {
            $entry['members'] = $membersByChat[$id] ?? [];
            $entry['member_count'] = intval($chat['member_count']);
        } else {
            $entry['other_user_name'] = $chat['peer_name'];
            $entry['other_user_nickname'] = $chat['peer_nickname'];
            $entry['other_user_avatar'] = $chat['peer_photo'];
        }

        return $entry;
    }, $chats);

    Http::success($result);
}

if ($method === 'POST') {
    require_processing_allowed();

    $isGroup = ($input['is_group'] ?? false) ? 1 : 0;

    if ($isGroup === 1) {
        $name = trim(strval($input['name'] ?? ''));
        $memberIds = is_array($input['member_ids'] ?? null)
            ? $input['member_ids']
            : [];

        if ($name === '') {
            Http::error('Specificare name per il gruppo', 400);
        }
        if (mb_strlen($name) > 100) {
            Http::error('Il nome del gruppo supera i 100 caratteri', 400);
        }
        if (count($memberIds) === 0) {
            Http::error('Specificare almeno un membro (member_ids)', 400);
        }

        $chatId = generate_chat_id(Db::pdo());

        Db::execute(
            'INSERT INTO chat (IDchat, is_group, name, created_by, utente1, utente2)
             VALUES (?, 1, ?, ?, NULL, NULL)',
            [$chatId, $name, $current_user_id]
        );
        Db::execute(
            "INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, 'admin')",
            [$chatId, $current_user_id]
        );

        // Solo utenti realmente esistenti: prima si poteva creare un gruppo
        // "con" identificativi inesistenti, che non avrebbero mai potuto accedere.
        $inserted = 0;
        $memberStmt = Db::pdo()->prepare(
            "INSERT IGNORE INTO chat_members (chat_id, user_id, role) VALUES (?, ?, 'member')"
        );
        foreach ($memberIds as $raw) {
            $memberId = str_replace(' ', '', trim(strval($raw)));
            if (!Auth::isValidUserId($memberId) || $memberId === $current_user_id) {
                continue;
            }
            $exists = Db::fetchOne(
                'SELECT 1 AS ok FROM utenti WHERE IDutente = ? AND erased_at IS NULL',
                [$memberId]
            );
            if ($exists === null) {
                continue;
            }
            $memberStmt->execute([$chatId, $memberId]);
            $inserted += $memberStmt->rowCount();
        }

        if ($inserted === 0) {
            // Nessun membro valido: la chat appena creata resta inutilizzabile,
            // quindi si annulla tutto.
            Db::execute('DELETE FROM chat WHERE IDchat = ?', [$chatId]);
            Http::error('Nessuno dei membri indicati esiste', 400);
        }

        Logger::audit('group.created', $current_user_id, 'chat', $chatId, 'ok', [
            'member_count' => $inserted + 1,
        ]);

        Http::success(['message' => 'Gruppo creato', 'IDchat' => $chatId, 'member_count' => $inserted + 1]);
        exit;
    }

    $targetUserId = isset($input['target_user_id'])
        ? str_replace(' ', '', trim(strval($input['target_user_id'])))
        : '';

    if ($targetUserId === '') {
        Http::error('Specificare target_user_id', 400);
    }
    if (!Auth::isValidUserId($targetUserId)) {
        Http::error('target_user_id deve essere numerico e di 10 cifre', 400);
    }
    if ($targetUserId === $current_user_id) {
        Http::error('Non puoi aprire una chat con te stesso', 400);
    }
    if (Privacy::isRestricted($current_user_id)) {
        Http::error('Trattamento limitato: aprire nuove chat non e\' consentito', 403);
    }

    $target = Db::fetchOne(
        'SELECT IDutente FROM utenti WHERE IDutente = ? AND erased_at IS NULL',
        [$targetUserId]
    );
    if ($target === null) {
        Http::error('Utente non trovato', 404);
    }

    // L'ordine dei due identificativi e' normalizzato: altrimenti (A,B) e
    // (B,A) producevano due chat distinte fra gli stessi due utenti.
    [$left, $right] = $current_user_id < $targetUserId
        ? [$current_user_id, $targetUserId]
        : [$targetUserId, $current_user_id];

    $existing = Db::fetchOne(
        'SELECT IDchat FROM chat WHERE utente1 = ? AND utente2 = ?',
        [$left, $right]
    );

    if ($existing !== null) {
        Http::success(['message' => 'Chat gia\' esistente', 'IDchat' => strval($existing['IDchat'])], [
            'created' => false,
        ]);
    }

    $chatId = generate_chat_id(Db::pdo());
    Db::execute(
        'INSERT INTO chat (IDchat, utente1, utente2) VALUES (?, ?, ?)',
        [$chatId, $left, $right]
    );

    Http::success(['message' => 'Chat creata', 'IDchat' => $chatId], ['created' => true]);
}

if ($method === 'DELETE') {
    // Uscita da un gruppo. L'utente viene rimosso dall'elenco dei membri; la
    // chat e i suoi messaggi restano per gli altri partecipanti, che non hanno
    // chiesto la cancellazione (Art. 17(2): la cancellazione non può danneggiare
    // i diritti di terzi).
    $chatId = Http::query('chat_id');
    if ($chatId === null || !Auth::isValidUserId($chatId)) {
        Http::error('chat_id deve essere numerico e di 10 cifre', 400);
    }

    $chat = Db::fetchOne('SELECT IDchat, is_group, created_by FROM chat WHERE IDchat = ?', [$chatId]);
    if ($chat === null) {
        Http::error('Chat non trovata', 404);
    }
    if (intval($chat['is_group']) !== 1) {
        Http::error('Operazione valida solo per i gruppi', 400);
    }

    $member = Db::fetchOne(
        'SELECT role FROM chat_members WHERE chat_id = ? AND user_id = ?',
        [$chatId, $current_user_id]
    );
    if ($member === null) {
        Http::error('Non sei membro di questo gruppo', 403);
    }

    Db::execute(
        'DELETE FROM chat_members WHERE chat_id = ? AND user_id = ?',
        [$chatId, $current_user_id]
    );
    Db::execute(
        'DELETE FROM chat_typing_status WHERE chat_id = ? AND user_id = ?',
        [$chatId, $current_user_id]
    );

    Logger::audit('group.left', $current_user_id, 'chat', $chatId, 'ok');

    Http::success(['left' => true, 'IDchat' => $chatId]);
}

Http::error('Metodo non consentito', 405);
