<?php
if (!$current_user_id) {
    http_response_code(401);
    echo json_encode(["error" => "Utente non autenticato"]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
if ($method === 'GET') {
    $stmt = $pdo->prepare("SELECT preferred_language, nickname, profile_bio, profile_photo_url, profile_audio_url, profile_audio_duration_seconds
                           FROM utenti
                           WHERE IDutente = ?");
    $stmt->execute([$current_user_id]);
    $user_settings = $stmt->fetch();

    $language = 'en';
    $nickname = null;
    $profile_bio = null;
    $profile_photo_url = null;
    $profile_audio_url = null;
    $profile_audio_duration_seconds = null;
    if ($user_settings) {
        $language = $user_settings['preferred_language'] ?? 'en';
        $nickname = $user_settings['nickname'] ?? null;
        $profile_bio = $user_settings['profile_bio'] ?? null;
        $profile_photo_url = $user_settings['profile_photo_url'] ?? null;
        $profile_audio_url = $user_settings['profile_audio_url'] ?? null;
        $profile_audio_duration_seconds = isset($user_settings['profile_audio_duration_seconds'])
            ? floatval($user_settings['profile_audio_duration_seconds'])
            : null;
    }

    echo json_encode([
        "success" => true,
        "data" => [
            "notifiche_attive" => true,
            "tema" => "scuro",
            "preferred_language" => strtolower($language),
            "nickname" => $nickname,
            "profile_bio" => $profile_bio,
            "profile_photo_url" => $profile_photo_url,
            "profile_audio_url" => $profile_audio_url,
            "profile_audio_duration_seconds" => $profile_audio_duration_seconds
        ]
    ]);

} elseif ($method === 'POST' || $method === 'PATCH') {
    $preferred_language = strtolower(trim($input['preferred_language'] ?? ''));
    if ($preferred_language !== '' && preg_match('/^[a-z]{2}$/', $preferred_language) !== 1) {
        http_response_code(400);
        echo json_encode(["error" => "preferred_language deve essere composto da 2 lettere"]);
        exit;
    }

    $nickname = trim($input['nickname'] ?? '');
    $profile_bio = trim($input['profile_bio'] ?? '');
    $profile_photo_url = trim($input['profile_photo_url'] ?? '');
    $profile_audio_url = trim($input['profile_audio_url'] ?? '');
    $profile_audio_duration_seconds = isset($input['profile_audio_duration_seconds'])
        ? floatval($input['profile_audio_duration_seconds'])
        : null;

    if ($profile_audio_url !== '' && ($profile_audio_duration_seconds === null || $profile_audio_duration_seconds > 5.0 || $profile_audio_duration_seconds <= 0)) {
        http_response_code(400);
        echo json_encode(["error" => "La descrizione audio deve durare tra 0 e 5 secondi"]);
        exit;
    }

    $stmt = $pdo->prepare("UPDATE utenti
                           SET preferred_language = COALESCE(NULLIF(?, ''), preferred_language),
                               nickname = COALESCE(NULLIF(?, ''), nickname),
                               profile_bio = NULLIF(?, ''),
                               profile_photo_url = NULLIF(?, ''),
                               profile_audio_url = NULLIF(?, ''),
                               profile_audio_duration_seconds = ?
                           WHERE IDutente = ?");
    $stmt->execute([
        $preferred_language,
        $nickname,
        $profile_bio,
        $profile_photo_url,
        $profile_audio_url,
        $profile_audio_url === '' ? null : $profile_audio_duration_seconds,
        $current_user_id
    ]);

    echo json_encode(["success" => true, "message" => "Impostazioni salvate", "payload" => $input]);

} else {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
}
?>
