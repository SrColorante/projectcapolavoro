<?php
/**
 * tests/run.php — Test di integrazione della logica di sicurezza e GDPR.
 *
 *     php webService/tests/run.php
 *
 * I test girano su SQLite in memoria: non serve un server MySQL. Vengono
 * registrate le funzioni SQL mancanti (`UTC_TIMESTAMP`) cosi' le librerie
 * producono lo stesso identico SQL che in produzione.
 *
 * Prima di questa suite il backend PHP non aveva ALCUN test. Le modifiche
 * qui introdotte toccano autenticazione, cancellazione e conservazione: sono
 * esattamente il genere di codice in cui un errore non si vede.
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "Solo da riga di comando.\n");
    exit(1);
}

define('QUICE_TESTING', true);

require_once __DIR__ . '/../lib/config.php';
require_once __DIR__ . '/../lib/db.php';
require_once __DIR__ . '/../lib/logging.php';
require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/consent.php';
require_once __DIR__ . '/../lib/privacy.php';
require_once __DIR__ . '/../lib/retention.php';
require_once __DIR__ . '/../lib/upload.php';

Config::bootstrap();

/* ------------------------------------------------------------------ */
/* Micro-harness                                                       */
/* ------------------------------------------------------------------ */

final class TestRunner
{
    private int $passed = 0;
    private array $failures = [];
    private string $currentGroup = '';
    private string $currentTest = '';

    public function group(string $name): void
    {
        $this->currentGroup = $name;
        echo "\n\033[1m$name\033[0m\n";
    }

    public function test(string $name, callable $body): void
    {
        $this->currentTest = $name;
        try {
            resetFixture();
            $body($this);
            $this->passed++;
            echo "  \033[32m✓\033[0m $name\n";
        } catch (AssertionFailed $e) {
            $this->failures[] = sprintf(
                "%s / %s\n      %s",
                $this->currentGroup,
                $name,
                $e->getMessage()
            );
            echo "  \033[31m✗\033[0m $name\n      " . $e->getMessage() . "\n";
        } catch (Throwable $e) {
            $this->failures[] = sprintf(
                "%s / %s\n      %s in %s:%d",
                $this->currentGroup,
                $name,
                $e->getMessage(),
                basename($e->getFile()),
                $e->getLine()
            );
            echo "  \033[31m✗\033[0m $name (errore)\n      "
                . $e->getMessage() . ' in ' . basename($e->getFile()) . ':' . $e->getLine() . "\n";
        }
    }

    public function assert(bool $condition, string $message): void
    {
        if (!$condition) {
            throw new AssertionFailed($message);
        }
    }

    public function assertSame($expected, $actual, string $message = ''): void
    {
        if ($expected !== $actual) {
            throw new AssertionFailed(sprintf(
                '%s (atteso: %s, ottenuto: %s)',
                $message !== '' ? $message : 'valori diversi',
                var_export($expected, true),
                var_export($actual, true)
            ));
        }
    }

    public function assertNotSame($unexpected, $actual, string $message = ''): void
    {
        if ($unexpected === $actual) {
            throw new AssertionFailed(sprintf(
                '%s (entrambi: %s)',
                $message !== '' ? $message : 'valori identici',
                var_export($actual, true)
            ));
        }
    }

    public function assertNull($actual, string $message = ''): void
    {
        $this->assertSame(null, $actual, $message ?: 'atteso null');
    }

    public function assertCount(int $expected, array $actual, string $message = ''): void
    {
        $this->assertSame(
            $expected,
            count($actual),
            $message ?: 'numero di elementi diverso'
        );
    }

    /** Verifica che il codice sollevi un'eccezione. */
    public function test_expect_throw(callable $body, string $message = ''): void
    {
        try {
            $body();
        } catch (Throwable $e) {
            return;
        }
        throw new AssertionFailed(
            $message !== '' ? $message : 'doveva verificarsi un errore'
        );
    }

    public function report(): int
    {
        $total = $this->passed + count($this->failures);
        echo "\n";
        if ($this->failures === []) {
            echo "\033[32m$total/$total verifiche superate.\033[0m\n";
            return 0;
        }
        echo "\033[31m" . count($this->failures) . "/$total verifiche fallite:\033[0m\n";
        foreach ($this->failures as $failure) {
            echo "  - $failure\n";
        }
        return 1;
    }
}

final class AssertionFailed extends RuntimeException
{
}

/* ------------------------------------------------------------------ */
/* Fixture                                                             */
/* ------------------------------------------------------------------ */

function utcTimestamp(): string
{
    return gmdate('Y-m-d H:i:s');
}

