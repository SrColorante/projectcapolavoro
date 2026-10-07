<?php
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
    exit;
}

$action = $input['action'] ?? null;
$phone = str_replace(' ', '', trim($input['phone'] ?? ''));
$email = trim($input['email'] ?? '');
$password = $input['password'] ?? '';
$name = trim($input['name'] ?? '');
$preferred_language = trim($input['preferred_language'] ?? 'en');
$profile_bio = trim($input['profile_bio'] ?? '');
$profile_photo_url = trim($input['profile_photo_url'] ?? '');
$profile_audio_url = trim($input['profile_audio_url'] ?? '');
$audio_duration = floatval($input['profile_audio_duration_seconds'] ?? 0);
$e2ee_public_key = trim($input['e2ee_public_key'] ?? '');
// Era `? 1 : 0` perche' la colonna era TINYINT(1) di MySQL; in PostgreSQL
// `two_factor_enabled` e' BOOLEAN.
$two_factor_enabled = ($input['two_factor_enabled'] ?? false) ? true : false;
$two_factor_channel = trim($input['two_factor_channel'] ?? '');
$two_factor_destination = trim($input['two_factor_destination'] ?? '');

if (!$action) {
    http_response_code(400);
    echo json_encode(["error" => "Specificare action"]);
    exit;
}

function generate_unique_user_id(PDO $pdo): string {
    do {
        $candidate = strval(random_int(1000000000, 9999999999));
        $stmt = $pdo->prepare("SELECT 1 FROM utenti WHERE IDutente = ?");
        $stmt->execute([$candidate]);
        $exists = $stmt->fetchColumn();
    } while ($exists);

    return $candidate;
}

function build_profile(array $user): array {
    return [
        // Il client si aspetta ancora un `id` numerico, e con quello cerca
        // gli amici e le chat: mandare l'email qui romperebbe le schermate
        // gia' scritte. Resta `IDutente`, che e' UNIQUE e non e' piu' la PK.
        "id" => strval($user['idutente'] ?? $user['IDutente'] ?? ''),
        "name" => $user['nome'],
        "nickname" => $user['nickname'],
        // `real_email` e l'indirizzo che la persona ha dato. `site_email` e'
        // la chiave del database e va in un campo a parte, altrimenti il
        // client finisce per mostrare l'indirizzo di dominio a chi si e'
        // registrato col telefono.
        "email" => $user['real_email'] ?? null,
        "site_email" => $user['site_email'] ?? null,
        "is_guest" => boolval($user['is_guest'] ?? false),
        "preferred_language" => strval($user['preferred_language'] ?? 'en'),
        "profile_bio" => $user['profile_bio'] ?? null,
        "profile_photo_url" => $user['profile_photo_url'] ?? null,
        "profile_audio_url" => $user['profile_audio_url'] ?? null,
        "profile_audio_duration_seconds" => isset($user['profile_audio_duration_seconds'])
            ? floatval($user['profile_audio_duration_seconds'])
            : null,
        "e2ee_public_key" => $user['e2ee_public_key'] ?? null,
        "two_factor_enabled" => boolval($user['two_factor_enabled'] ?? false),
        "two_factor_channel" => $user['two_factor_channel'] ?? null,
        "two_factor_destination" => $user['two_factor_destination'] ?? null,
        "two_factor_verified" => isset($user['two_factor_verified_at']) && $user['two_factor_verified_at'] !== null,
        "pec_certified" => isset($user['pec_certified_at']) && $user['pec_certified_at'] !== null
    ];
}

function normalize_language(string $value): string {
    if (preg_match('/^[a-z]{2}$/i', $value) !== 1) {
        return 'en';
    }
    return strtolower($value);
}

function nullable_profile_value(string $value): ?string {
    $trimmed = trim($value);
    return $trimmed === '' ? null : $trimmed;
}

$normalized_language = normalize_language($preferred_language);
$normalized_bio = nullable_profile_value($profile_bio);
$normalized_photo = nullable_profile_value($profile_photo_url);
$normalized_audio = nullable_profile_value($profile_audio_url);
$normalized_e2ee_public_key = nullable_profile_value($e2ee_public_key);
$normalized_2fa_channel = in_array($two_factor_channel, ['email', 'phone'], true)
    ? $two_factor_channel
    : null;
