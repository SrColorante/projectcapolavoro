<?php
/**
 * consent.php — Registro dei consensi (GDPR Art. 7).
 *
 * Il trattamento in Quice si fonda su:
 *  - Art. 6(1)(b) esecuzione del contratto: identificativi, profilo, messaggi,
 *    file scambiati, chat, impostazioni;
 *  - Art. 6(1)(a) consenso: traduzione on-device, trasferimento peer-to-peer
 *    sulla LAN, bio vocale, diagnostica opzionale.
 *
 * Ogni decisione viene registrata con marca temporale, versione del testo
 * presentato all'utente e prova (IP pseudonimizzato). Il ritiro deve essere
 * tanto semplice quanto la concessione (Art. 7(3)): per questo l'API espone
 * `withdraw` accanto a `grant` con lo stesso carico utile.
 *
 * La prova del consenso va conservata: `retentionDays('consensi')` e' volutamente
 * lunga (5 anni di default) anche se gli altri dati vengono cancellati prima.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/http.php';
require_once __DIR__ . '/logging.php';

final class Consent
{
    /**
     * Tipi di consenso riconosciuti. Ogni voce dichiara:
     *  - `required`  : necessario al servizio, non puo' essere ritirato senza
     *                  compromettere il servizio stesso
     *  - `basis`     : base giuridica dichiarata all'utente
     */
    public const CATALOG = [
        'privacy_policy' => [
            'required' => true,
            'basis' => 'Art. 6(1)(b) - esecuzione del contratto',
            'title' => 'Informativa privacy e trattamento dei messaggi',
        ],
        'data_processing' => [
            'required' => true,
            'basis' => 'Art. 6(1)(b) - esecuzione del contratto',
            'title' => 'Trattamento dei dati per erogare il servizio di messaggistica',
        ],
        'translation_ondevice' => [
            'required' => false,
            'basis' => 'Art. 6(1)(a) - consenso',
            'title' => 'Traduzione on-device dei messaggi',
        ],
        'lan_peer_transfer' => [
            'required' => false,
            'basis' => 'Art. 6(1)(a) - consenso',
            'title' => 'Condivisione diretta con i dispositivi vicini sulla rete locale',
        ],
        'voice_bio' => [
            'required' => false,
            'basis' => 'Art. 6(1)(a) - consenso',
            'title' => 'Bio vocale (dati vocali, fino a 5 secondi)',
        ],
        'diagnostics' => [
            'required' => false,
            'basis' => 'Art. 6(1)(a) - consenso',
            'title' => 'Diagnostica anonima delle prestazioni',
        ],
    ];

    public static function isKnownType(string $type): bool
    {
        return array_key_exists($type, self::CATALOG);
    }

    public static function policyVersion(): string
    {
        $version = @file_get_contents(dirname(__DIR__) . '/PRIVACY_POLICY_VERSION');
        $version = $version === false ? '' : trim($version);
        return $version === '' ? '1.0.0' : $version;
    }

    /**
     * Registra una decisione. Il tipo viene validato contro il catalogo per
     * evitare che un client invochi endpoint con identificativi arbitrari.
     */
    public static function record(
        string $userId,
        string $type,
        bool $granted,
        ?string $source = null,
        ?string $policyVersion = null
    ): void {
        if (!self::isKnownType($type)) {
            throw new InvalidArgumentException("Tipo di consenso sconosciuto: $type");
        }

        Db::execute(
            'INSERT INTO consensi
                (user_id, tipo, granted, policy_version, source, recorded_at, ip_hash, withdrawn_at)
             VALUES (?, ?, ?, ?, ?, UTC_TIMESTAMP(), ?, ?)',
            [
                $userId,
                $type,
                $granted ? 1 : 0,
                $policyVersion ?? self::policyVersion(),
                $source ?? 'unknown',
                Logger::hashIp(Logger::clientIp()),
                $granted ? null : gmdate('Y-m-d H:i:s'),
            ]
        );

        Logger::audit(
            $granted ? 'consent.granted' : 'consent.withdrawn',
            $userId,
            'consent',
            $type,
            'ok',
            ['policy_version' => $policyVersion ?? self::policyVersion(), 'source' => $source]
        );
    }

    /**
     * Stato corrente per utente: per ogni tipo noto, l'ultima decisione.
     */
    public static function statusFor(string $userId): array
    {
        $rows = Db::fetchAll(
            'SELECT tipo, granted, policy_version, recorded_at, withdrawn_at
             FROM consensi
             WHERE user_id = ?
             ORDER BY id ASC',
            [$userId]
        );

        $latest = [];
        foreach ($rows as $row) {
            $latest[strval($row['tipo'])] = $row;
        }

        $status = [];
        foreach (self::CATALOG as $type => $meta) {
            $entry = $latest[$type] ?? null;
            $granted = $entry !== null && (int)$entry['granted'] === 1;
            $status[$type] = [
                'granted' => $granted,
                'required' => $meta['required'],
                'basis' => $meta['basis'],
                'title' => $meta['title'],
                'policy_version' => $entry['policy_version'] ?? null,
                'decided_at' => $entry['recorded_at'] ?? null,
            ];
        }

        return $status;
    }

    /**
     * Storico completo, per la prova del consenso. Esposto nell'export.
     */
    public static function historyFor(string $userId): array
    {
        $rows = Db::fetchAll(
            'SELECT tipo, granted, policy_version, source, recorded_at, withdrawn_at
             FROM consensi
             WHERE user_id = ?
             ORDER BY recorded_at ASC, id ASC',
            [$userId]
        );

        return array_map(static function (array $row): array {
            return [
                'type' => $row['tipo'],
                'granted' => (int)$row['granted'] === 1,
                'policy_version' => $row['policy_version'],
                'source' => $row['source'],
                'recorded_at' => $row['recorded_at'],
                'withdrawn_at' => $row['withdrawn_at'],
            ];
        }, $rows);
    }

    /** Consenso attualmente concesso, se presente. */
    public static function has(string $userId, string $type): bool
    {
        $status = self::statusFor($userId);
        return isset($status[$type]) && $status[$type]['granted'] === true;
    }

    /**
     * Ritira un consenso. Rifiuta i consensi necessari, che non possono essere
     * ritirati senza disattivare il servizio: in quel caso va usata la
     * cancellazione dell'account.
     */
    public static function withdraw(string $userId, string $type, ?string $source = null): ?string
    {
        if (!self::isKnownType($type)) {
            return "Tipo di consenso sconosciuto: $type";
        }
        $meta = self::CATALOG[$type];
        if ($meta['required'] === true) {
            return 'Questo trattamento e\' necessario al servizio: per ritirare il consenso '
                . 'devi eliminare il tuo account.';
        }

        self::record($userId, $type, false, $source ?? 'settings');
        return null;
    }

    /**
     * Il peer-to-peer sulla LAN condivide contenuti con altri dispositivi senza
     * passare dal server: senza consenso non deve partire.
     */
    public static function assertPeerTransferAllowed(string $userId): void
    {
        if (self::has($userId, 'lan_peer_transfer')) {
            return;
        }
        Http::error(
            'La condivisione diretta sulla rete locale richiede il consenso esplicito. '
            . 'Attivalo nelle impostazioni sulla privacy.',
            403
        );
    }
}