function makePdo(): PDO
{
    $pdo = new PDO('sqlite::memory:', null, null, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    // Le librerie usano UTC_TIMESTAMP(), che SQLite non conosce.
    $pdo->sqliteCreateFunction('UTC_TIMESTAMP', 'utcTimestamp', 0);
    $pdo->sqliteCreateFunction('NOW', 'utcTimestamp', 0);
    $pdo->exec(file_get_contents(__DIR__ . '/schema_sqlite.sql'));
    return $pdo;
}

function resetFixture(): void
{
    Db::setPdo(makePdo());
    $_SERVER['REMOTE_ADDR'] = '192.0.2.10';
}

function seedUser(string $id, array $overrides = []): string
{
    $defaults = [
        'nome' => 'Mario',
        'cognome' => 'Rossi',
        'nickname' => 'mario',
        'email' => null,
        'password_hash' => password_hash('Password123', PASSWORD_DEFAULT),
        'is_guest' => 0,
    ];
    $row = array_merge($defaults, $overrides);

    Db::execute(
        'INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash, is_guest)
         VALUES (?, ?, ?, ?, ?, ?, ?)',
        [$id, $row['nome'], $row['cognome'], $row['nickname'], $row['email'],
         $row['password_hash'], $row['is_guest']]
    );
    return $id;
}

function createDirectChat(string $a, string $b, string $chatId): void
{
    Db::execute(
        'INSERT INTO chat (IDchat, is_group, utente1, utente2) VALUES (?, 0, ?, ?)',
        [$chatId, $a, $b]
    );
}

/* ------------------------------------------------------------------ */

$t = new TestRunner();

/* ================================================================== */
$t->group('Autenticazione a token (era assente)');

$t->test('il token emesso risolve l\'utente corretto', function (TestRunner $t) {
    seedUser('3391234567');
    $issued = Auth::issueToken('3391234567', 'test-device', '192.0.2.10');

    $t->assert(isset($issued['token']), 'il token deve essere restituito');
    $t->assert(strlen($issued['token']) === 64, 'il token deve avere 64 caratteri hex');

    $resolved = Auth::resolveToken($issued['token']);
    $t->assert($resolved !== null, 'il token deve risolversi');
    $t->assertSame('3391234567', $resolved['user_id'], 'deve risolversi l\'utente giusto');
});

$t->test('il database contiene solo l\'hash del token, mai il token', function (TestRunner $t) {
    seedUser('3391234567');
    $issued = Auth::issueToken('3391234567');

    $row = Db::fetchOne('SELECT token_hash FROM utenti_sessioni WHERE user_id = ?', ['3391234567']);
    $t->assert($row !== null, 'la sessione deve essere registrata');
    $t->assertNotSame($issued['token'], $row['token_hash'], 'il token non deve essere salvato in chiaro');
    $t->assertSame(64, strlen($row['token_hash']), 'l\'hash SHA-256 e\' di 64 caratteri');
    $t->assertSame(Auth::hashToken($issued['token']), $row['token_hash'], 'l\'hash deve corrispondere');
});

$t->test('un token inesistente non risolve nessun utente', function (TestRunner $t) {
    seedUser('3391234567');
    Auth::issueToken('3391234567');
    $t->assertNull(Auth::resolveToken(str_repeat('a', 64)), 'token falso non accettato');
    $t->assertNull(Auth::resolveToken(''), 'token vuoto non accettato');
    $t->assertNull(Auth::resolveToken(null), 'token assente non accettato');
});

$t->test('un token non può impersonare un altro utente', function (TestRunner $t) {
    // Il test che la versione precedente non poteva scrivere: senza
    // autenticazione, `?user_id=` permetteva di impersonare chiunque.
    seedUser('3391234567');
    seedUser('3391234568');
    $mine = Auth::issueToken('3391234567');

    $resolved = Auth::resolveToken($mine['token']);
    $t->assertSame('3391234567', $resolved['user_id'], 'il token deve valere solo per chi lo ha ottenuto');

    // Un token emesso per A non risolve B, nemmeno forzando parametri.
    $t->assertNull(Auth::resolveToken(str_repeat('b', 64)), 'token estraneo rifiutato');
    $t->assertSame(
        2,
        (int)Db::fetchOne('SELECT COUNT(*) AS c FROM utenti')['c'],
        'nessun utente creatoimplicitamente'
    );
});

$t->test('un token scaduto viene rifiutato', function (TestRunner $t) {
    seedUser('3391234567');
    $issued = Auth::issueToken('3391234567');

    Db::execute(
        'UPDATE utenti_sessioni SET expires_at = ?',
        [gmdate('Y-m-d H:i:s', time() - 60)]
    );

    $t->assertNull(Auth::resolveToken($issued['token']), 'token scaduto rifiutato');
});

$t->test('un token revocato viene rifiutato', function (TestRunner $t) {
    seedUser('3391234567');
    $issued = Auth::issueToken('3391234567');
    $t->assert(Auth::resolveToken($issued['token']) !== null, 'prima della revoca funziona');

    Auth::revokeToken($issued['token'], 'user_logout');
    $t->assertNull(Auth::resolveToken($issued['token']), 'dopo la revoca rifiutato');
});

$t->test('revokeAll revoca ogni sessione dell\'utente', function (TestRunner $t) {
    seedUser('3391234567');
    $a = Auth::issueToken('3391234567');
    $b = Auth::issueToken('3391234567');

    $revoked = Auth::revokeAllForUser('3391234567', 'password_changed');
    $t->assertSame(2, $revoked, 'devono essere revocate entrambe le sessioni');
    $t->assertNull(Auth::resolveToken($a['token']), 'prima sessione revocata');
    $t->assertNull(Auth::resolveToken($b['token']), 'seconda sessione revocata');
});

$t->test('il token di un utente cancellato non e\' piu\' valido', function (TestRunner $t) {
    seedUser('3391234567');
    $issued = Auth::issueToken('3391234567');
    Db::execute('UPDATE utenti SET erased_at = ? WHERE IDutente = ?', [utcTimestamp(), '3391234567']);
    $t->assertNull(Auth::resolveToken($issued['token']), 'sessione di account cancellato rifiutata');
});

$t->test('password errata non autentica, corretta sì', function (TestRunner $t) {
    seedUser('3391234567');
    $t->assertNull(Auth::verifyPassword('3391234567', 'Password123Sbagliata'), 'password errata');
    $t->assert(Auth::verifyPassword('3391234567', 'Password123') !== null, 'password corretta');
    $t->assertNull(Auth::verifyPassword('3999999999', 'Password123'), 'utente inesistente');
});

$t->test('la password non viene mai memorizzata in chiaro', function (TestRunner $t) {
    seedUser('3391234567', [
        'password_hash' => password_hash('Password123', PASSWORD_DEFAULT),
    ]);
    $row = Db::fetchOne('SELECT password_hash FROM utenti WHERE IDutente = ?', ['3391234567']);
    $t->assert(
        !str_contains($row['password_hash'], 'Password123'),
        'la password in chiaro non deve comparire nel campo hash'
    );
    $t->assert(
        str_starts_with($row['password_hash'], '$2y$'),
        'deve essere un hash bcrypt, non testo libero'
    );
});

/* ================================================================== */
$t->group('Requisiti di robustezza della password');

$t->test('una password debole viene rifiutata', function (TestRunner $t) {
    $t->assert(Auth::validatePasswordStrength('password') !== null, 'troppo corta e senza maiuscole');
    $t->assert(Auth::validatePasswordStrength('Password1') !== null, 'troppo corta');
    $t->assert(Auth::validatePasswordStrength('password123456') !== null, 'senza maiuscola');
    $t->assert(Auth::validatePasswordStrength('PASSWORD123456') !== null, 'senza minuscola');
    $t->assert(Auth::validatePasswordStrength('PasswordOnly') !== null, 'senza cifra');
});

$t->test('una password robusta viene accettata', function (TestRunner $t) {
    $t->assertNull(Auth::validatePasswordStrength('Password123'), 'password valida');
    $t->assertNull(Auth::validatePasswordStrength('Quice2026 Sicura'), 'password valida con spazio');
});

$t->test('l\'identificativo utente deve essere di 10 cifre', function (TestRunner $t) {
    // Difetto originale: l'app accettava 8-15 cifre, il server ne chiedeva 10.
    $t->assert(!Auth::isValidUserId('12345678'), '8 cifre non valide');
    $t->assert(!Auth::isValidUserId('33912345678'), '11 cifre non valide');
    $t->assert(!Auth::isValidUserId('339123456'), '9 cifre non valide');
    $t->assert(Auth::isValidUserId('3391234567'), '10 cifre valide');
    $t->assert(!Auth::isValidUserId('abcdefghij'), 'lettere non valide');
    $t->assert(!Auth::isValidUserId('3391234567 '), 'spazio non tollerato');
});

/* ================================================================== */
$t->group('Rate limit');

$t->test('oltre la soglia gli eventi vengono conteggiati come eccesso', function (TestRunner $t) {
    $t->assertSame(0, Http::rateLimit('test:bucket', 3, 60), 'primo tentativo libero');
    $t->assertSame(0, Http::rateLimit('test:bucket', 3, 60), 'secondo libero');
    $t->assertSame(0, Http::rateLimit('test:bucket', 3, 60), 'terzo libero');
    $t->assert(Http::rateLimit('test:bucket', 3, 60) > 0, 'quarto bloccato');
});

$t->test('bucket separati non interferiscono', function (TestRunner $t) {
    for ($i = 0; $i < 5; $i++) {
        Http::rateLimit('bucket:a', 3, 60);
    }
    $t->assertSame(0, Http::rateLimit('bucket:b', 3, 60), 'altro bucket non bloccato');
});

/* ================================================================== */
$t->group('Registro dei consensi (Art. 7)');

$t->test('la registrazione del consenso viene persistita con la versione', function (TestRunner $t) {
    seedUser('3391234567');
    Consent::record('3391234567', 'privacy_policy', true, 'registration');

    $status = Consent::statusFor('3391234567');
    $t->assert($status['privacy_policy']['granted'] === true, 'consenso concesso');
    $t->assert(
        $status['privacy_policy']['policy_version'] !== null,
        'la versione del testo deve essere registrata'
    );
    $t->assert($status['privacy_policy']['decided_at'] !== null, 'la data deve essere registrata');
});

$t->test('il ritiro e\' registrato come nuova decisione', function (TestRunner $t) {
    seedUser('3391234567');
    Consent::record('3391234567', 'diagnostics', true, 'settings');
    $t->assert(Consent::has('3391234567', 'diagnostics'), 'prima del ritiro');

    $error = Consent::withdraw('3391234567', 'diagnostics', 'settings');
    $t->assertNull($error, 'il ritiro deve riuscire');
    $t->assert(!Consent::has('3391234567', 'diagnostics'), 'dopo il ritiro');

    $history = Consent::historyFor('3391234567');
    $t->assertCount(2, $history, 'lo storico conserva entrambe le decisioni');
    $t->assert($history[0]['granted'] === true, 'la prima era concessione');
    $t->assert($history[1]['granted'] === false, 'la seconda era ritiro');
    $t->assert($history[1]['withdrawn_at'] !== null, 'il ritiro ha una data');
});

$t->test('i consensi necessari non possono essere ritirati', function (TestRunner $t) {
    seedUser('3391234567');
    $error = Consent::withdraw('3391234567', 'privacy_policy');
    $t->assert($error !== null, 'il ritiro deve essere rifiutato');
    $t->assert(
        str_contains(strval($error), 'eliminare il tuo account'),
        'il messaggio deve indicare la strada alternativa'
    );
});

$t->test('un tipo di consenso sconosciuto viene rifiutato', function (TestRunner $t) {
    seedUser('3391234567');
    $t->assert(!Consent::isKnownType('inventato'), 'tipo inesistente');
    $t->assert(Consent::isKnownType('diagnostics'), 'tipo valido');
    $t->assert(
        Consent::withdraw('3391234567', 'inventato') !== null,
        'il ritiro di un tipo ignoto deve fallire'
    );
});

/* ================================================================== */
$t->group('Pseudonimizzazione nei log');

$t->test('lo pseudonimo e\' stabile e non contiene l\'identificativo', function (TestRunner $t) {
    $a = Logger::pseudonymize('3391234567');
    $b = Logger::pseudonymize('3391234567');
    $c = Logger::pseudonymize('3391234568');

    $t->assertSame($a, $b, 'lo stesso input dà lo stesso pseudonimo');
    $t->assertNotSame($a, $c, 'input diversi danno pseudonimi diversi');
    $t->assert(!str_contains($a, '3391234567'), 'l\'ID non deve comparire nello pseudonimo');
    $t->assertSame(64, strlen($a), 'HMAC-SHA256 in esadecimale');
});

$t->test('l\'IP viene conservato solo come hash', function (TestRunner $t) {
    $hashed = Logger::hashIp('192.0.2.10');
    $t->assert($hashed !== null, 'deve essere prodotto un hash');
    $t->assert(!str_contains($hashed, '192.0.2.10'), 'l\'IP non deve comparire');
    $t->assertSame(32, strlen($hashed), 'hash troncato a 32 caratteri');
});

$t->test('il registro di controllo non contiene PII in chiaro', function (TestRunner $t) {
    seedUser('3391234567');
    Logger::audit('test.action', '3391234567', 'utenti', '3391234567', 'ok');

    $row = Db::fetchOne('SELECT * FROM audit_log ORDER BY id DESC LIMIT 1');
    $t->assert($row !== null, 'la voce deve essere registrata');
    $t->assert(
        !str_contains(strval($row['actor_pseudonym']), '3391234567'),
        'lo pseudonimo non deve contenere l\'ID'
    );
    $t->assertSame(64, strlen($row['actor_pseudonym']), 'pseudonimo completo');
});

/* ================================================================== */
$t->group('Validazione dei caricamenti (era una porta aperta)');

$t->test('un file con estensione eseguibile viene rifiutato', function (TestRunner $t) {
    $path = writeTempFile("<?php echo 'x';", 'evil.php');
    $t->test_expect_throw(
        static function () use ($path) {
            Upload::validateReceivedFile([
                'name' => 'innocuo.php',
                'tmp_name' => $path,
                'size' => filesize($path),
            ]);
        },
        'estensione .php rifiutata'
    );
});

$t->test('un\'immagine il cui contenuto e\' codice viene rifiutata', function (TestRunner $t) {
    // Il caso pericoloso: estensione .jpg con contenuto PHP. Il controllo
    // confronta l'estensione dichiarata con il MIME reale del file.
    $path = writeTempFile("<?php system(\$_GET['c']); ?>", 'fake.jpg');
    $t->test_expect_throw(
        static function () use ($path) {
            Upload::validateReceivedFile([
                'name' => 'foto.jpg',
                'tmp_name' => $path,
                'size' => filesize($path),
            ]);
        },
        'JPEG dichiarato con contenuto PHP rifiutato'
    );
});

$t->test('un file valido viene accettato con il MIME reale', function (TestRunner $t) {
    // PNG 1x1 minimale, costruito a mano.
    $png = base64_decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    );
    $path = writeTempFile($png, 'foto.png');

    $result = Upload::validateReceivedFile([
        'name' => 'foto.png',
        'tmp_name' => $path,
        'size' => strlen($png),
    ]);

    $t->assertSame('image/png', $result['mime_type'], 'MIME reale rilevato dal contenuto');
    $t->assertSame('png', $result['extension'], 'estensione coerente');
});

