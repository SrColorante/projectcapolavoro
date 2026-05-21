<?php
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
    exit;
}

$action = $input['action'] ?? null;
$email = trim($input['email'] ?? '');
$password = $input['password'] ?? '';
$name = trim($input['name'] ?? '');
$preferred_language = trim($input['preferred_language'] ?? 'en');
$profile_bio = trim($input['profile_bio'] ?? '');
$profile_photo_url = trim($input['profile_photo_url'] ?? '');
$profile_audio_url = trim($input['profile_audio_url'] ?? '');
$audio_duration = floatval($input['profile_audio_duration_seconds'] ?? 0);
$e2ee_public_key = trim($input['e2ee_public_key'] ?? '');
$two_factor_enabled = ($input['two_factor_enabled'] ?? false) ? 1 : 0;
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
        "id" => strval($user['IDutente']),
        "name" => $user['nome'],
        "nickname" => $user['nickname'],
        "email" => $user['email'],
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
                                IDutente, nome, cognome, nickname, email, password_hash, dataCreazione,
                                is_guest, preferred_language, e2ee_public_key
                           ) VALUES (?, ?, ?, ?, ?, ?, CURDATE(), 1, ?, ?)");
    $stmt->execute([
        $guest_id,
        $guest_name,
        'Utente',
        $guest_name,
        $guest_email,
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

if ($email === '' || $password === '') {
    http_response_code(400);
    echo json_encode(["error" => "Specificare email e password"]);
    exit;
}

function authenticate_user_or_fail(PDO $pdo, string $email, string $password): array {
    $stmt = $pdo->prepare("SELECT * FROM utenti WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch();
    if (!$user || !password_verify($password, $user['password_hash'])) {
        http_response_code(401);
        echo json_encode(["error" => "Credenziali non valide"]);
        exit;
    }
    return $user;
}

if ($action === 'login') {
    $user = authenticate_user_or_fail($pdo, $email, $password);

    echo json_encode(["success" => true, "data" => build_profile($user)]);
    exit;
}

if ($action === 'register') {
    $stmt = $pdo->prepare("SELECT 1 FROM utenti WHERE email = ?");
    $stmt->execute([$email]);
    if ($stmt->fetchColumn()) {
        http_response_code(409);
        echo json_encode(["error" => "Email già registrata"]);
        exit;
    }

    $normalized_name = $name === '' ? 'Nuovo utente' : $name;
    $user_id = generate_unique_user_id($pdo);
    $password_hash = password_hash($password, PASSWORD_BCRYPT);

    $stmt = $pdo->prepare("INSERT INTO utenti (
                                IDutente, nome, cognome, nickname, email, password_hash, dataCreazione,
                                preferred_language, profile_bio, profile_photo_url, profile_audio_url,
                                profile_audio_duration_seconds, e2ee_public_key, two_factor_enabled,
                                two_factor_channel, two_factor_destination
                           )
                           VALUES (?, ?, ?, ?, ?, ?, CURDATE(), ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([
        $user_id,
        $normalized_name,
        'Utente',
        $normalized_name,
        $email,
        $password_hash,
        $normalized_language,
        $normalized_bio,
        $normalized_photo,
        $normalized_audio,
        $normalized_audio === null ? null : $audio_duration,
        $normalized_e2ee_public_key,
        $two_factor_enabled,
        $normalized_2fa_channel,
        $normalized_2fa_destination
    ]);

    $user = [
        'IDutente' => $user_id,
        'nome' => $normalized_name,
        'nickname' => $normalized_name,
        'email' => $email,
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
    authenticate_user_or_fail($pdo, $email, $password);
    if ($normalized_2fa_channel === null || $normalized_2fa_destination === null) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare canale e destinazione per la 2FA"]);
        exit;
    }

    $stmt = $pdo->prepare("UPDATE utenti
                           SET two_factor_enabled = 1,
                               two_factor_channel = ?,
                               two_factor_destination = ?
                           WHERE email = ?");
    $stmt->execute([$normalized_2fa_channel, $normalized_2fa_destination, $email]);
    echo json_encode(["success" => true, "message" => "2FA abilitata"]);
    exit;
}

if ($action === 'certify_pec') {
    authenticate_user_or_fail($pdo, $email, $password);
    $stmt = $pdo->prepare("UPDATE utenti
                           SET pec_certified_at = NOW()
                           WHERE email = ? AND two_factor_enabled = 1");
    $stmt->execute([$email]);
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
