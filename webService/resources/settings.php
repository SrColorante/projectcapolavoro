<?php
/**
 * resources/settings.php — Profilo e preferenze dell'utente.
 *
 * Nota rispetto alla versione precedente: la risposta non faceva piu' eco
 * dell'intero corpo della richiesta (`"payload" => $input`), rimandando al
 * client tutto cio' che aveva inviato. Era un riflesso di debug che esponeva
 * campi non previsti e rumore inutile.
 */

declare(strict_types=1);

require_authentication();

$method = Http::method();

/** Bio scritta: limite dichiarato anche nell'interfaccia. */
const MAX_BIO_LENGTH = 500;

if ($method === 'GET') {
    $row = Db::fetchOne(
        'SELECT preferred_language, nickname, profile_bio, profile_photo_url,
                profile_audio_url, profile_audio_duration_seconds,
                processing_restricted, deletion_requested_at
         FROM utenti WHERE IDutente = ?',
        [$current_user_id]
    );

    Http::success([
        'preferred_language' => strtolower(strval($row['preferred_language'] ?? 'en')),
        'nickname' => $row['nickname'] ?? null,
        'profile_bio' => $row['profile_bio'] ?? null,
        'profile_photo_url' => $row['profile_photo_url'] ?? null,
        'profile_audio_url' => $row['profile_audio_url'] ?? null,
        'profile_audio_duration_seconds' => $row['profile_audio_duration_seconds'] === null
            ? null
            : floatval($row['profile_audio_duration_seconds']),
        'processing_restricted' => boolval($row['processing_restricted'] ?? false),
        'deletion_requested_at' => $row['deletion_requested_at'] ?? null,
    ]);
}

if ($method !== 'POST' && $method !== 'PATCH') {
    Http::error('Metodo non consentito', 405);
}

$language = strtolower(trim(strval($input['preferred_language'] ?? '')));
if ($language !== '' && preg_match('/^[a-z]{2}$/', $language) !== 1) {
    Http::error('preferred_language deve essere composto da 2 lettere', 400);
}

$nickname = trim(strval($input['nickname'] ?? ''));
$bio = trim(strval($input['profile_bio'] ?? ''));
$photoUrl = trim(strval($input['profile_photo_url'] ?? ''));
$audioUrl = trim(strval($input['profile_audio_url'] ?? ''));
$audioDuration = isset($input['profile_audio_duration_seconds'])
    ? floatval($input['profile_audio_duration_seconds'])
    : null;

if (mb_strlen($nickname) > 50) {
    Http::error('Il nickname supera i 50 caratteri', 400);
}
if (mb_strlen($bio) > MAX_BIO_LENGTH) {
    Http::error('La bio supera i ' . MAX_BIO_LENGTH . ' caratteri', 400);
}

// La bio vocale e' un dato biometrico nel senso del GDPR (voce). Se l'utente
// la imposta senza aver concesso il consenso specifico, la richiesta viene
// respinta: non basta che il campo sia opzionale, deve essere autorizzato.
if ($audioUrl !== '' && !Consent::has($current_user_id, 'voice_bio')) {
    Http::error(
        'Per impostare una bio vocale devi concedere il consenso specifico '
        . 'in Impostazioni > Privacy.',
        403
    );
}

if ($audioUrl !== '') {
    if ($audioDuration === null || $audioDuration <= 0 || $audioDuration > 5.0) {
        Http::error('La descrizione audio deve durare tra 0 e 5 secondi', 400);
    }
    $audioKey = resolve_owned_upload_key($audioUrl, $current_user_id, 'audio');
    if ($audioKey === null) {
        Http::error('Il file audio indicato non esiste o non e\' tuo', 400);
    }
} else {
    $audioKey = null;
    $audioDuration = null;
}

if ($photoUrl !== '') {
    $photoKey = resolve_owned_upload_key($photoUrl, $current_user_id, 'image');
    if ($photoKey === null) {
        Http::error('L\'immagine indicata non esiste o non e\' tua', 400);
    }
} else {
    $photoKey = null;
}

Db::execute(
    'UPDATE utenti
     SET preferred_language = COALESCE(NULLIF(?, ""), preferred_language),
         nickname           = COALESCE(NULLIF(?, ""), nickname),
         profile_bio        = NULLIF(?, ""),
         profile_photo_url  = ?,
         profile_audio_url  = ?,
         profile_audio_duration_seconds = ?
     WHERE IDutente = ?',
    [
        $language,
        $nickname,
        $bio,
        $photoKey,
        $audioKey,
        $audioDuration,
        $current_user_id,
    ]
);

Logger::audit('settings.updated', $current_user_id, 'utenti', $current_user_id, 'ok', [
    'has_bio' => $bio !== '',
    'has_photo' => $photoKey !== null,
    'has_audio_bio' => $audioKey !== null,
]);

$updated = Db::fetchOne(
    'SELECT preferred_language, nickname, profile_bio, profile_photo_url,
            profile_audio_url, profile_audio_duration_seconds
     FROM utenti WHERE IDutente = ?',
    [$current_user_id]
);

Http::success([
    'preferred_language' => strtolower(strval($updated['preferred_language'] ?? 'en')),
    'nickname' => $updated['nickname'] ?? null,
    'profile_bio' => $updated['profile_bio'] ?? null,
    'profile_photo_url' => $updated['profile_photo_url'] ?? null,
    'profile_audio_url' => $updated['profile_audio_url'] ?? null,
    'profile_audio_duration_seconds' => $updated['profile_audio_duration_seconds'] === null
        ? null
        : floatval($updated['profile_audio_duration_seconds']),
], ['message' => 'Impostazioni salvate']);

/**
 * Risolve un riferimento a un file caricato e verifica che ne appartenga
 * all'utente corrente, accettando sia la chiave di archiviazione sia il
 * vecchio `source_url` relativo.
 */
function resolve_owned_upload_key(string $reference, string $userId, string $expectedPreview): ?string
{
    $candidates = [$reference, '/' . ltrim($reference, '/')];

    foreach ($candidates as $candidate) {
        $row = Db::fetchOne(
            'SELECT storage_key, source_url, preview_type, owner_user_id, deleted_at
             FROM shared_files
             WHERE storage_key = ? OR source_url = ?
             LIMIT 1',
            [$candidate, $candidate]
        );
        if ($row === null) {
            continue;
        }
        if (strval($row['owner_user_id']) !== $userId) {
            return null;
        }
        if ($row['deleted_at'] !== null) {
            return null;
        }
        if ($expectedPreview !== '' && strval($row['preview_type']) !== $expectedPreview) {
            return null;
        }
        return strval($row['storage_key'] ?: ltrim(strval($row['source_url'] ?? ''), '/'));
    }

    return null;
}