$normalized_2fa_destination = nullable_profile_value($two_factor_destination);

/**
 * Indirizzo di dominio con cui entrare nel database condiviso.
 *
 * La PK di `utenti` e' `site_email`, quindi ogni riga ne ha bisogno. Quique
 * chiede il telefono, non l'email: quando il client non manda un indirizzo di
 * dominio se ne deriva uno dal telefono. Il CHECK `chk_utenti_site_email_domain`
 * accetta '@cristianrenosto.party', e questa funzione non puo' produrre altro.
 *
 * Nota sul dominio: `cristianrenosto.party` ha una regola Cloudflare
 * Email Routing con catch-all su `drop`, quindi un indirizzo derivato qui non
 * riceve posta. Va bene perche' `real_email` resta l'unico canale per le
 * notifiche.
 */
function resolve_site_email(string $email, string $phone): string {
    $trimmed = strtolower(trim($email));
    if ($trimmed !== '' && str_ends_with($trimmed, '@cristianrenosto.party')) {
        return $trimmed;
    }
    return $phone . '@cristianrenosto.party';
}

if ($normalized_audio !== null && ($audio_duration <= 0 || $audio_duration > 5.0)) {
    http_response_code(400);
    echo json_encode(["error" => "La descrizione audio deve durare tra 0 e 5 secondi"]);
    exit;
}

if ($action === 'guest_login') {
    $guest_id = generate_unique_user_id($pdo);
    $guest_name = $name === '' ? 'Ospite' : $name;
    $guest_email = "guest+" . $guest_id . "@guest.local";
    $password_hash = password_hash(bin2hex(random_bytes(12)), PASSWORD_BCRYPT);

    $stmt = $pdo->prepare("INSERT INTO utenti (
                                site_email, real_email, IDutente, nome, cognome, nickname, password_hash, dataCreazione,
                                is_guest, preferred_language, e2ee_public_key
                           ) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_DATE, TRUE, ?, ?)");
    $stmt->execute([
        $guest_email,
        $guest_email,
        $guest_id,
        $guest_name,
        'Utente',
        $guest_name,
        $password_hash,
        $normalized_language,
        $normalized_e2ee_public_key
    ]);

    $user = [
        'IDutente' => $guest_id,
        'nome' => $guest_name,
        'nickname' => $guest_name,
        'email' => $guest_email,
        'is_guest' => 1,
        'preferred_language' => $normalized_language,
        'e2ee_public_key' => $normalized_e2ee_public_key
    ];

    echo json_encode(["success" => true, "data" => build_profile($user)]);
    exit;
}

if ($action === 'login') {
    if ($phone === '' || $password === '') {
        http_response_code(400);
        echo json_encode(["error" => "Specificare numero di telefono e password"]);
        exit;
    }
}

function authenticate_user_or_fail(PDO $pdo, string $phone, string $password): array {
    $stmt = $pdo->prepare("SELECT * FROM utenti WHERE IDutente = ?");
    $stmt->execute([$phone]);
    $user = $stmt->fetch();
    if (!$user || !password_verify($password, $user['password_hash'])) {
        http_response_code(401);
        echo json_encode(["error" => "Credenziali non valide"]);
        exit;
    }
    return $user;
}

if ($action === 'login') {
    $user = authenticate_user_or_fail($pdo, $phone, $password);

    echo json_encode(["success" => true, "data" => build_profile($user)]);
    exit;
}

