<?php
if ($method !== 'POST') {
    http_response_code(405);
    echo json_encode(["error" => "Metodo non consentito"]);
    exit;
}

$action = $input['action'] ?? '';

function generate_e2ee_keypair(): array {
    if (function_exists('sodium_crypto_box_keypair')) {
        $keypair = sodium_crypto_box_keypair();
        return [
            "algorithm" => "x25519-xsalsa20poly1305",
            "public_key" => base64_encode(sodium_crypto_box_publickey($keypair)),
            "private_key" => base64_encode(sodium_crypto_box_secretkey($keypair))
        ];
    }

    $resource = openssl_pkey_new([
        "private_key_bits" => 2048,
        "private_key_type" => OPENSSL_KEYTYPE_RSA
    ]);
    if ($resource === false) {
        http_response_code(500);
        echo json_encode(["error" => "Impossibile generare una keypair E2EE"]);
        exit;
    }

    openssl_pkey_export($resource, $private_key);
    $details = openssl_pkey_get_details($resource);

    return [
        "algorithm" => "rsa-oaep-2048",
        "public_key" => $details['key'],
        "private_key" => $private_key
    ];
}

if ($action === 'generate_e2ee_keypair') {
    echo json_encode(["success" => true, "data" => generate_e2ee_keypair()]);
    exit;
}

if ($action === 'prepare_encrypted_message') {
    $ciphertext = trim($input['ciphertext'] ?? '');
    $sender_public_key = trim($input['sender_public_key'] ?? '');
    $recipient_public_key = trim($input['recipient_public_key'] ?? '');

    if ($ciphertext === '' || $sender_public_key === '' || $recipient_public_key === '') {
        http_response_code(400);
        echo json_encode(["error" => "Specificare ciphertext e chiavi E2EE di mittente/destinatario"]);
        exit;
    }

    echo json_encode([
        "success" => true,
        "data" => [
            "ciphertext" => $ciphertext,
            "sender_public_key" => $sender_public_key,
            "recipient_public_key" => $recipient_public_key,
            "created_at" => gmdate('c')
        ]
    ]);
    exit;
}

http_response_code(400);
echo json_encode(["error" => "Action non valida. Usa generate_e2ee_keypair o prepare_encrypted_message"]);