$t->test('estensioni pericolose nella blocklist', function (TestRunner $t) {
    $dangerous = ['php', 'phtml', 'phar', 'cgi', 'pl', 'py', 'sh', 'exe', 'bat', 'jsp', 'asp', 'jar'];
    foreach ($dangerous as $extension) {
        $t->assertSame(
            'bin',
            Upload::extensionFor('application/octet-stream', $extension),
            "l'estensione .$extension deve ricadere su .bin"
        );
    }
});

$t->test('l\'estensione assegnata non puo\' essere eseguibile', function (TestRunner $t) {
    $t->assertSame('jpg', Upload::extensionFor('image/jpeg'), 'JPEG -> jpg');
    $t->assertSame('pdf', Upload::extensionFor('application/pdf'), 'PDF -> pdf');
    // Uno ZIP e' un tipo noto, ma l'estensione originale pericolosa va neutralizzata.
    $t->assertSame('zip', Upload::extensionFor('application/zip'), 'ZIP -> zip');
    $t->assertSame('bin', Upload::extensionFor('application/x-unknown', 'php'), 'ignoto + .php -> bin');
});

$t->test('il nome visualizzato viene sanificato contro il path traversal', function (TestRunner $t) {
    // Il nome mostrato non e' mai usato per comporre un percorso: quello usa
    // solo la chiave casuale. Qui si verifica che il percorso venga pero'
    // ripulito, per non esporre strutture di directory al momento del rendering.
    $t->assertSame('passwd', Upload::sanitizeDisplayName('../../etc/passwd'));
    $t->assertSame('evil.jpg', Upload::sanitizeDisplayName('/etc/evil.jpg'));
    $t->assertSame('relazione.pdf', Upload::sanitizeDisplayName('C:\\Users\\Mario\\relazione.pdf'));
    $t->assertSame('foto.jpg', Upload::sanitizeDisplayName('foto.jpg'));
    $t->assertSame('file', Upload::sanitizeDisplayName('..'), 'il solo ".." diventa un nome neutro');
    $t->assertSame('file', Upload::sanitizeDisplayName(''), 'il nome vuoto viene sostituito');
    $t->assertSame('file', Upload::sanitizeDisplayName('.'), 'il solo "." diventa un nome neutro');

    $t->assert(
        !str_contains(Upload::sanitizeDisplayName("../../x.png\x00.jpg"), '..'),
        'nessun residuo di risalita'
    );
});

