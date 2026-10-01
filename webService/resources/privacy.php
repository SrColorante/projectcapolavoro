<?php
/**
 * resources/privacy.php — Esercizio dei diritti dell'interessato.
 *
 *   GET    /privacy            stato dei consensi + limitazione + sessioni
 *   GET    /privacy/export     fascicolo completo dei dati (Art. 15 e 20)
 *   POST   /privacy            azioni di controllo (vedi sotto)
 *
 * Tutte le rotte richiedono una sessione valida: nessun dato personale e'
 * ottenibile da anonimo.
 */

declare(strict_types=1);

require_once __DIR__ . '/../lib/privacy.php';
require_once __DIR__ . '/../lib/consent.php';

require_authentication();

$method = Http::method();

if ($method === 'GET') {
    $view = Http::query('view', 'status');

    if ($view === 'export') {
        Logger::audit('privacy.export', $current_user_id, 'utenti', $current_user_id, 'ok');

        $fascicolo = Privacy::buildExport($current_user_id);

        // Come richiesto dall'Art. 20, il formato e' leggibile da macchina e
        // strutturato: lo stesso oggetto JSON va bene sia per l'utente sia per
        // un eventuale importatore.
        $filename = 'quice-export-' . $current_user_id . '-' . gmdate('Ymd-His') . '.json';
        header('Content-Disposition: attachment; filename="' . $filename . '"');

        Http::success($fascicolo['export']);
    }

    $sessions = Db::fetchAll(
        'SELECT id, device_label, created_at, last_used_at, expires_at, revoked_at, revoked_reason
         FROM utenti_sessioni
         WHERE user_id = ?
         ORDER BY created_at DESC',
        [$current_user_id]
    );

    Http::success([
        'consents' => Consent::statusFor($current_user_id),
        'policy_version' => Consent::policyVersion(),
        'processing_restricted' => Privacy::isRestricted($current_user_id),
        'deletion' => [
            'requested_at' => $current_user['deletion_requested_at'] ?? null,
            'scheduled_for' => $current_user['deletion_scheduled_for'] ?? null,
            'cancellable' => ($current_user['deletion_requested_at'] ?? null) !== null
                && ($current_user['erased_at'] ?? null) === null,
        ],
        'retention' => [
            'messages_days' => Config::retentionDays('messaggi'),
            'files_days' => Config::retentionDays('shared_files'),
            'sessions_days' => Config::retentionDays('utenti_sessioni'),
            'audit_log_days' => Config::retentionDays('audit_log'),
            'consent_records_days' => Config::retentionDays('consensi'),
        ],
        'active_sessions' => array_map(static function (array $row): array {
            return [
                'id' => strval($row['id']),
                'device' => $row['device_label'],
                'created_at' => $row['created_at'],
                'last_used_at' => $row['last_used_at'],
                'expires_at' => $row['expires_at'],
                'active' => $row['revoked_at'] === null
                    && strtotime(strval($row['expires_at'])) > time(),
            ];
        }, $sessions),
        'rights' => [
            'access' => 'GET /privacy/export',
            'portability' => 'GET /privacy/export',
            'rectification' => 'PATCH /settings',
            'erasure' => 'POST /privacy {"action":"request_erasure"}',
            'restriction' => 'POST /privacy {"action":"restrict","value":true}',
            'objection' => 'POST /privacy {"action":"withdraw_consent","type":"..."}',
            'withdraw_consent' => 'POST /privacy {"action":"withdraw_consent","type":"..."}',
        ],
    ]);
    exit;
}

if ($method !== 'POST') {
    Http::error('Metodo non consentito', 405);
}

$action = strval($input['action'] ?? '');

switch ($action) {

    case 'grant_consent': {
        $type = strval($input['type'] ?? '');
        $granted = ($input['granted'] ?? true) !== false;

        if (!Consent::isKnownType($type)) {
            Http::error("Tipo di consenso non valido: $type", 400);
        }

        // Riconoscere un consenso non obbligatorio e' sempre libero. Negare
        // l'esecuzione del contratto, invece, non lo e': per quello serve
        // l'eliminazione dell'account, e glielo si dice esplicitamente.
        if (!$granted) {
            $error = Consent::withdraw($current_user_id, $type, 'privacy_settings');
            if ($error !== null) {
                Http::error($error, 409);
            }
        } else {
            Consent::record($current_user_id, $type, true, 'privacy_settings');
        }

        Http::success(
            ['consents' => Consent::statusFor($current_user_id)],
            ['type' => $type, 'granted' => $granted]
        );
        break;
    }

    case 'withdraw_consent': {
        $type = strval($input['type'] ?? '');
        $error = Consent::withdraw($current_user_id, $type, 'privacy_settings');
        if ($error !== null) {
            Http::error($error, 409);
        }
        Http::success(
            ['consents' => Consent::statusFor($current_user_id)],
            ['type' => $type, 'withdrawn' => true]
        );
        break;
    }

    case 'restrict': {
        // Art. 18: limitazione del trattamento. Blocca l'invio di nuovi dati
        // mantenendo accesso, rettifica e portabilita'.
        $restricted = ($input['value'] ?? true) !== false;
        Privacy::setProcessingRestriction($current_user_id, $restricted);
        Http::success(['processing_restricted' => $restricted]);
        break;
    }

    case 'request_erasure': {
        $confirmation = strval($input['confirmation'] ?? '');
        if ($confirmation !== 'ELIMINA') {
            Http::error(
                'Per confermare l\'eliminazione definitiva invia "confirmation":"ELIMINA". '
                . 'L\'operazione elimina profilo, messaggi, file e sessioni.',
                400
            );
        }

        try {
            $result = Privacy::requestErasure($current_user_id, 'user_request');
        } catch (RuntimeException $e) {
            Http::error($e->getMessage(), 409);
        }

        Http::success($result, [
            'warning' => 'Puoi annullare la richiesta fino alla data indicata '
                . 'tramite POST /auth {"action":"cancel_erasure"}.',
        ]);
        break;
    }

    case 'cancel_erasure': {
        try {
            Privacy::cancelErasure($current_user_id);
        } catch (RuntimeException $e) {
            Http::error($e->getMessage(), 409);
        }
        Http::success(['cancelled' => true, 'reauthentication_required' => true]);
        break;
    }

    case 'revoke_session': {
        $target = strval($input['session_id'] ?? '');
        $owned = Db::fetchOne(
            'SELECT id FROM utenti_sessioni WHERE id = ? AND user_id = ?',
            [$target, $current_user_id]
        );
        if ($owned === null) {
            Http::error('Sessione non trovata', 404);
        }
        Db::execute(
            'UPDATE utenti_sessioni SET revoked_at = ?, revoked_reason = ? WHERE id = ?',
            [gmdate('Y-m-d H:i:s'), 'revoked_by_user', intval($owned['id'])]
        );
        Logger::audit('session.revoked', $current_user_id, 'session', $target, 'ok');
        Http::success(['revoked' => true]);
        break;
    }

    default:
        Http::error(
            'Azione non valida. Usa grant_consent, withdraw_consent, restrict, '
            . 'request_erasure, cancel_erasure o revoke_session',
            400
        );
}
