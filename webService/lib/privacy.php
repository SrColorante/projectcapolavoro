<?php
/**
 * privacy.php — Diritti dell'interessato (GDPR Art. 15, 16, 17, 18, 20, 21).
 *
 *  Art. 15/20  accesso e portabilita'  -> Privacy::buildExport()
 *  Art. 16    rettifica                 -> gestita da resources/settings.php
 *  Art. 17    oblio                     -> Privacy::requestErasure() + Privacy::purgeErasures()
 *  Art. 18    limitazione               -> Privacy::setProcessingRestriction()
 *  Art. 21    opposizione              -> revoca consensi + cancellazione
 *
 * Principi applicati:
 *  - cancellazione in cascata su TUTTI i dati, compresi i file su disco;
 *  - finestra di attesa prima della cancellazione definitiva, cosi' una
 *    richiesta fatta per errore e' reversibile (Art. 19: notifica agli altri
 *    titolari quando si cancella il dato di terzi);
 *  - i consensi NON vengono cancellati insieme ai dati: sono la prova della
 *    liceita' del trattamento e sopravvivono in forma pseudonima;
 *  - l'audit log conserva pseudonimo e azione, ma l'identificativo diretto
 *    viene rimesso a NULL, cosi' la responsabilita' resta dimostrabile senza
 *    mantenere il dato identificativo (tecnica di pseudonizzazione, Art. 4(5)).
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/logging.php';
require_once __DIR__ . '/http.php';
require_once __DIR__ . '/consent.php';
require_once __DIR__ . '/upload.php';

final class Privacy
{
    /**
     * Costruisce il fascicolo completo dei dati di un utente, in JSON
     * leggibile da macchina (Art. 15 e Art. 20).
     */
    public static function buildExport(string $userId): array
    {
        $user = Db::fetchOne('SELECT * FROM utenti WHERE IDutente = ?', [$userId]);

        $profile = [];
        if ($user !== null) {
            // password_hash ed e2ee_public_key restano esclusi per non
            // distribuire materiale di autenticazione in un file di export.
            $profile = [
                'id' => strval($user['IDutente']),
                'name' => $user['nome'],
                'nickname' => $user['nickname'],
                'email' => $user['email'],
                'is_guest' => (bool)$user['is_guest'],
                'preferred_language' => $user['preferred_language'],
                'profile_bio' => $user['profile_bio'],
                'profile_photo' => $user['profile_photo_url'],
                'profile_audio' => $user['profile_audio_url'],
                'profile_audio_duration_seconds' => $user['profile_audio_duration_seconds'],
                'created_at' => $user['dataCreazione'],
                'two_factor_enabled' => (bool)$user['two_factor_enabled'],
                'processing_restricted' => (bool)($user['processing_restricted'] ?? false),
                'deletion_requested_at' => $user['deletion_requested_at'],
            ];
        }

        $messages = Db::fetchAll(
            "SELECT m.id, m.textmessage, m.senderID, m.reciverID, m.chat_id,
                    m.timenow, m.is_certified, m.deleted_at,
                    c.is_group, c.name AS chat_name
             FROM messaggi m
             LEFT JOIN chat c ON c.IDchat = m.chat_id
             WHERE m.senderID = ? OR m.reciverID = ?
                OR m.chat_id IN (SELECT chat_id FROM chat_members WHERE user_id = ?)
             ORDER BY m.timenow ASC, m.id ASC",
            [$userId, $userId, $userId]
        );

        $files = Db::fetchAll(
            'SELECT id, file_name, mime_type, size_bytes, preview_type, created_at,
                    message_id, deleted_at
             FROM shared_files
             WHERE owner_user_id = ?
             ORDER BY created_at ASC',
            [$userId]
        );

        $chats = Db::fetchAll(
            "SELECT c.IDchat, c.is_group, c.name, c.created_at
             FROM chat c
             WHERE c.utente1 = ? OR c.utente2 = ?
                OR c.IDchat IN (SELECT chat_id FROM chat_members WHERE user_id = ?)
             ORDER BY c.created_at ASC",
            [$userId, $userId, $userId]
        );

        $sessions = Db::fetchAll(
            'SELECT device_label, created_at, last_used_at, expires_at, revoked_at, revoked_reason
             FROM utenti_sessioni WHERE user_id = ? ORDER BY created_at ASC',
            [$userId]
        );

        $audit = Db::fetchAll(
            'SELECT action, resource_type, resource_id, outcome, correlation_id, created_at
             FROM audit_log WHERE actor_user_id = ? ORDER BY created_at ASC',
            [$userId]
        );

        return [
            'export' => [
                'format' => 'quice-export/1.0',
                'generated_at' => gmdate('c'),
                'controller' => [
                    'identity' => 'Da completare con i dati del titolare del trattamento '
                        . '(vedi docs/LEGAL/ROPA.md)',
                ],
                'subject' => $profile,
                'conversations' => array_map(static function (array $row): array {
                    return [
                        'id' => strval($row['IDchat']),
                        'is_group' => (bool)$row['is_group'],
                        'name' => $row['name'] ?? null,
                        'created_at' => $row['created_at'] ?? null,
                    ];
                }, $chats),
                'messages' => array_map(static function (array $row) use ($userId): array {
                    return [
                        'id' => strval($row['id']),
                        'content' => $row['deleted_at'] !== null ? null : $row['textmessage'],
                        'redacted' => $row['deleted_at'] !== null,
                        'sent_by_me' => strval($row['senderID']) === $userId,
                        'chat_id' => $row['chat_id'] === null ? null : strval($row['chat_id']),
                        'chat_name' => $row['chat_name'],
                        'timestamp' => $row['timenow'],
                        'certified' => (bool)$row['is_certified'],
                        'deleted_at' => $row['deleted_at'],
                    ];
                }, $messages),
                'files' => array_map(static function (array $row): array {
                    return [
                        'id' => strval($row['id']),
                        'name' => $row['file_name'],
                        'mime_type' => $row['mime_type'],
                        'size_bytes' => (int)$row['size_bytes'],
                        'preview_type' => $row['preview_type'],
                        'uploaded_at' => $row['created_at'],
                        'linked_message_id' => $row['message_id'] === null
                            ? null
                            : strval($row['message_id']),
                        'deleted_at' => $row['deleted_at'],
                    ];
                }, $files),
                'sessions' => array_map(static function (array $row): array {
                    return [
                        'device' => $row['device_label'],
                        'created_at' => $row['created_at'],
                        'last_used_at' => $row['last_used_at'],
                        'expires_at' => $row['expires_at'],
                        'revoked_at' => $row['revoked_at'],
                        'revoked_reason' => $row['revoked_reason'],
                    ];
                }, $sessions),
                'consents' => Consent::historyFor($userId),
                'processing_restriction' => [
                    'restricted' => (bool)($user['processing_restricted'] ?? false),
                    'set_at' => $user['processing_restricted_at'] ?? null,
                ],
                'audit_trail' => array_map(static function (array $row): array {
                    return [
                        'action' => $row['action'],
                        'resource_type' => $row['resource_type'],
                        'resource_id' => $row['resource_id'],
                        'outcome' => $row['outcome'],
                        'correlation_id' => $row['correlation_id'],
                        'at' => $row['created_at'],
                    ];
                }, $audit),
                'retention' => [
                    'messages_days' => Config::retentionDays('messaggi'),
                    'files_days' => Config::retentionDays('shared_files'),
                    'sessions_days' => Config::retentionDays('utenti_sessioni'),
                    'audit_log_days' => Config::retentionDays('audit_log'),
                    'consent_records_days' => Config::retentionDays('consensi'),
                ],
            ],
        ];
    }

    /**
     * Segnala l'intenzione di cancellare l'account. L'account viene prima
     * "congelato" (accesso ridotto, nuove sessioni bloccate) e poi eliminato
     * definitivamente da `purgeErasures()` al termine della finestra di attesa.
     */
    public static function requestErasure(string $userId, ?string $reason = null): array
    {
        if (!Db::tableExists('utenti')) {
            throw new RuntimeException('Schema non inizializzato.');
        }

        $user = Db::fetchOne('SELECT erased_at FROM utenti WHERE IDutente = ?', [$userId]);
        if ($user === null) {
            throw new RuntimeException('Utente inesistente.');
        }
        if ($user['erased_at'] !== null) {
            throw new RuntimeException('Account gia\' cancellato.');
        }

        $graceDays = Config::erasureGraceDays();
        $now = gmdate('Y-m-d H:i:s');
        $scheduledFor = gmdate('Y-m-d H:i:s', time() + $graceDays * 86400);

        Db::execute(
            'UPDATE utenti
             SET deletion_requested_at = ?, deletion_scheduled_for = ?, deletion_reason = ?
             WHERE IDutente = ?',
            [$now, $scheduledFor, $reason, $userId]
        );

        // Le sessioni aperte vengono chiuse subito: l'utente non deve piu'
        // usare il servizio mentre la cancellazione e' in corso.
        Db::execute(
            'UPDATE utenti_sessioni SET revoked_at = ?, revoked_reason = ?
             WHERE user_id = ? AND revoked_at IS NULL',
            [$now, 'erasure_requested', $userId]
        );

        Logger::audit('privacy.erasure_requested', $userId, 'utenti', $userId, 'ok', [
            'grace_days' => $graceDays,
            'scheduled_for' => $scheduledFor,
        ]);

        return [
            'requested_at' => gmdate('c', strtotime($now)),
            'scheduled_erasure_at' => gmdate('c', strtotime($scheduledFor)),
            'grace_days' => $graceDays,
            'can_be_cancelled' => true,
        ];
    }

    /**
     * Annulla una richiesta di cancellazione prima che diventi definitiva.
     * Le sessioni non vengono riapplicate automaticamente: l'utente dovra'
     * autenticarsi di nuovo, ed e' il comportamento atteso dopo un
     * evento di sicurezza.
     */
    public static function cancelErasure(string $userId): void
    {
        $affected = Db::execute(
            'UPDATE utenti
             SET deletion_requested_at = NULL, deletion_scheduled_for = NULL, deletion_reason = NULL
             WHERE IDutente = ? AND erased_at IS NULL',
            [$userId]
        );
        if ($affected === 0) {
            throw new RuntimeException('Nessuna cancellazione da annullare.');
        }
        Logger::audit('privacy.erasure_cancelled', $userId, 'utenti', $userId, 'ok');
    }

    /**
     * Elimina definitivamente tutti i dati di un utente. Cancellazione in
     * cascata su database e filesystem.
     *
     * @return array riepilogo delle cancellazioni effettuate
     */
    public static function purgeUser(string $userId): array
    {
        if (!Db::tableExists('utenti')) {
            throw new RuntimeException('Schema non inizializzato.');
        }

        $pseudonym = Logger::pseudonymize($userId);

        return Db::transaction(function (PDO $pdo) use ($userId, $pseudonym): array {
            $summary = ['messages' => 0, 'files' => 0, 'chats' => 0, 'sessions' => 0];

            // 1. File fisici. Vanno raccolti prima che le righe spariscano,
            //    altrimenti si perdono i riferimenti ai file su disco.
            $fileRows = Db::fetchAll(
                'SELECT storage_key FROM shared_files WHERE owner_user_id = ?',
                [$userId]
            );
            $summary['file_count'] = count($fileRows);
            foreach ($fileRows as $row) {
                Upload::deleteStoredFile((string)$row['storage_key']);
            }

            // 2. Messaggi inviati e ricevuti, incluse le chat di gruppo.
            $summary['messages'] = Db::execute(
                'DELETE FROM messaggi
                 WHERE senderID = ?
                    OR reciverID = ?
                    OR chat_id IN (SELECT chat_id FROM chat_members WHERE user_id = ?)',
                [$userId, $userId, $userId]
            );

            // 3. File condivisi.
            $summary['files'] = Db::execute(
                'DELETE FROM shared_files WHERE owner_user_id = ?',
                [$userId]
            );

            // 4. Appartenenza ai gruppi.
            Db::execute('DELETE FROM chat_members WHERE user_id = ?', [$userId]);
            Db::execute('DELETE FROM chat_typing_status WHERE user_id = ?', [$userId]);

            // 5. Chat 1-to-1 e gruppi rimasti senza membri.
            $orphanChats = Db::fetchAll(
                'SELECT IDchat FROM chat
                 WHERE (utente1 = ? OR utente2 = ? OR created_by = ?)
                   AND IDchat NOT IN (SELECT chat_id FROM chat_members)'
                . ' AND NOT EXISTS (SELECT 1 FROM messaggi m WHERE m.chat_id = chat.IDchat)',
                [$userId, $userId, $userId]
            );
            foreach ($orphanChats as $row) {
                Db::execute('DELETE FROM chat WHERE IDchat = ?', [$row['IDchat']]);
                $summary['chats']++;
            }
            // Le chat che conservano messaggi di terzi non si cancellano:
            // cancellarle distruggerebbe dati di altri interessati senza
            // che ne abbiano chiesto la cancellazione.
            Db::execute(
                'UPDATE chat SET utente1 = NULL, utente2 = NULL, created_by = NULL
                 WHERE utente1 = ? OR utente2 = ?',
                [$userId, $userId]
            );

            // 6. Sessioni.
            $summary['sessions'] = Db::execute(
                'DELETE FROM utenti_sessioni WHERE user_id = ?',
                [$userId]
            );

            // 7. Codici 2FA.
            try {
                Db::execute('DELETE FROM otp_two_factor_codes WHERE userID = ?', [$userId]);
            } catch (\Throwable $e) {
                // Tabella opzionale.
            }

            // 8. Consensi: NON cancellati, ma resi pseudonimi. Sono la prova
            //    della liceita' del trattamento e devono restare
            //    dimostrabili anche dopo l'oblio (Art. 7(1), Art. 17(3)(b)).
            Db::execute(
                'UPDATE consensi
                 SET user_id = NULL, subject_pseudonym = ?, ip_hash = NULL
                 WHERE user_id = ?',
                [$pseudonym, $userId]
            );

            // 9. Audit: l'identificativo diretto sparisce, azione e pseudonimo
            //    restano (Art. 17(3)(e) — obblighi legali, Art. 5(2)).
            Db::execute(
                'UPDATE audit_log
                 SET actor_user_id = NULL, actor_pseudonym = COALESCE(actor_pseudonym, ?),
                     ip_hash = NULL
                 WHERE actor_user_id = ?',
                [$pseudonym, $userId]
            );

            // 10. Utente.
            Db::execute('DELETE FROM utenti WHERE IDutente = ?', [$userId]);

            Logger::audit('privacy.erasure_completed', null, 'utenti', $pseudonym, 'ok',
                array_merge(['subject' => $pseudonym], $summary));

            return $summary;
        });
    }

    /**
     *Esegue le cancellazioni definitive scadute la finestra di attesa.
     * Da richiamare periodicamente (cron giornaliero).
     */
    public static function purgeDueErasures(): array
    {
        if (!Db::tableExists('utenti')) {
            return ['processed' => 0, 'details' => []];
        }

        $due = Db::fetchAll(
            'SELECT IDutente FROM utenti
             WHERE erased_at IS NULL
               AND deletion_requested_at IS NOT NULL
               AND deletion_scheduled_for IS NOT NULL
               AND deletion_scheduled_for <= UTC_TIMESTAMP()'
        );

        $details = [];
        foreach ($due as $row) {
            $userId = strval($row['IDutente']);
            try {
                $summary = self::purgeUser($userId);
                $details[] = ['subject' => Logger::pseudonymize($userId), 'summary' => $summary];
            } catch (\Throwable $e) {
                Logger::technical('error', 'Cancellazione fallita', [
                    'subject' => Logger::pseudonymize($userId),
                    'error' => $e->getMessage(),
                ]);
            }
        }

        return ['processed' => count($details), 'details' => $details];
    }

    /**
     * Art. 18 — limitazione del trattamento. Blocca la conservazione e
     * l'invio di nuovi dati mantenendo accesso e rettifica.
     */
    public static function setProcessingRestriction(string $userId, bool $restricted): void
    {
        Db::execute(
            'UPDATE utenti SET processing_restricted = ?, processing_restricted_at = ? WHERE IDutente = ?',
            [$restricted ? 1 : 0, $restricted ? gmdate('Y-m-d H:i:s') : null, $userId]
        );
        Logger::audit(
            $restricted ? 'privacy.restriction_set' : 'privacy.restriction_lifted',
            $userId,
            'utenti',
            $userId,
            'ok'
        );
    }

    public static function isRestricted(string $userId): bool
    {
        $row = Db::fetchOne('SELECT processing_restricted FROM utenti WHERE IDutente = ?', [$userId]);
        return $row !== null && (bool)$row['processing_restricted'];
    }
}
