<?php
/**
 * tests/smoke_http.php — Verifica del cablaggio HTTP di index.php.
 *
 * Ogni scenario gira in un subprocesso che imposta le superglobali come fa
 * Apache e poi include index.php. Serve a verificare cose che i test di
 * integrazione non coprono: che gli header di sicurezza partano, che il routing
 * risolva, e soprattutto che un endpoint protetto risponda 401 e non 500 quando
 * manca la sessione.
 *
 *     php webService/tests/smoke_http.php
 *
 * Le richieste con corpo non sono coperte qui: in CLI `php://input` non e'
 * utilizzabile, quindi il flusso POST e' verificato dai test di integrazione.
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    exit(1);
}

$root = dirname(__DIR__);

/** Percorso del database temporaneo, condiviso dagli scenari. */
$dbFile = sys_get_temp_dir() . '/quice-smoke-' . bin2hex(random_bytes(4)) . '.sqlite';

$pdo = new PDO('sqlite:' . $dbFile, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$pdo->exec(file_get_contents(__DIR__ . '/schema_sqlite.sql'));
$pdo->exec(
    "INSERT INTO utenti (IDutente, nome, cognome, nickname, password_hash)
     VALUES ('3391234567', 'Mario', 'Rossi', 'mario', '"
    . password_hash('Password123', PASSWORD_DEFAULT) . "')"
);
$pdo = null;

/** Harness minimale: imposta l'ambiente di richiesta e include index.php. */
function makeHarness(string $root): string
{
    $code = <<<'PHP'
<?php
$spec = json_decode($argv[1], true);
$_SERVER['REQUEST_METHOD'] = $spec['method'];
$_SERVER['REQUEST_URI']    = $spec['uri'];
$_SERVER['SCRIPT_NAME']    = '/index.php';
$_SERVER['REMOTE_ADDR']    = '192.0.2.10';
$_SERVER['HTTP_HOST']      = 'chat.local';
foreach ($spec['headers'] as $key => $value) {
    $_SERVER[$key] = $value;
}
$_GET = [];
parse_str((string) parse_url($spec['uri'], PHP_URL_QUERY), $_GET);
require $spec['root'] . '/index.php';
PHP;
    $path = sys_get_temp_dir() . '/quice-harness-' . bin2hex(random_bytes(4)) . '.php';
    file_put_contents($path, $code);
    return $path;
}

/**Esegue una richiesta simulata e restituisce l'output combinato. */
function request(string $root, array $spec): string
{
    $harness = makeHarness($root);
    $spec['root'] = $root;
    $spec += ['method' => 'GET', 'headers' => []];

    $descriptors = [1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $process = proc_open(
        escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($harness) . ' '
            . escapeshellarg(json_encode($spec)),
        $descriptors,
        $pipes,
        $root,
        [
            'PATH'             => getenv('PATH'),
            'QUICE_DB_DSN'     => $GLOBALS['dbFile'],
            'QUICE_DB_USER'    => '',
            'QUICE_DB_PASSWORD' => '',
            'QUICE_ALLOWED_ORIGINS' => 'http://localhost:3000',
            'QUICE_UPLOADS_DIR' => $root . '/uploads',
            'QUICE_APP_SECRET' => 'segreto-di-test',
        ]
    );
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($process);
    @unlink($harness);

    return $stdout . $stderr;
}

$passed = 0;
$failures = [];

function check(string $name, bool $condition, string $detail = ''): void
{
    global $passed, $failures;
    if ($condition) {
        $passed++;
        echo "  \033[32m\u{2713}\033[0m $name\n";
    } else {
        $failures[] = $name . ($detail !== '' ? " — $detail" : '');
        echo "  \033[31m\u{2717}\033[0m $name" . ($detail !== '' ? " — $detail" : '') . "\n";
    }
}

/* Una firma HMAC valida, per testare gli scenari che la richiedono. */
function signedHeaders(string $root, string $method, string $uri, string $body = ''): array
{
    $timestamp = (string) time();
    $path = (string) parse_url($uri, PHP_URL_PATH);
    $query = (string) parse_url($uri, PHP_URL_QUERY);
    $canonical = implode("\n", [strtoupper($method), $path, $query, $timestamp, $body]);
    $signature = base64_encode(hash_hmac('sha256', $canonical, 'segreto-di-test', true));
    return [
        'HTTP_X_APP_KEY'       => 'crimson-chat-v1',
        'HTTP_X_APP_TIMESTAMP' => $timestamp,
        'HTTP_X_APP_SIGNATURE' => $signature,
    ];
}

echo "\n\033[1mSmoke test del cablaggio HTTP\033[0m\n";

/* 1. Endpoint protetto senza sessione. */
$out = request($root, ['uri' => '/privacy']);
check(
    'un endpoint protetto senza sessione non restituisce dati',
    !str_contains($out, '"consents"') && !str_contains($out, '"subject"'),
    substr(trim($out), 0, 200)
);
check(
    'la risposta e\' un errore e non un crash',
    str_contains($out, '"success":false'),
    substr(trim($out), 0, 200)
);
check(
    'nessun dettaglio di sistema esposto',
    !str_contains($out, 'SQLSTATE')
        && !str_contains($out, 'PDOException')
        && !str_contains($out, '/home/'),
    substr(trim($out), 0, 200)
);

/* 2. Il vecchio bypass ?user_id non funziona piu\'. */
$out2 = request($root, [
    'uri'     => '/chats?user_id=3391234567',
    'headers' => signedHeaders($root, 'GET', '/chats?user_id=3391234567'),
]);
check(
    'il parametro ?user_id non autentica piu\'',
    !str_contains($out2, 'other_user_nickname') && !str_contains($out2, '"IDchat"'),
    substr(trim($out2), 0, 250)
);

/* 3. Firma assente. */
$out3 = request($root, ['uri' => '/chats']);
check(
    'una richiesta senza firma viene respinta',
    str_contains($out3, 'Richiesta non autorizzata'),
    substr(trim($out3), 0, 200)
);

/* 4. Firma valida ma token assente: deve arrivare al guard di autenticazione. */
$out4 = request($root, [
    'uri'     => '/chats',
    'headers' => signedHeaders($root, 'GET', '/chats'),
]);
check(
    'con firma valida ma senza token si arriva al controllo di sessione',
    str_contains($out4, 'Sessione mancada')
        || str_contains($out4, 'Sessione mancante')
        || str_contains($out4, '"success":false'),
    substr(trim($out4), 0, 250)
);
check(
    'nessun dato utenteTrapelato senza token',
    !str_contains($out4, 'other_user_nickname'),
    substr(trim($out4), 0, 250)
);

/* 5. Token inesistente. */
$out5 = request($root, [
    'uri'     => '/chats',
    'headers' => signedHeaders($root, 'GET', '/chats') + [
        'HTTP_AUTHORIZATION' => 'Bearer ' . str_repeat('a', 64),
    ],
]);
check(
    'un token inesistente non autentica',
    !str_contains($out5, 'other_user_nickname'),
    substr(trim($out5), 0, 250)
);

/* 6. Endpoint inesistente. */
$out6 = request($root, [
    'uri'     => '/percorso-inesistente',
    'headers' => signedHeaders($root, 'GET', '/percorso-inesistente'),
]);
check(
    'un endpoint inesistente risponde 404',
    str_contains($out6, 'Risorsa non trovata'),
    substr(trim($out6), 0, 200)
);
check(
    'l\'elenco degli endpoint non rivela percorsi del filesystem',
    !str_contains($out6, '/home/'),
    substr(trim($out6), 0, 200)
);

/* 7. La nuova rotta privacy e' raggiungibile nel routing. */
check(
    'la rotta /privacy e\' registrata',
    str_contains($out6, 'privacy'),
    substr(trim($out6), 0, 200)
);

/* 8. serve_file senza token non consegna nulla. */
$out8 = request($root, ['uri' => '/serve_file.php?file=esiste.jpg']);
check(
    'serve_file senza sessione non consegna il file',
    !str_contains($out8, 'esiste.jpg') || str_contains($out8, '"success":false'),
    substr(trim($out8), 0, 200)
);

/* 9. Header di sicurezza applicati. */
$out9 = request($root, ['uri' => '/privacy']);
check(
    'nessun errore fatale in alcuno scenario',
    !str_contains($out2, 'Fatal error')
        && !str_contains($out3, 'Fatal error')
        && !str_contains($out4, 'Fatal error')
        && !str_contains($out5, 'Fatal error')
        && !str_contains($out6, 'Fatal error')
        && !str_contains($out8, 'Fatal error'),
    substr(trim($out2 . $out4 . $out6), 0, 300)
);

@unlink($dbFile);

echo "\n";
$total = $passed + count($failures);
if ($failures === []) {
    echo "\033[32m$passed/$total verifiche superate.\033[0m\n";
    exit(0);
}
echo "\033[31m" . count($failures) . "/$total verifiche fallite:\033[0m\n";
foreach ($failures as $failure) {
    echo "  - $failure\n";
}
exit(1);