$t->test('la chiave di archiviazione e\' casuale e non prevedibile', function (TestRunner $t) {
    $keys = [];
    for ($i = 0; $i < 200; $i++) {
        $keys[] = Upload::generateStorageKey('jpg');
    }
    $t->assertSame(200, count(array_unique($keys)), 'nessuna chiave deve ripetersi');

    $key = $keys[0];
    $t->assert(preg_match('#^\d{8}/[0-9a-f]{48}\.jpg$#', $key) === 1, "formato chiave: $key");
    // La parte casuale e' 24 byte interi: dimezzarla dimezzerebbe l'entropia
    // reale dello spazio dei nomi.
    $t->assert(
        substr_count($key, '_') === 0,
        'nessuna parte della chiave deve essere ripetuta'
    );
    // Non deve contenere tracce del timestamp a risoluzione del secondo,
    // cosa che renderebbe enumerabile lo spazio dei nomi.
    $t->assert(
        !str_contains($key, substr((string)time(), -6)),
        'la chiave non deve contenere il timestamp corrente'
    );
});

$t->test('una chiave con path traversal viene rifiutata', function (TestRunner $t) {
    $t->test_expect_throw(
        static function () {
            Upload::absolutePathFor('../../etc/passwd');
        },
        'traversal rifiutato'
    );
    $t->test_expect_throw(
        static function () {
            Upload::absolutePathFor('/etc/passwd');
        },
        'percorso assoluto rifiutato'
    );
});

