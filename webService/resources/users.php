<?php
/**
 * resources/users.php — Profili pubblici e blocchi (Art. 21, diritto di opposizione).
 *
 * Le rotte di questo file non accettano `user_id` dalla query string come
 * identita' dell'utente: `me` indica l'utente della sessione corrente,
 * `user_ids` indica gli identificativi che si vuole CONSULTARE (dati pubblici
 * del profilo), che e' operazione legittima e diversa dal fingere di essere
 * qualcun altro.
 *
 * Il profilo esposto e' volutamente minimo: identificativo, nome, nickname e
 * foto. Non vengono restituiti email, meta della 2FA, né stato di
 * cancellazione di terzi (Art. 5(1)(c) — minimizzazione).
 */

declare(strict_types=1);

require_authentication();

$method = Http::method();

/** Proiezione minima di un utente, per un richiedente qualsiasi. */
function public_profile(array $row): array
{
    return [
        'id' => strval($row['IDutente']),
        'name' => $row['nome'],
        'nickname' => $row['nickname'],
        'avatar' => $row['profile_photo_url'] ?? null,
    ];
}

if ($method === 'GET') {
    if (Http::query('me') !== null) {
        // Dati propri completi, compresi quelli identificativi che l'utente
        // stesso puo' legittimamente vedere.
        $me = Db::fetchOne('SELECT * FROM utenti WHERE IDutente = ?', [$current_user_id]);
        if ($me === null) {
            Http::error('Utente non trovato', 404);
        }
        Http::success([
            'id' => strval($me['IDutente']),
            'name' => $me['nome'],
            'nickname' => $me['nickname'],
            'email' => $me['email'] ?? null,
            'is_guest' => boolval($me['is_guest']),
            'avatar' => $me['profile_photo_url'] ?? null,
            'profile_bio' => $me['profile_bio'] ?? null,
            'two_factor_enabled' => boolval($me['two_factor_enabled']),
            'two_factor_channel' => $me['two_factor_channel'] ?? null,
            'processing_restricted' => boolval($me['processing_restricted'] ?? false),
            'deletion_requested_at' => $me['deletion_requested_at'] ?? null,
        ]);
    }

    $ids = Http::query('user_ids');
    if ($ids === null || $ids === '') {
        Http::error("Specificare 'me' oppure 'user_ids' separati da virgola", 400);
    }

    $requested = array_slice(array_filter(array_map('trim', explode(',', $ids))), 0, 50);
    $valid = array_values(array_filter(
        $requested,
        static fn($id) => Auth::isValidUserId($id)
    ));
    if ($valid === []) {
        Http::error('Nessun identificativo valido', 400);
    }

    $placeholders = implode(',', array_fill(0, count($valid), '?'));
    $rows = Db::fetchAll(
        "SELECT IDutente, nome, nickname, profile_photo_url
         FROM utenti
         WHERE IDutente IN ($placeholders) AND erased_at IS NULL",
        $valid
    );

    $profiles = [];
    foreach ($rows as $row) {
        $profiles[] = public_profile($row);
    }

    Http::success($profiles);
}

if ($method === 'POST') {
    $action = strval($input['action'] ?? '');

    if ($action === 'block' || $action === 'unblock') {
        $target = str_replace(' ', '', trim(strval($input['user_id'] ?? '')));

        if (!Auth::isValidUserId($target)) {
            Http::error('user_id deve essere numerico e di 10 cifre', 400);
        }
        if ($target === $current_user_id) {
            Http::error('Non puoi bloccare te stesso', 400);
        }

        $exists = Db::fetchOne(
            'SELECT 1 AS ok FROM utenti WHERE IDutente = ? AND erased_at IS NULL',
            [$target]
        );
        if ($exists === null) {
            Http::error('Utente non trovato', 404);
        }

        if ($action === 'block') {
            $existing = Db::fetchOne(
                'SELECT 1 AS ok FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?',
                [$current_user_id, $target]
            );
            if ($existing === null) {
                Db::execute(
                    'INSERT INTO user_blocks (blocker_id, blocked_id, created_at)
                     VALUES (?, ?, UTC_TIMESTAMP())',
                    [$current_user_id, $target]
                );
            }
            Logger::audit('user.blocked', $current_user_id, 'utenti', $target, 'ok');
            Http::success(['blocked' => true, 'user_id' => $target]);
        }

        Db::execute(
            'DELETE FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?',
            [$current_user_id, $target]
        );
        Logger::audit('user.unblocked', $current_user_id, 'utenti', $target, 'ok');
        Http::success(['blocked' => false, 'user_id' => $target]);
    }

    if ($action === 'report') {
        /*
         * Segnalazione di contenuto. Non e' una moderazione centralizzata: si
         * registra in locale, perche' il progetto e' aut ospitato e non
         * prevede un'autorita' centrale. Utile pero' come tracciamento interno.
         */
        $target = str_replace(' ', '', trim(strval($input['user_id'] ?? '')));
        $reason = trim(strval($input['reason'] ?? ''));

        if (!Auth::isValidUserId($target)) {
            Http::error('user_id deve essere numerico e di 10 cifre', 400);
        }
        if ($reason === '' || mb_strlen($reason) > 500) {
            Http::error('Indicare un motivo (max 500 caratteri)', 400);
        }

        Logger::audit('user.reported', $current_user_id, 'utenti', $target, 'ok', [
            'reason_length' => mb_strlen($reason),
        ]);
        Http::success(['recorded' => true]);
    }

    Http::error('Azione non valida. Usa block, unblock o report', 400);
}

Http::error('Metodo non consentito', 405);
