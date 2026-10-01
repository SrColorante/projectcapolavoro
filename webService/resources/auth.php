<?php
/**
 * resources/auth.php — Registrazione, accesso, disconnessione, modifica password.
 *
 * Ogni risposta di successo che instaura una sessione restituisce un token
 * Bearer. Il client lo conserva in un archivio sicuro e lo invia nell'header
 * `Authorization`: la password non viene piu' inviata a ogni richiesta e non
 * viene piu' memorizzata sul dispositivo.
 */

declare(strict_types=1);

require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/consent.php';
require_once __DIR__ . '/../lib/privacy.php';

if (Http::method() !== 'POST') {
    Http::error('Metodo non consentito', 405);
}

$action = strval($input['action'] ?? '');
$phone = str_replace(' ', '', trim(strval($input['phone'] ?? '')));
$email = trim(strval($input['email'] ?? ''));
$password = strval($input['password'] ?? '');
$name = trim(strval($input['name'] ?? ''));
$deviceLabel = trim(strval($input['device_label'] ?? '')) ?: null;

$clientIp = Logger::clientIp();

/**
 * Proiezione del profilo verso il client.
 *
 * Nota GDPR: `email` e i dati della 2FA (canale + destinazione) NON vengono
 * restituiti in chiaro a ogni chiamata. Sono dati identificativi la cui
 * esposizione non e' necessaria al funzionamento dell'app: il client li riceve
 * una volta sola, al momento dell'accesso, e puo' chiederli esplicitamente
 * via /users. Ridurre la diffusione dei dati identificativi e' il primo dei
 * doveri del titolare (Art. 5(1)(c)).
 */
function build_profile(array $user, bool $includeSensitive = false): array
{
    $profile = [
        'id' => strval($user['IDutente']),
        'name' => $user['nome'],
        'nickname' => $user['nickname'],
        'is_guest' => boolval($user['is_guest'] ?? false),
        'preferred_language' => strval($user['preferred_language'] ?? 'en'),
        'profile_bio' => $user['profile_bio'] ?? null,
        'profile_photo_url' => $user['profile_photo_url'] ?? null,
        'profile_audio_url' => $user['profile_audio_url'] ?? null,
        'profile_audio_duration_seconds' => isset($user['profile_audio_duration_seconds'])
            ? floatval($user['profile_audio_duration_seconds'])
            : null,
        'two_factor_enabled' => boolval($user['two_factor_enabled'] ?? false),
        'processing_restricted' => boolval($user['processing_restricted'] ?? false),
        'deletion_requested_at' => $user['deletion_requested_at'] ?? null,
    ];

    if ($includeSensitive) {
        $profile['email'] = $user['email'] ?? null;
        $profile['two_factor_channel'] = $user['two_factor_channel'] ?? null;
        $profile['two_factor_destination'] = $user['two_factor_destination'] ?? null;
    }

    return $profile;
}

/** Genera un ID a 10 cifre non ancora presente. */
function generate_unique_user_id(PDO $pdo): string
{
    do {
        $candidate = strval(random_int(1000000000, 9999999999));
        $stmt = $pdo->prepare('SELECT 1 FROM utenti WHERE IDutente = ?');
        $stmt->execute([$candidate]);
        $exists = $stmt->fetchColumn();
    } while ($exists);

    return $candidate;
}

/** Etichetta del dispositivo, per permettere all'utente di riconoscere le sessioni. */
function resolve_device_label(?string $requested): ?string
{
    if ($requested !== null && $requested !== '') {
        return mb_substr($requested, 0, 120);
    }
    $agent = strval($_SERVER['HTTP_USER_AGENT'] ?? '');
    return $agent === '' ? null : mb_substr($agent, 0, 120);
}

