<?php
if (!$current_user_id) {
    http_response_code(401);
    echo json_encode(["error" => "Utente non autenticato"]);
    exit;
}

const DEFAULT_FILE_LIMIT_BYTES = 52428800;

function resolve_preview_type(string $mime_type, string $file_name, ?string $source_url): string {
    $normalized_mime = strtolower(trim($mime_type));
    $normalized_name = strtolower(trim($file_name));

    if ($source_url !== null && preg_match('/^https?:\/\//i', $source_url) === 1) {
        return 'link';
    }
    if (str_starts_with($normalized_mime, 'audio/')) {
        return 'audio';
    }
    if ($normalized_mime === 'application/pdf' || str_ends_with($normalized_name, '.pdf')) {
        return 'pdf';
    }
    if ($normalized_mime === 'image/gif' || str_ends_with($normalized_name, '.gif')) {
        return 'gif';
    }
    if (str_starts_with($normalized_mime, 'image/')) {
        return 'image';
    }
    if (str_starts_with($normalized_mime, 'video/')) {
        return 'video';
    }
    return 'file';
}

function build_preview_payload(
    string $preview_type,
    string $file_name,
    string $mime_type,
    ?string $source_url
): array {
    $payload = [
        "title" => $file_name,
        "mime_type" => $mime_type
    ];

    if ($source_url !== null) {
        $payload["url"] = $source_url;
        if ($preview_type === 'link') {
            $host = parse_url($source_url, PHP_URL_HOST);
            $payload["host"] = $host;
        }
    }

    return $payload;
}

if ($method === 'POST') {
    $file_name = trim($input['file_name'] ?? '');
    $mime_type = trim($input['mime_type'] ?? 'application/octet-stream');
    $size_bytes = intval($input['size_bytes'] ?? 0);
    $source_url = trim($input['source_url'] ?? '');
    $admin_password = strval($input['admin_password'] ?? '');
    $override_limit = boolval($input['override_limit'] ?? false);

    if ($file_name === '' || $size_bytes <= 0) {
        http_response_code(400);
        echo json_encode(["error" => "Specificare file_name e size_bytes > 0"]);
        exit;
    }

    $limit_bypassed = false;
    if ($size_bytes > DEFAULT_FILE_LIMIT_BYTES) {
        $expected_admin_password = getenv('CRIMSON_CHAT_ADMIN_BYPASS_PASSWORD');
        if ($expected_admin_password === false || $expected_admin_password === '') {
            $expected_admin_password = 'SEGRETO_DA_RUOTARE';
        }
        $has_bypass = $override_limit && $admin_password !== '' && hash_equals($expected_admin_password, $admin_password);
        if (!$has_bypass) {
            http_response_code(403);
            echo json_encode([
                "error" => "File oltre 50MB: inserire password admin per il bypass",
                "max_size_bytes" => DEFAULT_FILE_LIMIT_BYTES
            ]);
            exit;
        }
        $limit_bypassed = true;
    }

    $normalized_source = $source_url === '' ? null : $source_url;
    $preview_type = resolve_preview_type($mime_type, $file_name, $normalized_source);
    $preview_payload = build_preview_payload($preview_type, $file_name, $mime_type, $normalized_source);
    $preview_json = json_encode($preview_payload, JSON_UNESCAPED_SLASHES);

    $stmt = $pdo->prepare("INSERT INTO shared_files (
                                owner_user_id, file_name, mime_type, size_bytes, source_url,
                                preview_type, preview_payload, bypassed_limit
                           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([
        $current_user_id,
        $file_name,
        $mime_type,
        $size_bytes,
        $normalized_source,
        $preview_type,
        $preview_json,
        $limit_bypassed ? 1 : 0
    ]);

    echo json_encode([
        "success" => true,
        "data" => [
            "id" => strval($pdo->lastInsertId()),
            "file_name" => $file_name,
            "mime_type" => $mime_type,
            "size_bytes" => $size_bytes,
            "limit_bypassed" => $limit_bypassed,
            "preview_type" => $preview_type,
            "preview_payload" => $preview_payload
        ]
    ]);
    exit;
}

if ($method === 'GET') {
    $stmt = $pdo->prepare("SELECT id, file_name, mime_type, size_bytes, source_url, preview_type, preview_payload, bypassed_limit, created_at
                           FROM shared_files
                           WHERE owner_user_id = ?
                           ORDER BY created_at DESC");
    $stmt->execute([$current_user_id]);
    $rows = $stmt->fetchAll();
    $files = array_map(function ($row) {
        $row['id'] = strval($row['id']);
        $row['size_bytes'] = intval($row['size_bytes']);
        $row['bypassed_limit'] = boolval($row['bypassed_limit']);
        $row['preview_payload'] = json_decode($row['preview_payload'] ?? '{}', true);
        return $row;
    }, $rows);
    echo json_encode(["success" => true, "data" => $files]);
    exit;
}

http_response_code(405);
echo json_encode(["error" => "Metodo non consentito"]);