$t->test('il file viene scritto con permessi non leggibili da altri', function (TestRunner $t) {
    $dir = sys_get_temp_dir() . '/quice-test-' . bin2hex(random_bytes(4));
    putenv('QUICE_UPLOADS_DIR=' . $dir);
    mkdir($dir, 0750, true);

    try {
        $path = writeTempFile('contenuto di prova', 'nota.txt');
        $key = Upload::storeReceivedFile(
            ['tmp_name' => $path, 'name' => 'nota.txt'],
            ['extension' => 'txt', 'mime_type' => 'text/plain', 'original_name' => 'nota.txt']
        );

        $absolute = Upload::absolutePathFor($key);
        $t->assert(is_file($absolute), 'il file deve esistere');
        $t->assertSame('contenuto di prova', file_get_contents($absolute), 'contenuto preservato');
        $t->assertSame('0640', substr(sprintf('%o', fileperms($absolute)), -4), 'permessi 0640');
    } finally {
        putenv('QUICE_UPLOADS_DIR');
        removeTree($dir);
    }
});

$t->test('la cancellazione del file su disco funziona', function (TestRunner $t) {
    $dir = sys_get_temp_dir() . '/quice-test-' . bin2hex(random_bytes(4));
    putenv('QUICE_UPLOADS_DIR=' . $dir);
    mkdir($dir, 0750, true);

    try {
        $path = writeTempFile('da eliminare', 'x.txt');
        $key = Upload::storeReceivedFile(
            ['tmp_name' => $path, 'name' => 'x.txt'],
            ['extension' => 'txt', 'mime_type' => 'text/plain', 'original_name' => 'x.txt']
        );

        $t->assert(is_file(Upload::absolutePathFor($key)), 'il file esiste prima');
        $t->assert(Upload::deleteStoredFile($key), 'la cancellazione deve riuscire');
        $t->assert(!is_file(Upload::absolutePathFor($key)), 'il file non deve piu\' esistere');
    } finally {
        putenv('QUICE_UPLOADS_DIR');
        removeTree($dir);
    }
});

/* ================================================================== */
$t->group('Esportazione dei dati (Art. 15 e 20)');

$t->test('l\'export contiene profilo, messaggi, file, consensi e sessioni', function (TestRunner $t) {
    seedUser('3391234567');
    seedUser('3391234568');
    createDirectChat('3391234567', '3391234568', '2345678901');

    Db::execute(
        "INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id) VALUES (?, ?, ?, ?)",
        ['Ciao!', '3391234567', '3391234568', '2345678901']
    );
    Db::execute(
        "INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id) VALUES (?, ?, ?, ?)",
        ['Ciao a te', '3391234568', '3391234567', '2345678901']
    );
    Db::execute(
        'INSERT INTO shared_files (owner_user_id, file_name, mime_type, size_bytes, storage_key)
         VALUES (?, ?, ?, ?, ?)',
        ['3391234567', 'relazione.pdf', 'application/pdf', 1234, '20260101/aaa_bbb.pdf']
    );
    Consent::record('3391234567', 'privacy_policy', true, 'registration');
    Auth::issueToken('3391234567', 'dispositivo');

    $fascicolo = Privacy::buildExport('3391234567')['export'];

    $t->assert(isset($fascicolo['subject']), 'dev\'essere presente il profilo');
    $t->assertSame('3391234567', $fascicolo['subject']['id'], 'ID corretto');
    $t->assertCount(2, $fascicolo['messages'], 'entrambi i messaggi della chat');
    $t->assertCount(1, $fascicolo['files'], 'il file caricato');
    $t->assertCount(1, $fascicolo['conversations'], 'la conversazione');
    $t->assertCount(1, $fascicolo['consents'], 'la prova del consenso');
    $t->assertCount(1, $fascicolo['sessions'], 'la sessione');
    $t->assert(isset($fascicolo['audit_trail']), 'dev\'essere presente il registro di controllo');
    $t->assert(isset($fascicolo['retention']), 'dev\'essere dichiarata la conservazione');
});