if ($action === 'register') {
    if ($phone === '' || $password === '') {
        http_response_code(400);
        echo json_encode(["error" => "Specificare numero di telefono e password"]);
        exit;
    }

    $site_email = resolve_site_email($email, $phone);

    // La PK e' `site_email`: se e' gia' preso l'account esiste. Il messaggio
    // e' generico per non confermare quale indirizzo e' registrato.
    $stmt = $pdo->prepare("SELECT 1 FROM utenti WHERE site_email = ?");
    $stmt->execute([$site_email]);
    if ($stmt->fetchColumn()) {
        http_response_code(409);
        echo json_encode(["error" => "Account già registrato"]);
        exit;
    }

    // Il telefono resta UNIQUE e viene ancora verificato: due account con lo
    // stesso numero sarebbero la stessa persona due volte, e il login lo cerca
    // con `WHERE IDutente = ?`.
    $stmt = $pdo->prepare("SELECT 1 FROM utenti WHERE IDutente = ?");
    $stmt->execute([$phone]);
    if ($stmt->fetchColumn()) {
        http_response_code(409);
        echo json_encode(["error" => "Numero di telefono già registrato"]);
        exit;
    }

    $normalized_name = $name === '' ? 'Nuovo utente' : $name;
    $password_hash = password_hash($password, PASSWORD_BCRYPT);

    $stmt = $pdo->prepare("INSERT INTO utenti (
                                site_email, real_email, IDutente, nome, cognome, nickname, password_hash, dataCreazione,
                                preferred_language, profile_bio, profile_photo_url, profile_audio_url,
                                profile_audio_duration_seconds, e2ee_public_key, two_factor_enabled,
                                two_factor_channel, two_factor_destination
                           )
                           VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_DATE, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([
        // `site_email` e la PK: se il client manda un indirizzo di dominio
        // si usa quello, altrimenti se ne deriva uno dal telefono. Il dominio
        // e' applicato dal CHECK della tabella, quindi qui basta costruirlo
        // bene: far fallire la registrazione perche' l'utente non ha ancora
        // una casella del sito sarebbe un motivo per non registrarsi.
        $site_email,
        $email === '' ? $site_email : $email,
        $phone,
        $normalized_name,
        'Utente',
        $normalized_name,
        $password_hash,
        $normalized_language,
        $normalized_bio,
        $normalized_photo,
        $normalized_audio,
        $normalized_audio === null ? null : $audio_duration,
        $normalized_e2ee_public_key,
        // `false` diventerebbe la stringa vuota, che pdo_pgsql rifiuta su una
        // colonna BOOLEAN: vedi resources/bool.php. Senza questo, la
        // registrazione di chi non attiva il 2FA fallirebbe — cioe' quasi
        // tutti.
        sql_bool($two_factor_enabled),
        $normalized_2fa_channel,
        $normalized_2fa_destination
    ]);

    $user = [
        'IDutente' => $phone,
        'nome' => $normalized_name,
        'nickname' => $normalized_name,
        'email' => $email === '' ? null : $email,
        'preferred_language' => $normalized_language,
        'profile_bio' => $normalized_bio,
        'profile_photo_url' => $normalized_photo,
        'profile_audio_url' => $normalized_audio,
        'profile_audio_duration_seconds' => $normalized_audio === null ? null : $audio_duration,
        'e2ee_public_key' => $normalized_e2ee_public_key,
        'two_factor_enabled' => $two_factor_enabled,
        'two_factor_channel' => $normalized_2fa_channel,
        'two_factor_destination' => $normalized_2fa_destination
    ];

    echo json_encode(["success" => true, "data" => build_profile($user)]);
    exit;
}

if ($action === 'enable_2fa') {
    authenticate_user_or_fail($pdo, $phone, $password);
    if ($normalized_2fa_channel === null || $normalized_2fa_destination === null) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare canale e destinazione per la 2FA"]);
        exit;
    }

    $stmt = $pdo->prepare("UPDATE utenti
                           SET two_factor_enabled = TRUE,
                               two_factor_channel = ?,
                               two_factor_destination = ?
                           WHERE IDutente = ?");
    $stmt->execute([$normalized_2fa_channel, $normalized_2fa_destination, $phone]);
    echo json_encode(["success" => true, "message" => "2FA abilitata"]);
    exit;
}

if ($action === 'certify_pec') {
    authenticate_user_or_fail($pdo, $phone, $password);
    $stmt = $pdo->prepare("UPDATE utenti
                           SET pec_certified_at = CURRENT_TIMESTAMP
                           WHERE IDutente = ? AND two_factor_enabled = TRUE");
    $stmt->execute([$phone]);
    if ($stmt->rowCount() === 0) {
        http_response_code(400);
        echo json_encode(["error" => "Per la certificazione è necessaria la 2FA abilitata"]);
        exit;
    }
    echo json_encode(["success" => true, "message" => "Utente certificato in stile PEC"]);
    exit;
}

http_response_code(400);
echo json_encode(["error" => "Action non valida. Usa login, register, guest_login, enable_2fa o certify_pec"]);