switch ($action) {

    case 'register': {
        // L'identificativo e' il numero di telefono: esattamente 10 cifre.
        // Prima l'app accettava 8-15 cifre mentre il server ne richiedeva 10:
        // la registrazione riusciva ma l'accesso successivo falliva per
        // sempre, lasciando l'utente bloccato fuori dal proprio account.
        if (!Auth::isValidUserId($phone)) {
            Http::error(
                'Il numero di telefono deve essere composto da esattamente 10 cifre.',
                400
            );
        }

        $strengthError = Auth::validatePasswordStrength($password);
        if ($strengthError !== null) {
            Http::error($strengthError, 400);
        }

        Auth::assertLoginAllowed($phone, $clientIp);

        if (Db::fetchOne('SELECT 1 AS ok FROM utenti WHERE IDutente = ?', [$phone]) !== null) {
            Http::error('Numero di telefono gia\' registrato', 409);
        }

        $normalizedEmail = null;
        if ($email !== '') {
            if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
                Http::error('Indirizzo email non valido', 400);
            }
            if (Db::fetchOne('SELECT 1 AS ok FROM utenti WHERE email = ?', [$email]) !== null) {
                Http::error('Email gia\' registrata', 409);
            }
            $normalizedEmail = $email;
        }

        $displayName = $name !== '' ? mb_substr($name, 0, 20) : 'Nuovo utente';
        $requestedLanguage = strtolower(strval($input['preferred_language'] ?? 'en'));
        $language = preg_match('/^[a-z]{2}$/', $requestedLanguage) === 1
            ? $requestedLanguage
            : 'en';

        Db::execute(
            'INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash,
                                 dataCreazione, is_guest, preferred_language)
             VALUES (?, ?, ?, ?, ?, ?, CURDATE(), 0, ?)',
            [
                $phone,
                $displayName,
                'Utente',
                $displayName,
                $normalizedEmail,
                password_hash($password, PASSWORD_DEFAULT),
                $language,
            ]
        );

        // Il consenso all'informativa e' parte della validazione del contratto
        // (Art. 6(1)(b) / Art. 7(1)): va registrato con l'azione che lo ha
        // prodotto, altrimenti la prova non e' completa.
        Consent::record($phone, 'privacy_policy', true, 'registration');
        Consent::record($phone, 'data_processing', true, 'registration');

        $user = Db::fetchOne('SELECT * FROM utenti WHERE IDutente = ?', [$phone]);
        $issued = Auth::issueToken($phone, resolve_device_label($deviceLabel), $clientIp);

        Http::success(
            array_merge(
                ['user' => build_profile($user ?? [], true)],
                $issued
            ),
            ['consents' => Consent::statusFor($phone)]
        );
        break;
    }

    case 'login': {
        if (!Auth::isValidUserId($phone) || $password === '') {
            Http::error('Specificare numero di telefono e password', 400);
        }

        Auth::assertLoginAllowed($phone, $clientIp);

        $user = Auth::verifyPassword($phone, $password);
        if ($user === null) {
            Logger::audit('login.failed', $phone, null, null, 'denied');
            // Messaggio identico a quello per utente inesistente: non
            // riveliamo se il numero e' registrato.
            Http::error('Credenziali non valide', 401);
        }

        if (($user['erased_at'] ?? null) !== null) {
            Http::error('Questo account e\' stato eliminato.', 410);
        }

        // L'utente puo' annullare la cancellazione entro la finestra di attesa.
        $requested = $user['deletion_requested_at'] ?? null;
        $cancelling = $requested !== null
            && (strtotime(strval($requested)) + 86400 * 3) > time();

        Logger::audit('login.succeeded', $phone, null, null, 'ok');
        $issued = Auth::issueToken($phone, resolve_device_label($deviceLabel), $clientIp);

        Http::success(
            array_merge(
                [
                    'user' => build_profile($user, true),
                    'cancellation_pending' => $cancelling,
                ],
                $issued
            ),
            ['consents' => Consent::statusFor($phone)]
        );
        break;
    }

    case 'guest_login': {
        $guestId = generate_unique_user_id(Db::pdo());
        $guestName = $name !== '' ? mb_substr($name, 0, 20) : 'Ospite';

        // Un account ospite non riceve email e non ha una password utilizzabile:
        // il segreto e' casuale e non viene mai mostrato, quindi non puo'
        // essere indovinato ne' ripristinato.
        Db::execute(
            'INSERT INTO utenti (IDutente, nome, cognome, nickname, email, password_hash,
                                 dataCreazione, is_guest, preferred_language, data_retention_until)
             VALUES (?, ?, ?, ?, ?, ?, CURDATE(), 1, ?, ?)',
            [
                $guestId,
                $guestName,
                'Ospite',
                $guestName,
                null,
                password_hash(bin2hex(random_bytes(24)), PASSWORD_DEFAULT),
                strtolower(strval($input['preferred_language'] ?? 'en')) ?: 'en',
                // Gli ospiti sono dati a termine di scadenza: minimizzazione.
                gmdate('Y-m-d', time() + 7 * 86400),
            ]
        );

        Consent::record($guestId, 'privacy_policy', true, 'guest_registration');
        Consent::record($guestId, 'data_processing', true, 'guest_registration');

        $user = Db::fetchOne('SELECT * FROM utenti WHERE IDutente = ?', [$guestId]);
        $issued = Auth::issueToken($guestId, resolve_device_label($deviceLabel), $clientIp);

        Logger::audit('guest.created', $guestId, 'utenti', $guestId, 'ok');

        Http::success(
            array_merge(
                [
                    'user' => build_profile($user ?? [], true),
                    'auto_delete_at' => gmdate('c', strtotime('+7 days')),
                ],
                $issued
            )
        );
        break;
    }

    case 'logout': {
        // Il token puo' essere letto anche se la sessione e' gia' scaduta:
        // in quel caso si risponde comunque 200, per non rivelare lo stato.
        $token = Http::bearerToken();
        if ($token !== null) {
            Auth::revokeToken($token);
        }
        Http::success(['logged_out' => true]);
        break;
    }

    case 'change_password': {
        require_authentication();

        $current = strval($input['current_password'] ?? '');
        $new = strval($input['new_password'] ?? '');

        $strengthError = Auth::validatePasswordStrength($new);
        if ($strengthError !== null) {
            Http::error($strengthError, 400);
        }
        if ($current === '' || $current === $new) {
            Http::error('La nuova password deve essere diversa da quella attuale.', 400);
        }

        $user = Auth::verifyPassword($current_user_id, $current);
        if ($user === null) {
            Logger::audit('password.change_failed', $current_user_id, null, null, 'denied');
            Http::error('Password attuale non corretta', 401);
        }

        Db::execute(
            'UPDATE utenti SET password_hash = ? WHERE IDutente = ?',
            [password_hash($new, PASSWORD_DEFAULT), $current_user_id]
        );

        // Cambiando la password si revocano le altre sessioni: e' il comportamento
        // atteso e limita l'impatto di un dispositivo perso o rubato.
        $keptSessionId = $current_session['session_id'] ?? null;
        $revoked = Auth::revokeAllForUser($current_user_id, 'password_changed');
        $freshToken = Auth::issueToken($current_user_id, $current_session['device_label'] ?? null, $clientIp);

        Logger::audit('password.changed', $current_user_id, null, null, 'ok');

        Http::success(array_merge(
            ['other_sessions_revoked' => max(0, $revoked - 1)],
            $freshToken
        ));
        break;
    }

    case 'cancel_erasure': {
        require_authentication();
        try {
            Privacy::cancelErasure($current_user_id);
        } catch (RuntimeException $e) {
            Http::error($e->getMessage(), 400);
        }
        // Le sessioni restano revocate: l'utente deve autenticarsi di nuovo.
        Http::success(['cancelled' => true, 'reauthentication_required' => true]);
        break;
    }

    case 'enable_2fa':
    case 'certify_pec': {
        require_authentication();

        $channel = strval($input['two_factor_channel'] ?? '');
        $destination = trim(strval($input['two_factor_destination'] ?? ''));
        $secret = strval($input['password'] ?? '');

        if (!Auth::verifyPassword($current_user_id, $secret)) {
            Http::error('Password non corretta', 401);
        }

        if ($action === 'enable_2fa') {
            if (!in_array($channel, ['email', 'phone'], true) || $destination === '') {
                Http::error('Specificare canale (email|phone) e destinazione per la 2FA', 400);
            }
            if ($channel === 'email' && filter_var($destination, FILTER_VALIDATE_EMAIL) === false) {
                Http::error('Destinazione email non valida', 400);
            }
            if ($channel === 'phone' && !Auth::isValidUserId($destination)) {
                Http::error('Destinazione telefonica non valida: servono 10 cifre', 400);
            }

            Db::execute(
                'UPDATE utenti
                 SET two_factor_enabled = 1, two_factor_channel = ?, two_factor_destination = ?
                 WHERE IDutente = ?',
                [$channel, $destination, $current_user_id]
            );
            Logger::audit('twofactor.enabled', $current_user_id, 'utenti', $current_user_id, 'ok');
            Http::success(['message' => '2FA abilitata', 'two_factor_channel' => $channel]);
            break;
        }

        $affected = Db::execute(
            'UPDATE utenti SET pec_certified_at = NOW()
             WHERE IDutente = ? AND two_factor_enabled = 1',
            [$current_user_id]
        );
        if ($affected === 0) {
            Http::error('Per la certificazione e\' necessaria la 2FA abilitata', 400);
        }
        Logger::audit('pec.certified', $current_user_id, 'utenti', $current_user_id, 'ok');
        Http::success(['message' => 'Utente certificato in stile PEC']);
        break;
    }

    default:
        Http::error(
            'Azione non valida. Usa register, login, guest_login, logout, '
            . 'change_password, cancel_erasure, enable_2fa o certify_pec',
            400
        );
}