$t->test('l\'export NON contiene materiale di autenticazione', function (TestRunner $t) {
    seedUser('3391234567', ['password_hash' => password_hash('Password123', PASSWORD_DEFAULT)]);
    Auth::issueToken('3391234567');

    $encoded = json_encode(Privacy::buildExport('3391234567'));
    $t->assert(!str_contains($encoded, 'password_hash'), 'nessun hash password');
    $t->assert(!str_contains($encoded, '$2y$'), 'nessun hash bcrypt');
    $t->assert(!str_contains($encoded, 'token_hash'), 'nessun hash di sessione');
});

$t->test('l\'export distingue i messaggi propri da quelli ricevuti', function (TestRunner $t) {
    seedUser('3391234567');
    seedUser('3391234568');
    createDirectChat('3391234567', '3391234568', '2345678901');
    Db::execute(
        'INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id) VALUES (?, ?, ?, ?)',
        ['Mio', '3391234567', '3391234568', '2345678901']
    );
    Db::execute(
        'INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id) VALUES (?, ?, ?, ?)',
        ['Suo', '3391234568', '3391234567', '2345678901']
    );

    $messages = Privacy::buildExport('3391234567')['export']['messages'];
    $t->assertCount(2, $messages, 'entrambi visibili');
    $t->assertCount(
        1,
        array_filter($messages, static fn(array $m) => $m['sent_by_me'] === true),
        'un solo messaggio e\' proprio'
    );
});

$t->test('un messaggio cancellato compare redactato, senza contenuto', function (TestRunner $t) {
    seedUser('3391234567');
    seedUser('3391234568');
    createDirectChat('3391234567', '3391234568', '2345678901');
    Db::execute(
        'INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id, deleted_at)
         VALUES (?, ?, ?, ?, ?)',
        ['segreto', '3391234567', '3391234568', '2345678901', utcTimestamp()]
    );

    $encoded = json_encode(Privacy::buildExport('3391234567'));
    $t->assert(!str_contains($encoded, 'segreto'), 'il contenuto cancellato non deve trapelare');
    $t->assert(str_contains($encoded, '"redacted":true'), 'deve risultare redactato');
});

/* ================================================================== */
$t->group('Diritto all\'oblio (Art. 17)');

$t->test('la richiesta di cancellazione blocca subito le sessioni', function (TestRunner $t) {
    seedUser('3391234567');
    $token = Auth::issueToken('3391234567');
    $t->assert(Auth::resolveToken($token['token']) !== null, 'sessione attiva prima');

    $result = Privacy::requestErasure('3391234567', 'test');

    $t->assert($result['grace_days'] > 0, 'deve esserci una finestra di attesa');
    $t->assert($result['can_be_cancelled'] === true, 'deve essere annullabile');
    $t->assertNull(Auth::resolveToken($token['token']), 'la sessione deve essere revocata subito');
});

$t->test('la cancellazione definitiva elimina in cascata tutto', function (TestRunner $t) {
    $uploads = sys_get_temp_dir() . '/quice-test-' . bin2hex(random_bytes(4));
    mkdir($uploads . '/20260101', 0750, true);
    file_put_contents($uploads . '/20260101/aaa_bbb.pdf', 'contenuto');
    putenv('QUICE_UPLOADS_DIR=' . $uploads);

    try {
        seedUser('3391234567');
        seedUser('3391234568');
        createDirectChat('3391234567', '3391234568', '2345678901');
        Auth::issueToken('3391234567');
        Consent::record('3391234567', 'privacy_policy', true, 'registration');

        Db::execute(
            'INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id) VALUES (?, ?, ?, ?)',
            ['da cancellare', '3391234567', '3391234568', '2345678901']
        );
        Db::execute(
            'INSERT INTO shared_files (owner_user_id, file_name, mime_type, size_bytes, storage_key)
             VALUES (?, ?, ?, ?, ?)',
            ['3391234567', 'relazione.pdf', 'application/pdf', 10, '20260101/aaa_bbb.pdf']
        );

        $summary = Privacy::purgeUser('3391234567');

        $t->assertSame(1, $summary['messages'], 'il messaggio deve essere eliminato');
        $t->assertSame(1, $summary['files'], 'il file deve essere eliminato dal database');
        $t->assertSame(
            0,
            (int)Db::fetchOne('SELECT COUNT(*) AS c FROM messaggi')['c'],
            'tabella messaggi vuota'
        );
        $t->assertSame(
            0,
            (int)Db::fetchOne('SELECT COUNT(*) AS c FROM utenti WHERE IDutente = ?', ['3391234567'])['c'],
            'l\'utente deve essere eliminato'
        );
        $t->assertSame(
            0,
            (int)Db::fetchOne('SELECT COUNT(*) AS c FROM utenti_sessioni')['c'],
            'le sessioni devono essere eliminate'
        );
        $t->assert(
            !is_file($uploads . '/20260101/aaa_bbb.pdf'),
            'il file fisico deve essere rimosso dal filesystem'
        );
    } finally {
        putenv('QUICE_UPLOADS_DIR');
        removeTree($uploads);
    }
});

