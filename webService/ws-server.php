<?php
/**
 * ws-server.php — Server WebSocket opzionale per la messaggistica in tempo reale.
 *
 * STATO: opzionale. L'applicazione funziona senza, usando il polling HTTP
 * (8 secondi, 2 con la chat aperta). Questo file si avvia solo se le
 * dipendenze sono installate:
 *
 *     cd webService && composer install && php ws-server.php
 *
 * SICUREZZA — cosa cambia rispetto alla versione precedente
 * -------------------------------------------------------
 * La versione precedente accettava `userId` e `roomId` dichiarati dal client:
 * bastava inviare un messaggio con l'identificativo di un altro per leggere e
 * scrivere nella sua chat. Non esisteva autenticazione.
 *
 * Qui:
 *   - l'identita' NON viene mai accettata dal client: si deriva dal token di
 *     sessione, lo stesso usato dall'API REST;
 *   - l'autenticazione avviene con un PRIMO MESSAGGIO, non con un parametro
 *     nell'URL, cosi' il token non finisce nei log di accesso del reverse proxy;
 *   - l'ingresso in una stanza e' verificato contro l'iscrizione reale nel
 *     database: nessuno puo' entrare in una chat a cui non partecipa;
 *   - il contesto e' resettato se il token scade o viene revocato.
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/config.php';
require_once __DIR__ . '/lib/db.php';
require_once __DIR__ . '/lib/auth.php';
require_once __DIR__ . '/lib/logging.php';

Config::bootstrap();

$autoload = __DIR__ . '/vendor/autoload.php';
if (!is_readable($autoload)) {
    fwrite(STDERR, <<<TXT
    Manca vendor/autoload.php: le dipendenze Ratchet non sono installate.

        cd $(dirname(__DIR__)) && composer install

    Questo server e' opzionale: l'applicazione funziona anche senza, con il
    polling HTTP. Nessun dato viene perso semplicemente non avviandolo.

    TXT);
    exit(1);
}

require $autoload;

use Ratchet\MessageComponentInterface;
use Ratchet\ConnectionInterface;
use Ratchet\Server\IoServer;
use Ratchet\WebSocket\WsServer;
use Ratchet\Http\HttpServer;

final class ChatServer implements MessageComponentInterface
{
    /** Secondi entro cui una connessione deve autenticarsi. */
    private const AUTH_TIMEOUT_SECONDS = 10;

    /** @var array<int, array{conn: ConnectionInterface, userId: ?string, roomId: ?string, openedAt: int, token: ?string}> */
    private array $connInfo = [];

    /** @var array<string, SplObjectStorage<ConnectionInterface, null>> */
    private array $rooms = [];

    public function onOpen(ConnectionInterface $conn): void
    {
        $this->connInfo[$conn->resourceId] = [
            'conn'     => $conn,
            'userId'   => null,
            'roomId'   => null,
            'openedAt' => time(),
            'token'    => null,
        ];

        // Richiede l'autenticazione come primo atto.
        $conn->send(json_encode([
            'type'    => 'auth_required',
            'message' => 'Invia {"type":"auth","token":"..."} entro '
                . self::AUTH_TIMEOUT_SECONDS . ' secondi.',
        ]));
    }

    public function onMessage(ConnectionInterface $from, $msg): void
    {
        try {
            $data = json_decode($msg, true);
        } catch (\Throwable $e) {
            return;
        }
        if (!is_array($data) || !isset($data['type'])) {
            return;
        }

        $type = strval($data['type']);

        // 1. Autenticazione (obbligatoria come primo messaggio).
        if ($this->connInfo[$from->resourceId]['userId'] ?? null) {
            $this->handleAuthenticated($from, $type, $data);
            return;
        }

        if ($type !== 'auth') {
            $from->close(4401, 'Autenticazione richiesta');
            return;
        }

        if (time() - ($this->connInfo[$from->resourceId]['openedAt'] ?? time())
            > self::AUTH_TIMEOUT_SECONDS) {
            $from->close(4408, 'Tempo scaduto per l\'autenticazione');
            return;
        }

        $token = is_string($data['token'] ?? null) ? strval($data['token']) : '';
        $session = Auth::resolveToken($token);

        if ($session === null) {
            Logger::audit('ws.auth_failed', null, 'websocket', null, 'denied');
            $from->close(4401, 'Token non valido');
            return;
        }

        $this->connInfo[$from->resourceId]['userId'] = $session['user_id'];
        $this->connInfo[$from->resourceId]['token'] = $token;
        Logger::audit('ws.authenticated', $session['user_id'], 'websocket', null, 'ok');

        $from->send(json_encode([
            'type'    => 'auth_ok',
            'user_id' => $session['user_id'],
        ]));
    }

    /** Gestisce i messaggi successivi all'autenticazione. */
    private function handleAuthenticated(ConnectionInterface $from, string $type, array $data): void
    {
        // Rivalida a ogni messaggio: una sessione revocata dal server (per
        // esempio dopo un cambio password) deve chiudere la connessione.
        if (!$this->assertStillAuthorized($from)) {
            return;
        }

        $userId = $this->connInfo[$from->resourceId]['userId'];
        $payload = is_array($data['payload'] ?? null) ? $data['payload'] : [];

        switch ($type) {

            case 'join': {
                $roomId = strval($payload['roomId'] ?? '');
                if (!Auth::isValidUserId($roomId)) {
                    $from->close(4400, 'Identificativo chat non valido');
                    return;
                }
                if (!$this->isMember($roomId, strval($userId))) {
                    // Non si rivela se la chat esiste: si nega l'ingresso.
                    Logger::audit('ws.join_denied', $userId, 'chat', $roomId, 'denied');
                    $from->close(4403, 'Accesso negato a questa chat');
                    return;
                }

                // Lascia la stanza precedente, se diversa.
                $previous = $this->connInfo[$from->resourceId]['roomId'] ?? null;
                if ($previous !== null && $previous !== $roomId) {
                    $this->leaveRoom($from, $previous);
                }

                if (!isset($this->rooms[$roomId])) {
                    $this->rooms[$roomId] = new \SplObjectStorage();
                }
                $this->rooms[$roomId]->attach($from);
                $this->connInfo[$from->resourceId]['roomId'] = $roomId;

                $this->broadcast($roomId, [
                    'type'     => 'user_joined',
                    'user_id'  => $userId,
                    'chat_id'  => $roomId,
                ], $from);
                break;
            }

            case 'typing_start':
            case 'typing_stop':
            case 'recording_start':
            case 'recording_stop': {
                $roomId = $this->connInfo[$from->resourceId]['roomId'] ?? null;
                if ($roomId === null) {
                    return;
                }
                $state = in_array($type, ['typing_start', 'recording_start'], true)
                    ? $type
                    : 'idle';

                $this->broadcast($roomId, [
                    'type'    => $type,
                    'user_id' => $userId,
                    'chat_id' => $roomId,
                    'payload' => ['state' => $state],
                ], $from);
                break;
            }

            case 'ping': {
                $from->send(json_encode(['type' => 'pong', 'at' => time()]));
                break;
            }

            case 'new_message': {
                // La persistenza resta al backend REST: qui ci si limita a
                // notificare gli altri client della stanza, che rifanno il
                // fetch. Duplicare la scrittura del messaggio su due canali
                // creerebbe due fonti di verita' e il rischio di doppioni.
                $roomId = $this->connInfo[$from->resourceId]['roomId'] ?? null;
                if ($roomId === null) {
                    return;
                }
                $this->broadcast($roomId, [
                    'type'     => 'new_message',
                    'user_id'  => $userId,
                    'chat_id'  => $roomId,
                    'payload'  => ['refresh' => true],
                ], $from);
                break;
            }
        }
    }

    public function onClose(ConnectionInterface $conn): void
    {
        $info = $this->connInfo[$conn->resourceId] ?? null;
        if ($info === null) {
            return;
        }

        $roomId = $info['roomId'];
        $userId = $info['userId'];
        if ($roomId !== null) {
            $this->leaveRoom($conn, $roomId);
        }
        unset($this->connInfo[$conn->resourceId]);
    }

    public function onError(ConnectionInterface $conn, \Exception $e): void
    {
        Logger::technical('error', 'Errore WebSocket', ['message' => $e->getMessage()]);
        $conn->close();
    }

    private function leaveRoom(ConnectionInterface $conn, string $roomId): void
    {
        if (isset($this->rooms[$roomId])) {
            $this->rooms[$roomId]->detach($conn);
            if (count($this->rooms[$roomId]) === 0) {
                unset($this->rooms[$roomId]);
            }
        }
        $this->connInfo[$conn->resourceId]['roomId'] = null;
    }

    private function broadcast(string $roomId, array $message, ?ConnectionInterface $exclude = null): void
    {
        if (!isset($this->rooms[$roomId])) {
            return;
        }
        $encoded = json_encode($message, JSON_UNESCAPED_SLASHES);
        foreach ($this->rooms[$roomId] as $conn) {
            if ($exclude !== null && $conn === $exclude) {
                continue;
            }
            $conn->send($encoded);
        }
    }

    /** Verifica l'appartenza al database. Unica fonte di verita'. */
    private function isMember(string $chatId, string $userId): bool
    {
        try {
            $row = Db::fetchOne(
                'SELECT 1 AS ok FROM chat
                 WHERE IDchat = ?
                   AND (utente1 = ? OR utente2 = ?
                        OR IDchat IN (SELECT chat_id FROM chat_members WHERE user_id = ?))',
                [$chatId, $userId, $userId, $userId]
            );
            return $row !== null;
        } catch (\Throwable $e) {
            Logger::technical('error', 'Verifica appartenenza fallita', [
                'error' => $e->getMessage(),
            ]);
            // In caso di errore si nega l'accesso: meglio un falso negativo
            // che esporre una chat a chi non ne fa parte.
            return false;
        }
    }

    /**
     * Rivalida la sessione di una connessione autenticata. Chiamata a ogni
     * messaggio: se il token e' stato revocato o e' scaduto, la connessione
     * viene chiusa invece di restare attiva con permessi ormai decaduti.
     */
    private function assertStillAuthorized(ConnectionInterface $conn): bool
    {
        $info = $this->connInfo[$conn->resourceId] ?? null;
        if ($info === null || $info['userId'] === null) {
            return false;
        }

        $session = Auth::resolveToken($info['token'] ?? null);
        if ($session === null || $session['user_id'] !== $info['userId']) {
            Logger::audit('ws.session_invalidated', $info['userId'], 'websocket', null, 'denied');
            $conn->close(4401, 'Sessione non piu\' valida');
            unset($this->connInfo[$conn->resourceId]);
            return false;
        }

        return true;
    }
}

$port = (int)Config::get('QUICE_WS_PORT', '8080');
$bind = strval(Config::get('QUICE_WS_BIND', '127.0.0.1'));

echo "Server WebSocket in ascolto su {$bind}:{$port}\n";
echo "Autenticazione: primo messaggio {\"type\":\"auth\",\"token\":\"...\"}\n";

$server = IoServer::factory(
    new HttpServer(new WsServer(new ChatServer())),
    $port,
    $bind
);
$server->run();
