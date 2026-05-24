<?php
require __DIR__ . '/vendor/autoload.php';

use Ratchet\MessageComponentInterface;
use Ratchet\ConnectionInterface;
use Ratchet\Server\IoServer;
use Ratchet\WebSocket\WsServer;
use Ratchet\Http\HttpServer;

class ChatServer implements MessageComponentInterface {
    protected $rooms = [];
    protected $connInfo = [];
    protected $typingState = [];

    public function onOpen(ConnectionInterface $conn) {
        $this->connInfo[$conn->resourceId] = ['conn' => $conn, 'userId' => null, 'username' => null, 'roomId' => null];
    }

    public function onMessage(ConnectionInterface $from, $msg) {
        $data = json_decode($msg, true);
        if (!is_array($data) || empty($data['type'])) return;

        $type = $data['type'];
        $userId = $data['userId'] ?? null;
        $payload = $data['payload'] ?? [];

        switch ($type) {
            case 'join':
                $roomId = $payload['roomId'] ?? null;
                $username = $payload['username'] ?? 'Anon';
                $this->connInfo[$from->resourceId] = ['conn'=>$from,'userId'=>$userId,'username'=>$username,'roomId'=>$roomId];
                if (!isset($this->rooms[$roomId])) $this->rooms[$roomId] = new \SplObjectStorage();
                $this->rooms[$roomId]->attach($from);
                $this->broadcast($roomId, ['type'=>'user_joined','userId'=>$userId,'payload'=>['username'=>$username]], $exclude=$from);
                break;

            case 'new_message':
                $roomId = $this->connInfo[$from->resourceId]['roomId'] ?? null;
                // Persist message here and compute definitive id if needed
                $out = ['type'=>'new_message','userId'=>$userId,'payload'=>$payload];
                $this->broadcast($roomId, $out, $exclude=null);
                break;

            case 'typing_start':
            case 'typing_stop':
            case 'recording_start':
            case 'recording_stop':
                $roomId = $this->connInfo[$from->resourceId]['roomId'] ?? null;
                $this->typingState[$roomId][$userId] = in_array($type, ['typing_start','recording_start']) ? $type : 'idle';
                $this->broadcast($roomId, ['type'=>$type,'userId'=>$userId,'payload'=>['username'=>$this->connInfo[$from->resourceId]['username'] ?? '']], $exclude=$from);
                break;
        }
    }

    public function onClose(ConnectionInterface $conn) {
        $info = $this->connInfo[$conn->resourceId] ?? null;
        if ($info) {
            $roomId = $info['roomId'];
            $userId = $info['userId'];
            if ($roomId && isset($this->rooms[$roomId])) {
                $this->rooms[$roomId]->detach($conn);
            }
            unset($this->connInfo[$conn->resourceId]);
            $this->broadcast($roomId, ['type'=>'user_left','userId'=>$userId,'payload'=>['username'=>$info['username'] ?? '']], $exclude=null);
        }
    }

    public function onError(ConnectionInterface $conn, \Exception $e) {
        $conn->close();
    }

    protected function broadcast($roomId, $messageArray, $exclude=null) {
        $msg = json_encode($messageArray);
        if (!isset($this->rooms[$roomId])) return;
        foreach ($this->rooms[$roomId] as $conn) {
            if ($exclude && $conn === $exclude) continue;
            $conn->send($msg);
        }
    }
}

$port = 8080;
echo "Starting WebSocket server on port {$port}\n";
$server = IoServer::factory(
    new HttpServer(new WsServer(new ChatServer())),
    $port
);
$server->run();