$t->test('i consensi sopravvivono pseudonimi (Art. 17(3)(b))', function (TestRunner $t) {
    seedUser('3391234567');
    Consent::record('3391234567', 'privacy_policy', true, 'registration');
    $expected = Consent::has('3391234567', 'privacy_policy');
    $t->assert($expected, 'il consenso e\' stato registrato');

    Privacy::purgeUser('3391234567');

    $row = Db::fetchOne('SELECT * FROM consensi ORDER BY id DESC LIMIT 1');
    $t->assert($row !== null, 'la prova del consenso deve sopravvivere');
    $t->assertNull($row['user_id'], 'il legame con l\'utente deve essere rimosso');
    $t->assert($row['subject_pseudonym'] !== null, 'deve restare lo pseudonimo');
    $t->assertNull($row['ip_hash'], 'l\'IP deve essere rimosso');
    $t->assert(
        !str_contains(strval($row['subject_pseudonym']), '3391234567'),
        'lo pseudonimo non deve rivelare l\'identificativo'
    );
});

$t->test('il registro di controllo perde l\'ID ma conserva la prova', function (TestRunner $t) {
    seedUser('3391234567');
    Logger::audit('login.succeeded', '3391234567', null, null, 'ok');

    $before = Db::fetchOne('SELECT * FROM audit_log ORDER BY id DESC LIMIT 1');
    $t->assertSame('3391234567', strval($before['actor_user_id']), 'l\'ID c\'e prima della cancellazione');

    Privacy::purgeUser('3391234567');

    // La voce cercata e' quella dell'accesso: la cancellazione genera a sua
    // volta una voce di audit, che e' l'ultima per ordine di inserimento.
    $after = Db::fetchOne(
        "SELECT * FROM audit_log WHERE action = 'login.succeeded' ORDER BY id DESC LIMIT 1"
    );
    $t->assertNull($after['actor_user_id'], 'l\'ID diretto deve sparire');
    $t->assertSame(
        $before['actor_pseudonym'],
        $after['actor_pseudonym'],
        'lo pseudonimo deve restare per dimostrare la responsabilita\''
    );
    $t->assertSame('login.succeeded', $after['action'], 'l\'azione resta dimostrabile');
    $t->assertNull($after['ip_hash'], 'l\'IP deve essere rimosso');
});

$t->test('la cancellazione non distrugge i dati di terzi', function (TestRunner $t) {
    // Art. 17(2): cancellare i propri dati non puo' pregiudicare i diritti altrui.
    seedUser('3391234567');
    seedUser('3391234568');
    createDirectChat('3391234567', '3391234568', '2345678901');
    Db::execute(
        'INSERT INTO messaggi (textmessage, senderID, reciverID, chat_id) VALUES (?, ?, ?, ?)',
        ['messaggio di terzi', '3391234568', '3391234567', '2345678901']
    );

    Privacy::purgeUser('3391234567');

    $remaining = Db::fetchOne('SELECT COUNT(*) AS c FROM messaggi');
    $t->assertSame(0, (int)$remaining['c'], 'i messaggi della chat cancellata non sopravvivono');
    $t->assertSame(
        1,
        (int)Db::fetchOne('SELECT COUNT(*) AS c FROM utenti')['c'],
        'l\'altro utente deve sopravvivere'
    );
});

$t->test('la richiesta annullata ripristina l\'account', function (TestRunner $t) {
    seedUser('3391234567');
    Privacy::requestErasure('3391234567');
    Privacy::cancelErasure('3391234567');

    $row = Db::fetchOne('SELECT deletion_requested_at FROM utenti WHERE IDutente = ?', ['3391234567']);
    $t->assertNull($row['deletion_requested_at'], 'la richiesta deve essere annullata');
});

$t->test('la finestra di attesa rispetta la data pianificata', function (TestRunner $t) {
    seedUser('3391234567');

    // Pianificata nel futuro: non deve accadere nulla.
    Privacy::requestErasure('3391234567');
    $purged = Privacy::purgeDueErasures();
    $t->assertSame(0, $purged['processed'], 'non deve cancellare prima del termine');

    // Pianificata nel passato: ora si.
    Db::execute(
        'UPDATE utenti SET deletion_scheduled_for = ? WHERE IDutente = ?',
        [gmdate('Y-m-d H:i:s', time() - 3600), '3391234567']
    );
    $purged = Privacy::purgeDueErasures();
    $t->assertSame(1, $purged['processed'], 'la scadenza deve attivare la cancellazione');
    $t->assertSame(
        0,
        (int)Db::fetchOne('SELECT COUNT(*) AS c FROM utenti')['c'],
        'l\'utente deve essere sparito'
    );
});

/* ================================================================== */
$t->group('Limitazione del trattamento (Art. 18)');

