<?php
/**
 * retention.php — Conservazione limitata nel tempo (Art. 5(1)(e)).
 *
 * "I dati personali devono essere conservati solo per il tempo necessario a
 *  raggiungere le finalita' per cui sono stati raccolti o trattati."
 *
 * Senza un meccanismo di questo tipo il database cresce indefinitamente e i
 * messaggi di utenti che non aprono piu' l'app restano per sempre, in contrasto
 * con il principio di minimizzazione. Ogni tabella ha un termine di conservazione
 * configurabile via ambiente (vedi Config::retentionDays).
 *
 * Da eseguire periodicamente: `php webService/migrate.php retention`
 * oppure via cron giornaliero.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/logging.php';
require_once __DIR__ . '/upload.php';
require_once __DIR__ . '/privacy.php';

final class Retention
{
    /**
     * Esegue un giro completo di conservazione. Restituisce un riepilogo.
     */
    public static function run(bool $dryRun = false): array
    {
        $summary = [
            'dry_run' => $dryRun,
            'messages' => 0,
            'files' => 0,
            'sessions' => 0,
            'audit_log' => 0,
            'consensi' => 0,
            'typing_status' => 0,
            'rate_limit_events' => 0,
            'erasure_requests' => 0,
            'orphan_directories_removed' => 0,
        ];

        // 1. Messaggi scaduti. I file agganciati vengono eliminati insieme.
        $fileKeys = $dryRun ? [] : Db::fetchAll(
            'SELECT sf.storage_key
             FROM shared_files sf
             JOIN messaggi m ON m.file_attachment_id = sf.id
             WHERE m.purge_after IS NOT NULL AND m.purge_after <= UTC_TIMESTAMP()'
        );
        $summary['messages'] = self::purgeColumn('messaggi', 'purge_after', $dryRun);
        foreach ($fileKeys as $row) {
            Upload::deleteStoredFile((string)$row['storage_key']);
        }

        // 2. File orfani o scaduti che non sono piu' agganciati a un messaggio.
        $orphanKeys = $dryRun ? [] : Db::fetchAll(
            'SELECT storage_key FROM shared_files
             WHERE purge_after IS NOT NULL AND purge_after <= UTC_TIMESTAMP()'
        );
        $summary['files'] = self::purgeColumn('shared_files', 'purge_after', $dryRun);
        foreach ($orphanKeys as $row) {
            Upload::deleteStoredFile((string)$row['storage_key']);
        }

        // 3. Sessioni scadute da almeno un TTL.
        $sessionsDays = Config::retentionDays('utenti_sessioni');
        $summary['sessions'] = $dryRun ? 0 : Db::execute(
            'DELETE FROM utenti_sessioni
             WHERE expires_at < ? AND (revoked_at IS NULL OR revoked_at < ?)',
            [
                gmdate('Y-m-d H:i:s', time() - $sessionsDays * 86400),
                gmdate('Y-m-d H:i:s', time() - $sessionsDays * 86400),
            ]
        );

        // 4. Audit: il termine piu' lungo serve a dimostrare responsabilita'.
        $auditDays = Config::retentionDays('audit_log');
        $summary['audit_log'] = $dryRun ? 0 : Db::execute(
            'DELETE FROM audit_log WHERE created_at < ?',
            [gmdate('Y-m-d H:i:s', time() - $auditDays * 86400)]
        );

        // 5. Prove di consenso, conservate piu' a lungo dei dati trattati.
        $consentDays = Config::retentionDays('consensi');
        $summary['consensi'] = $dryRun ? 0 : Db::execute(
            'DELETE FROM consensi WHERE recorded_at < ? AND user_id IS NULL',
            [gmdate('Y-m-d H:i:s', time() - $consentDays * 86400)]
        );

        // 6. Stato "sta scrivendo": inutile dopo pochi secondi.
        $summary['typing_status'] = $dryRun ? 0 : Db::execute(
            'DELETE FROM chat_typing_status WHERE updated_at < ?',
            [gmdate('Y-m-d H:i:s', time() - 3600)]
        );

        // 7. Eventi del rate limit.
        $summary['rate_limit_events'] = $dryRun ? 0 : Db::execute(
            'DELETE FROM rate_limit_events WHERE occurred_at < ?',
            [gmdate('Y-m-d H:i:s', time() - 3600)]
        );

        // 8. Cancellazioni definitive scadute la finestra di attesa.
        $erasures = Privacy::purgeDueErasures();
        $summary['erasure_requests'] = $erasures['processed'];

        if (!$dryRun && $summary['files'] + count($fileKeys) > 0) {
            $summary['orphan_directories_removed'] = Upload::pruneEmptyDirectories();
        }

        Logger::technical('info', 'Retention eseguita', $summary);

        return $summary;
    }

    /**
     * Cancella le righe la cui colonna `purge_after` e' scaduta, o — se il
     * termine non e' gia' impostato — quelle piu' vecchie del termine configurato.
     *
     * @return int numero stimato (in dry run) o effettivamente rimosso
     */
    private static function purgeColumn(string $table, string $column, bool $dryRun): int
    {
        if (!Db::tableExists($table)) {
            return 0;
        }

        try {
            if ($dryRun) {
                $row = Db::fetchOne(
                    "SELECT COUNT(*) AS c FROM `$table` WHERE `$column` IS NOT NULL AND `$column` <= UTC_TIMESTAMP()"
                );
                return (int)($row['c'] ?? 0);
            }

            return Db::execute(
                "DELETE FROM `$table` WHERE `$column` IS NOT NULL AND `$column` <= UTC_TIMESTAMP()"
            );
        } catch (\Throwable $e) {
            Logger::technical('error', "Purge fallito su $table", ['error' => $e->getMessage()]);
            return 0;
        }
    }

    /**
     * Imposta i termini di conservazione sugli elementi appena creati, in base
     * alla policy configurata. Va chiamato all'inserimento di messaggi e file.
     */
    public static function stampMessages(array $messageIds): void
    {
        if ($messageIds === []) {
            return;
        }
        $days = Config::retentionDays('messaggi');
        $purgeAfter = gmdate('Y-m-d H:i:s', time() + $days * 86400);
        $placeholders = implode(',', array_fill(0, count($messageIds), '?'));
        Db::execute(
            "UPDATE messaggi SET purge_after = ? WHERE id IN ($placeholders) AND purge_after IS NULL",
            array_merge([$purgeAfter], array_values($messageIds))
        );
    }

    public static function stampFiles(array $fileIds): void
    {
        if ($fileIds === []) {
            return;
        }
        $days = Config::retentionDays('shared_files');
        $purgeAfter = gmdate('Y-m-d H:i:s', time() + $days * 86400);
        $placeholders = implode(',', array_fill(0, count($fileIds), '?'));
        Db::execute(
            "UPDATE shared_files SET purge_after = ? WHERE id IN ($placeholders) AND purge_after IS NULL",
            array_merge([$purgeAfter], array_values($fileIds))
        );
    }
}
