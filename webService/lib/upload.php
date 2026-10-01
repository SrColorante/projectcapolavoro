<?php
/**
 * upload.php — Validazione e gestione dei file caricati.
 *
 * Il buco che questo file chiude: prima il MIME type arrivava dal client
 * (`$_FILES['file']['type']`, che e' dichiarato dall'utente e quindi falso
 * con facilità) e il nome veniva sanitizzato ma non controllato. Con un
 * estensione `.php` il file diventava eseguibile dal web server. Il `.htaccess`
 * aggiunto in precedenza e' una rete di sicurezza, non una correzione: qui ora
 * il tipo viene verificato sul contenuto reale del file e l'estensione viene
 * decisa dal server.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/logging.php';
require_once __DIR__ . '/http.php';

final class Upload
{
    /** Estensioni mai accettate, indipendentemente dal contenuto. */
    private const BLOCKED_EXTENSIONS = [
        'php', 'php3', 'php4', 'php5', 'php7', 'php8', 'phps', 'phtml', 'phar',
        'pht', 'shtml', 'cgi', 'pl', 'py', 'rb', 'sh', 'bash', 'zsh', 'exe',
        'com', 'bat', 'cmd', 'msi', 'dll', 'so', 'dylib', 'jsp', 'jspx', 'asp',
        'aspx', 'ashx', 'asmx', 'cer', 'htaccess', 'ini', 'jar', 'apk', 'app',
    ];

    /**
     * Estensioni che il server assegna in base al MIME reale. Tutto cio' che
     * non e' in questa mappa viene salvato con estensione `.bin`, cosi' il web
     * server non lo puo' interpretare come script.
     */
    private const EXTENSION_BY_MIME = [
        'image/jpeg'      => 'jpg',
        'image/png'       => 'png',
        'image/gif'       => 'gif',
        'image/webp'      => 'webp',
        'image/bmp'       => 'bmp',
        'image/heic'      => 'heic',
        'image/svg+xml'   => 'svg',
        'image/tiff'      => 'tiff',
        'audio/mpeg'      => 'mp3',
        'audio/mp4'       => 'm4a',
        'audio/x-m4a'     => 'm4a',
        'audio/aac'       => 'aac',
        'audio/ogg'       => 'ogg',
        'audio/opus'      => 'opus',
        'audio/wav'       => 'wav',
        'audio/x-wav'     => 'wav',
        'audio/webm'      => 'weba',
        'video/mp4'       => 'mp4',
        'video/webm'      => 'webm',
        'video/quicktime' => 'mov',
        'video/x-msvideo' => 'avi',
        'application/pdf' => 'pdf',
        'text/plain'      => 'txt',
        'text/csv'        => 'csv',
        'application/zip' => 'zip',
        'application/x-7z-compressed' => '7z',
        // Testo/codice: salvato come .txt perche' il contenuto e' inerte e
        // l'anteprima nel client e' "code".
        'text/x-c'        => 'txt',
        'text/x-c++'      => 'txt',
        'text/x-java'     => 'txt',
        'text/x-python'   => 'txt',
    ];

    /** MIME che non devono mai essere archiviati, perche' attivi o interpretabili. */
    private const BLOCKED_MIMES = [
        'text/html',
        'application/xhtml+xml',
        'application/x-httpd-php',
        'application/x-msdownload',
        'application/vnd.microsoft.portable-executable',
        'application/x-executable',
        'application/x-sharedlib',
        'application/javascript',
        'text/javascript',
        'application/x-msdos-program',
    ];

    /**
     * Determina il MIME reale dal contenuto del file, non dai metadati del
     * client.
     */
    public static function detectMime(string $path): string
    {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        if ($finfo === false) {
            return 'application/octet-stream';
        }
        $mime = finfo_file($finfo, $path);
        finfo_close($finfo);
        return is_string($mime) && $mime !== '' ? strtolower($mime) : 'application/octet-stream';
    }

    /**
     * Valida il file appena ricevuto. Restituisce il MIME reale, oppure lancia
     * RuntimeException con un messaggio adatto all'utente.
     */
    public static function validateReceivedFile(array $uploaded): array
    {
        $originalName = strval($uploaded['name'] ?? '');
        $tmpPath = strval($uploaded['tmp_name'] ?? '');

        if ($tmpPath === '' || !is_file($tmpPath)) {
            throw new RuntimeException('File non valido.');
        }

        $size = intval($uploaded['size'] ?? 0);
        $max = Config::maxUploadBytes();
        if ($size <= 0) {
            throw new RuntimeException('File vuoto.');
        }
        if ($size > $max) {
            throw new RuntimeException('Il file supera il limite consentito di ' . self::humanSize($max) . '.');
        }

        $originalExt = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
        if (in_array($originalExt, self::BLOCKED_EXTENSIONS, true)) {
            throw new RuntimeException(
                'Questo tipo di file non e\' ammesso. Rinominare il file non e\' sufficiente: '
                . 'il contenuto viene verificato.'
            );
        }

        $realMime = self::detectMime($tmpPath);
        if (in_array($realMime, self::BLOCKED_MIMES, true)) {
            throw new RuntimeException('Contenuto non ammesso per motivi di sicurezza.');
        }

        // Coerenza tra l'estensione dichiarata e il contenuto reale: un .jpg
        // che in realta' e' uno script e' il caso piu' pericoloso in assoluto.
        self::assertExtensionMatchesContent($originalExt, $realMime);

        return [
            'mime_type' => $realMime,
            'size_bytes' => $size,
            'original_name' => self::sanitizeDisplayName($originalName),
            'extension' => self::extensionFor($realMime, $originalExt),
        ];
    }

    /**
     * Un'immagine dichiarata che in realta' contiene codice viene rifiutata.
     * Non e' un controllo esaustivo anti-malware, ma chiude il caso triviale
     * che stava alla base della vulnerabilita'.
     */
    private static function assertExtensionMatchesContent(string $extension, string $mime): void
    {
        $imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'tiff', 'svg'];
        $looksLikeImage = in_array($extension, $imageExtensions, true)
            || str_starts_with($mime, 'image/');

        if ($looksLikeImage && !str_starts_with($mime, 'image/')) {
            throw new RuntimeException(
                'Il contenuto del file non corrisponde alla sua estensione: rifiutato.'
            );
        }
    }

    /** Estensione assegnata dal server in base al MIME reale. */
    public static function extensionFor(string $realMime, string $originalExt = ''): string
    {
        if (isset(self::EXTENSION_BY_MIME[$realMime])) {
            $candidate = self::EXTENSION_BY_MIME[$realMime];
            if (!in_array($candidate, self::BLOCKED_EXTENSIONS, true)) {
                return $candidate;
            }
        }
        // Estensione originale solo se innocua, altrimenti .bin.
        $normalized = strtolower(preg_replace('/[^a-z0-9]/', '', $originalExt) ?? '');
        if ($normalized !== '' && strlen($normalized) <= 8
            && !in_array($normalized, self::BLOCKED_EXTENSIONS, true)) {
            return $normalized;
        }
        return 'bin';
    }

    /**
     * Nome mostrato all'utente. Non viene mai usato per comporre il percorso
     * su disco: quello usa esclusivamente la chiave casuale.
     */
    public static function sanitizeDisplayName(string $name): string
    {
        $base = basename(str_replace('\\', '/', $name));
        $base = preg_replace('/[\x00-\x1F\x7F]/u', '', $base) ?? '';
        $base = str_replace(['/', '\\', "\0"], '', $base);
        $base = trim($base);
        if ($base === '' || $base === '.' || $base === '..') {
            $base = 'file';
        }
        if (mb_strlen($base) > 180) {
            $base = mb_substr($base, 0, 180);
        }
        return $base;
    }

    /**
     * Chiave opzionale per lo storage. Usa casualita' crittografica: il
     * precedente `uniqid()` e' prevedibile e non va bene per nomi di file
     * esposti via web.
     *
     * Formato: `YYYYMMDD/<48 caratteri hex>.<estensione>`. La cartella data e'
     * comoda per la manutenzione, ma non parte della segretezza: l'unicita' e
     * l'imprevedibilita' stanno nei 24 byte casuali.
     */
    public static function generateStorageKey(string $extension): string
    {
        $random = bin2hex(random_bytes(24));
        $ext = preg_replace('/[^a-z0-9]/', '', strtolower($extension)) ?? 'bin';
        if ($ext === '' || in_array($ext, self::BLOCKED_EXTENSIONS, true)) {
            $ext = 'bin';
        }
        $prefix = gmdate('Ymd');
        return sprintf('%s/%s.%s', $prefix, $random, $ext);
    }

    public static function uploadsDir(): string
    {
        return rtrim(Config::uploadsDir(), '/');
    }

    /**
     * Risolve la chiave in un percorso assoluto, garantendo che resti dentro
     * la directory di archiviazione.
     *
     * Il controllo e' lessicale prima (per rifiutare `..` e i percorsi
     * assoluti) e poi verificato sul filesystem via realpath quando la
     * directory di destinazione esiste gia'. Serve perche' la chiamata avviene
     * anche durante la cancellazione di un file, quando la directory potrebbe
     * non esistere piu'.
     */
    public static function absolutePathFor(string $storageKey): string
    {
        $key = str_replace('\\', '/', trim($storageKey));
        if ($key === '' || str_starts_with($key, '/') || str_contains($key, '..')) {
            throw new RuntimeException('Chiave di archiviazione non valida.');
        }

        $base = self::uploadsDir();
        $resolved = $base . '/' . $key;

        $realBase = realpath($base);
        if ($realBase === false) {
            // La directory base non esiste ancora: il controllo lessicale basta.
            return $resolved;
        }

        // Si risolve l'antenato piu' vicino che esiste davvero.
        $probe = dirname($resolved);
        while ($probe !== '' && !is_dir($probe)) {
            $parent = dirname($probe);
            if ($parent === $probe) {
                break;
            }
            $probe = $parent;
        }
        $realProbe = realpath($probe);
        if ($realProbe === false
            || !str_starts_with($realProbe, $realBase)) {
            throw new RuntimeException('Chiave di archiviazione fuori dalla directory prevista.');
        }

        return $resolved;
    }

    public static function ensureDirectory(string $path): void
    {
        if (!is_dir($path) && !@mkdir($path, 0750, true) && !is_dir($path)) {
            throw new RuntimeException('Impossibile creare la directory di archiviazione.');
        }
    }

    public static function storeReceivedFile(array $uploaded, array $validated): string
    {
        $storageKey = self::generateStorageKey($validated['extension']);
        $target = self::absolutePathFor($storageKey);
        self::ensureDirectory(dirname($target));

        if (is_file($target)) {
            throw new RuntimeException('Collisione sulla chiave di archiviazione: riprova.');
        }

        $moved = is_uploaded_file(strval($uploaded['tmp_name']))
            ? move_uploaded_file(strval($uploaded['tmp_name']), $target)
            : rename(strval($uploaded['tmp_name']), $target);

        if (!$moved) {
            throw new RuntimeException('Impossibile salvare il file.');
        }

        // 0640: nessun altro utente del server puo' leggere i file caricati.
        @chmod($target, 0640);

        return $storageKey;
    }

    /** Elimina un file archiviato. Usato da cancellazione account e da purge. */
    public static function deleteStoredFile(?string $storageKey): bool
    {
        if ($storageKey === null || $storageKey === '') {
            return false;
        }
        try {
            $path = self::absolutePathFor($storageKey);
        } catch (\Throwable $e) {
            return false;
        }
        if (is_file($path)) {
            return @unlink($path);
        }
        return false;
    }

    /**
     * Elimina ricorsivamente le directory vuote lasciate dalla cancellazione
     * dei file.
     */
    public static function pruneEmptyDirectories(?string $root = null): int
    {
        $root = $root ?? self::uploadsDir();
        if (!is_dir($root)) {
            return 0;
        }
        $removed = 0;
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
            RecursiveIteratorIterator::CHILD_FIRST
        );
        foreach ($iterator as $entry) {
            if ($entry->isDir() && self::isEmptyDir($entry->getPathname())) {
                if (@rmdir($entry->getPathname())) {
                    $removed++;
                }
            }
        }
        return $removed;
    }

    private static function isEmptyDir(string $path): bool
    {
        $handle = @opendir($path);
        if ($handle === false) {
            return false;
        }
        while (($entry = readdir($handle)) !== false) {
            if ($entry !== '.' && $entry !== '..') {
                closedir($handle);
                return false;
            }
        }
        closedir($handle);
        return true;
    }

    public static function humanSize(int $bytes): string
    {
        $units = ['B', 'KB', 'MB', 'GB'];
        $value = (float)$bytes;
        $index = 0;
        while ($value >= 1024 && $index < count($units) - 1) {
            $value /= 1024;
            $index++;
        }
        return round($value, $value >= 10 || $index === 0 ? 0 : 1) . ' ' . $units[$index];
    }
}
