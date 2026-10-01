<?php
/**
 * resources/security.php — Materiale pubblico per la cifratura end-to-end.
 *
 * COSA NON E' (e va detto chiaramente, anche all'utente)
 * ---------------------------------------------------
 * La versione precedente generava le coppie di chiavi LATO SERVER e
 * restituiva nel corpo della risposta sia la chiave pubblica sia quella
 * PRIVATA. Un canale "end-to-end" in cui il server genera e conosce la chiave
 * privata non e' un canale end-to-end: il server puo' decifrare tutto cio' che
 * transita. Sulla base di quella falsa promessa l'interfaccia mostrava anche
 * un tutorial che affermava la cifratura end-to-end.
 *
 * In un'implementazione E2EE reale:
 *   - la chiave privata nasce sul dispositivo e non esce MAI dal dispositivo;
 *   - il server si limita a conservare e distribuire chiavi PUBBLICHE;
 *   - il messaggio cifrato viaggia opaco.
 *
 * Percio' qui il server non genera piu' chiavi e non accetta materiale privato.
 * Conserva e distribuisce solo chiavi pubbliche, e segnala esplicitamente che
 * la cifratura end-to-end non e' ancora attiva finche' il client non implementa
 * il cifrario. Inventare un canale sicuro dichiarandolo funzionante sarebbe
 * peggio che dichiararlo assente: ingannerebbe l'utente (Art. 5(1)(a)) pur senza
 * violare i dati.
 */

declare(strict_types=1);

require_authentication();

$method = Http::method();

/** Algoritmi ammessi per la chiave pubblica. */
const SUPPORTED_KEY_ALGORITHMS = ['x25519-xsalsa20poly1305', 'ed25519', 'rsa-oaep-2048'];

if ($method === 'GET') {
    // Chiavi pubbliche dei contatti: il client le usa per cifrare.
    $ids = Http::query('user_ids');
    if ($ids === null || $ids === '') {
        Http::error("Specificare 'user_ids' separati da virgola", 400);
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
        "SELECT IDutente, e2ee_public_key, e2ee_key_algorithm
         FROM utenti
         WHERE IDutente IN ($placeholders) AND erased_at IS NULL",
        $valid
    );

    $keys = [];
    foreach ($rows as $row) {
        $keys[strval($row['IDutente'])] = [
            'public_key' => $row['e2ee_public_key'],
            'algorithm' => $row['e2ee_key_algorithm'] ?? null,
        ];
    }

    Http::success($keys, [
        'e2ee_enabled' => false,
        'notice' => 'La cifratura end-to-end non e\' ancora implementata. '
            . 'Le chiavi pubbliche sono conservate in attesa, ma i messaggi '
            . 'viaggiano in chiaro sul canale TLS.',
    ]);
}

if ($method !== 'POST') {
    Http::error('Metodo non consentito', 405);
}

$action = strval($input['action'] ?? '');

if ($action === 'publish_public_key') {
    $publicKey = trim(strval($input['public_key'] ?? ''));
    $algorithm = trim(strval($input['algorithm'] ?? ''));

    if ($publicKey === '' || strlen($publicKey) > 2048) {
        Http::error('public_key mancante o troppo lunga', 400);
    }
    if (!in_array($algorithm, SUPPORTED_KEY_ALGORITHMS, true)) {
        Http::error('Algoritmo non supportato: ' . implode(', ', SUPPORTED_KEY_ALGORITHMS), 400);
    }

    // Rifiuto esplicito di qualsiasi materiale privato: se un client (o un
    // attaccante) provasse a depositare qui una chiave privata, non deve
    // finire nel database.
    $looksPrivate = str_contains($publicKey, 'PRIVATE KEY')
        || str_starts_with($publicKey, 'MC4CAQAw')
        || str_contains(strtolower($publicKey), 'private');
    if ($looksPrivate) {
        Logger::audit('security.private_key_rejected', $current_user_id, 'utenti', $current_user_id, 'denied');
        Http::error(
            'Questo endpoint accetta solo chiavi pubbliche. La chiave privata '
            . 'deve restare sul dispositivo e non deve mai essere inviata al server.',
            400
        );
    }

    Db::execute(
        'UPDATE utenti SET e2ee_public_key = ?, e2ee_key_algorithm = ? WHERE IDutente = ?',
        [$publicKey, $algorithm, $current_user_id]
    );

    Logger::audit('security.public_key_published', $current_user_id, 'utenti', $current_user_id, 'ok');

    Http::success([
        'published' => true,
        'algorithm' => $algorithm,
        'e2ee_enabled' => false,
    ]);
}

if ($action === 'wrap_message') {
    /*
     * Il server non deve MAI ricevere il messaggio in chiaro per poi cifrarlo:
     * e' il client che deve cifrare localmente con la chiave pubblica del
     * destinatario. Questa rotta viene rifiutata esplicitamente.
     */
    Logger::audit(
        'security.server_side_encryption_rejected',
        $current_user_id,
        null,
        null,
        'denied'
    );
    Http::error(
        'La cifratura deve avvenire sul dispositivo del mittente: il server non '
        . 'accetta messaggi in chiaro da cifrare. Implementa il cifrario lato client.',
        400
    );
}

Http::error(
    'Azione non valida. Usa publish_public_key. '
    . 'Le azioni generate_keypair e prepare_encrypted_message sono state rimosse: '
    . 'generare chiavi sul server non produce cifratura end-to-end.',
    400
);
