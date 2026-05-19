<?php
if ($method !== 'POST') {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
    exit;
}

$action = $input['action'] ?? null;
$email = trim($input['email'] ?? '');
$password = $input['password'] ?? '';
$name = trim($input['name'] ?? '');

if (!$action || $email === '' || $password === '') {
    http_response_code(400);
    echo json_encode(["error" => "Specificare action, email e password"]);
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
        "email" => $user['email']
    ];
}

if ($action === 'login') {
    $stmt = $pdo->prepare("SELECT * FROM utenti WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch();

    if (!$user || !password_verify($password, $user['password_hash'])) {
        http_response_code(401);
        echo json_encode(["error" => "Credenziali non valide"]);
        exit;
    }

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

    $stmt = $pdo->prepare("INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash, dataCreazione)
                           VALUES (?, ?, ?, ?, ?, ?, CURDATE())");
    $stmt->execute([
        $user_id,
        $normalized_name,
        'Utente',
        $normalized_name,
        $email,
        $password_hash
    ]);

    $user = [
        'IDutente' => $user_id,
        'nome' => $normalized_name,
        'nickname' => $normalized_name,
        'email' => $email
    ];

    echo json_encode(["success" => true, "data" => build_profile($user)]);
    exit;
}

http_response_code(400);
echo json_encode(["error" => "Action non valida. Usa login o register"]);