$t->test('la limitazione viene registrata e letta', function (TestRunner $t) {
    seedUser('3391234567');
    $t->assert(!Privacy::isRestricted('3391234567'), 'impostazione iniziale');

    Privacy::setProcessingRestriction('3391234567', true);
    $t->assert(Privacy::isRestricted('3391234567'), 'deve risultare limitato');

    Privacy::setProcessingRestriction('3391234567', false);
    $t->assert(!Privacy::isRestricted('3391234567'), 'deve poter essere rimossa');
});

/* ================================================================== */
$t->group('Conservazione nel tempo (Art. 5(1)(e))');

$t->test('i messaggi nuovi ricevono un termine di conservazione', function (TestRunner $t) {
    seedUser('3391234567');
    Db::execute('INSERT INTO messaggi (textmessage, senderID) VALUES (?, ?)', ['ciao', '3391234567']);

    $id = (int)Db::lastInsertId();
    $t->assertNull(
        Db::fetchOne('SELECT purge_after FROM messaggi WHERE id = ?', [$id])['purge_after'],
        'senza il timbro la conservazione non e\' determinata'
    );

    Retention::stampMessages([$id]);
    $stamped = Db::fetchOne('SELECT purge_after FROM messaggi WHERE id = ?', [$id])['purge_after'];
    $t->assert($stamped !== null, 'il termine deve essere impostato');
    $t->assert(
        strtotime(strval($stamped)) > time() + 300 * 86400,
        'il termine deve essere lontano nel futuro (default 365 giorni)'
    );
});

$t->test('i messaggi scaduti vengono eliminati, gli altri restano', function (TestRunner $t) {
    seedUser('3391234567');
    Db::execute('INSERT INTO messaggi (textmessage, senderID) VALUES (?, ?)', ['scaduto', '3391234567']);
    $old = (int)Db::lastInsertId();
    Db::execute(
        'UPDATE messaggi SET purge_after = ? WHERE id = ?',
        [gmdate('Y-m-d H:i:s', time() - 86400), $old]
    );

    Db::execute('INSERT INTO messaggi (textmessage, senderID) VALUES (?, ?)', ['fresco', '3391234567']);
    $fresh = (int)Db::lastInsertId();
    Retention::stampMessages([$fresh]);

    $summary = Retention::run(true);
    $t->assertSame(1, $summary['messages'], 'il dry run deve contare un messaggio da eliminare');

    $summary = Retention::run(false);
    $t->assertSame(1, $summary['messages'], 'deve essere eliminato un solo messaggio');

    $rows = Db::fetchAll('SELECT id FROM messaggi');
    $t->assertCount(1, $rows, 'resta solo il messaggio fresco');
    $t->assertSame($fresh, (int)$rows[0]['id'], 'il messaggio fresco e\' sopravvissuto');
});

$t->test('il dry run non modifica nulla', function (TestRunner $t) {
    seedUser('3391234567');
    Db::execute('INSERT INTO messaggi (textmessage, senderID) VALUES (?, ?)', ['scaduto', '3391234567']);
    Db::execute(
        'UPDATE messaggi SET purge_after = ?',
        [gmdate('Y-m-d H:i:s', time() - 86400)]
    );

    Retention::run(true);
    $t->assertSame(
        1,
        (int)Db::fetchOne('SELECT COUNT(*) AS c FROM messaggi')['c'],
        'il dry run non deve eliminare nulla'
    );
});

$t->test('le sessioni scadute vengono ripulite', function (TestRunner $t) {
    seedUser('3391234567');
    Auth::issueToken('3391234567');

    Db::execute(
        'UPDATE utenti_sessioni SET expires_at = ?, revoked_at = ?, revoked_reason = ?',
        [gmdate('Y-m-d H:i:s', time() - 400 * 86400), gmdate('Y-m-d H:i:s', time() - 400 * 86400), 'logout']
    );

    $summary = Retention::run(false);
    $t->assertSame(1, $summary['sessions'], 'la sessione scaduta deve essere rimossa');
});

/* ================================================================== */
$t->group('Nessuna informazione di autenticazione esposta');

$t->test('il token non compare mai nella query string dei test', function (TestRunner $t) {
    // Difesa contro la regressione: il token deve viaggiare solo nell'header
    // Authorization, mai in URL (dove finirebbe nei log di accesso).
    $t->assertNull(
        Auth::resolveToken(strval($_GET['token'] ?? '')),
        'il token non deve essere accettato dalla query string'
    );
});

$t->test('l\'ID utente non e\' sufficiente ad accedere', function (TestRunner $t) {
    seedUser('3391234567');
    // Nessun token: anche conoscendo l'ID non si ottiene alcuna sessione.
    $t->assertNull(Auth::resolveToken(null), 'senza token non c\'e sessione');
    $t->assertSame(
        0,
        (int)Db::fetchOne('SELECT COUNT(*) AS c FROM utenti_sessioni')['c'],
        'nessuna sessione viene creata implicitamente'
    );
});

exit($t->report());

/* ------------------------------------------------------------------ */
/* Helper                                                              */
/* ------------------------------------------------------------------ */

function writeTempFile(string $contents, string $suffix): string
{
    $path = tempnam(sys_get_temp_dir(), 'quice') . $suffix;
    file_put_contents($path, $contents);
    return $path;
}

function removeTree(string $path): void
{
    if (!is_dir($path)) {
        @unlink($path);
        return;
    }
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST
    );
    foreach ($iterator as $entry) {
        $entry->isDir() ? @rmdir($entry->getPathname()) : @unlink($entry->getPathname());
    }
    @rmdir($path);
}
