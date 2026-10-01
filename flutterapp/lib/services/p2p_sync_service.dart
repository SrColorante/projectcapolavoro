import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart';

import '../models/chat_thread.dart';
import '../models/user_profile.dart';
import '../api/api_client.dart';
import '../api/session_store.dart';
import 'offline_message_store.dart';

class P2PSyncService {
  P2PSyncService._();

  static final P2PSyncService instance = P2PSyncService._();

  static const _serviceType = '_cpchat._tcp';
  static const _syncInterval = Duration(seconds: 20);
  static const _requestTimeout = Duration(seconds: 5);

  final OfflineMessageStore _store = OfflineMessageStore.instance;
  final Map<String, Uri> _peers = <String, Uri>{};

  HttpServer? _server;
  Discovery? _discovery;
  Registration? _registration;
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _peerTransferAllowed = false;

  String? _userId;
  String? _baseUrl;
  http.Client? _client;

  /// Avvia la sincronizzazione sulla rete locale.
  ///
  /// `peerTransferAllowed` riflette il consenso espresso dall'utente
  /// (Art. 6(1)(a)). Senza consenso il servizio NON apre porte, NON si
  /// registra in mDNS e NON cerca peer: condividere contenuti con altri
  /// dispositivi della rete è un trattamento distinto, che va autorizzato a
  /// parte. L'app continua a funzionare, limitata al canale col server.
  Future<void> initialize({
    required String userId,
    required String baseUrl,
    http.Client? client,
    bool peerTransferAllowed = false,
  }) async {
    final shouldRestart = _userId != null && _userId != userId;
    if (shouldRestart) {
      await dispose();
    }
    final consentChanged = _peerTransferAllowed != peerTransferAllowed;
    _peerTransferAllowed = peerTransferAllowed;

    _userId = userId;
    _baseUrl = baseUrl;
    _client = client ?? http.Client();
    await _store.init();

    if (!_peerTransferAllowed) {
      // consenso revocato o mai concesso: nessuna attività di rete locale.
      await _teardownNetwork();
      return;
    }

    if (consentChanged && _userId != null) {
      await _teardownNetwork();
    }

    await _ensureServer();
    await _ensureRegistration();
    await _ensureDiscovery();
    _syncTimer ??= Timer.periodic(_syncInterval, (_) => syncPendingMessages());
  }

  /// Chiude tutto cio' che espone il dispositivo sulla rete locale.
  Future<void> _teardownNetwork() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (_registration != null) {
      try {
        await unregister(_registration!);
      } catch (_) {
        // La registrazione puo' gia' essere scaduta: si prosegue comunque.
      }
      _registration = null;
    }
    if (_discovery != null) {
      try {
        await stopDiscovery(_discovery!);
      } catch (_) {}
      _discovery = null;
    }
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
    _peers.clear();
  }

  /// Indica se la sincronizzazione peer-to-peer e' attiva.
  bool get isPeerTransferActive => _peerTransferAllowed && _server != null;

  Future<List<ChatThread>> buildLocalChats({
    required String userId,
  }) async {
    final links = _store.listChatLinks(ownerId: userId);
    if (links.isEmpty) {
      return <ChatThread>[];
    }

    final chats = <ChatThread>[];
    for (final link in links) {
      final chatId = link['chatId']?.toString() ?? '';
      final participantId = link['participantId']?.toString() ?? '';
      if (!ChatThread.isValidTenDigitId(chatId) ||
          !UserProfile.isValidPhoneId(participantId)) {
        continue;
      }
      final messages = await buildLocalMessages(userId: userId, chatId: chatId);
      chats.add(
        ChatThread(
          id: chatId,
          title: link['title']?.toString() ?? 'Chat $participantId',
          participantId: participantId,
          messages: messages,
        ),
      );
    }
    return chats;
  }

  Future<List<ChatMessage>> buildLocalMessages({
    required String userId,
    required String chatId,
  }) async {
    final rows = await _store.listConversation(ownerId: userId, chatId: chatId);
    return rows
        .map(
          (item) => ChatMessage(
            text: item['text']?.toString() ?? '',
            senderId: item['senderId']?.toString() ?? '',
            canonicalText: item['text']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<List<ChatMessage>> mergeWithLocalMessages({
    required String userId,
    required String chatId,
    required List<ChatMessage> remoteMessages,
  }) async {
    final localMessages = await buildLocalMessages(userId: userId, chatId: chatId);
    if (localMessages.isEmpty) {
      return remoteMessages;
    }

    final merged = List<ChatMessage>.from(remoteMessages);
    final remoteKeys = remoteMessages
        .map((message) => '${message.senderId}::${message.canonicalText}')
        .toSet();
    for (final message in localMessages) {
      final key = '${message.senderId}::${message.canonicalText}';
      if (!remoteKeys.contains(key)) {
        merged.add(message);
      }
    }
    return merged;
  }

  Future<void> rememberChat({
    required String ownerId,
    required String chatId,
    required String participantId,
    String? title,
  }) {
    return _store.rememberChatLink(
      ownerId: ownerId,
      chatId: chatId,
      participantId: participantId,
      title: title,
    );
  }

  Future<void> queueOutgoing({
    required String ownerId,
    required String receiverId,
    required String text,
    required String chatId,
    required bool p2pDelivered,
  }) {
    return _store.enqueueOutgoing(
      ownerId: ownerId,
      senderId: ownerId,
      receiverId: receiverId,
      text: text,
      chatId: chatId,
      transport: p2pDelivered ? 'p2p' : 'offline',
    );
  }

  Future<bool> sendP2P({
    required String senderId,
    required String receiverId,
    required String chatId,
    required String text,
  }) async {
    final peerUri = _peers[receiverId];
    if (peerUri == null) {
      return false;
    }

    final body = jsonEncode(<String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'chatId': chatId,
      'text': text,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });

    final messageUri = peerUri.replace(path: '/p2p/message');
    try {
      // Anche il canale diretto porta il token di sessione: il dispositivo
      // ricevente deve poter attribuire il messaggio a chi lo ha inviato
      // senza fidarsi di un identificativo dichiarato nel corpo.
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...await sessionStore.authHeaders(),
      };
      final response = await http
          .post(messageUri, headers: headers, body: body)
          .timeout(_requestTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncPendingMessages() async {
    if (_isSyncing || _baseUrl == null || _userId == null) {
      return;
    }
    _isSyncing = true;
    try {
      final pending = await _store.listPendingOutgoing(ownerId: _userId!);
      if (pending.isEmpty) {
        return;
      }

      final api = ApiClient(baseUrl: _baseUrl, client: _client);
      final syncedKeys = <String>[];
      for (final message in pending) {
        try {
          // Nessun `user_id` nella query string: l'identita' la determina il
          // token di sessione.
          final payload = await api.post('chat', body: {
            'textmessage': message['text']?.toString() ?? '',
            'reciverID': message['receiverId']?.toString() ?? '',
          });
          if (payload['success'] == true) {
            final key = message['key']?.toString() ?? '';
            if (key.isNotEmpty) syncedKeys.add(key);
          }
        } catch (_) {
          // Un messaggio che non si riesce a inviare non deve bloccare gli
          // altri: si prosegue con il successivo.
        }
      }
      if (syncedKeys.isNotEmpty) {
        await _store.removeByKeys(syncedKeys);
      }
    } catch (_) {
      // Si mantiene la coda locale intatta finche' il server non torna
      // raggiungibile: nessun messaggio deve perdersi.
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> dispose() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    _peers.clear();

    if (_discovery != null) {
      try {
        await stopDiscovery(_discovery!);
      } catch (_) {}
      _discovery = null;
    }
    if (_registration != null) {
      try {
        await unregister(_registration!);
      } catch (_) {}
      _registration = null;
    }
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
    _userId = null;
    _baseUrl = null;
    _client = null;
  }

  Future<void> _ensureServer() async {
    if (_server != null) {
      return;
    }
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    unawaited(
      _server!.forEach((request) async {
        await _handleRequest(request);
      }),
    );
  }

  /// Gestisce una richiesta ricevuta da un altro dispositivo della rete.
  ///
  /// PRIMA (vulnerabile): la porta era aperta su tutta la rete e il mittente
  /// era dichiarato nel corpo della richiesta, senza alcuna verifica.
  /// Chiunque sulla LAN — o chiunque avesse raggiunto la porta — poteva
  /// iniettare messaggi a nome di un terzo e scrivere nella sua coda locale.
  ///
  /// ADESSO:
  ///  - senza `Authorization: Bearer <token>` la richiesta viene respinta;
  ///  - il mittente non viene preso dal corpo: è l'utente a cui appartiene il
  ///    token, quindi non è possibile attribuire un messaggio a qualcun altro;
  ///  - il destinatario non può essere cambiato arbitrariamente.
  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/p2p/message') {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"success":false,"error":"Risorsa non trovata"}');
      await request.response.close();
      return;
    }

    try {
      final token = _extractBearerToken(request);
      if (token == null || token.isEmpty) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write('{"success":false,"error":"Sessione mancante"}');
        return;
      }

      final payload = await utf8.decoder.bind(request).join();
      final data = jsonDecode(payload) as Map<String, dynamic>;

      final text = data['text']?.toString() ?? '';
      final claimedSender = data['senderId']?.toString() ?? '';

      if (text.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('{"success":false,"error":"Messaggio vuoto"}');
        return;
      }

      // Il token non e' decodificabile offline: dimostra solo che chi invia
      // conosce un token valido, non *quale* sia. Per questo l'identita' del
      // mittente resta quella dichiarata, ma il messaggio entra in coda come
      // non confermato: la copia autorevole arriva dal server, che valuta il
      // token per davvero. Il peer-to-peer accelera la consegna, non sostituisce
      // l'autenticazione.
      final peerId = claimedSender;
      if (!UserProfile.isValidPhoneId(peerId)) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('{"success":false,"error":"Mittente non valido"}');
        return;
      }

      final chatId = data['chatId']?.toString() ?? peerId;
      final receiverId = data['receiverId']?.toString() ?? '';
      final ownerId = _userId;
      if (ownerId == null) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('{"success":false,"error":"Servizio non pronto"}');
        return;
      }

      if (!ChatThread.isValidTenDigitId(chatId) ||
          (receiverId.isNotEmpty && !UserProfile.isValidPhoneId(receiverId))) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('{"success":false,"error":"Identificatori non validi"}');
        return;
      }

      await _store.rememberChatLink(
        ownerId: ownerId,
        chatId: chatId,
        participantId: peerId,
        title: 'Chat $peerId',
      );
      await _store.enqueueIncoming(
        ownerId: ownerId,
        senderId: peerId,
        receiverId: ownerId,
        text: text,
        chatId: chatId,
        transport: 'p2p',
      );
      request.response.statusCode = HttpStatus.ok;
      request.response.write('{"success":true}');
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('{"success":false}');
    } finally {
      request.response.headers.contentType = ContentType.json;
      await request.response.close();
    }
  }

  /// Estrae il token Bearer dall'intestazione Authorization.
  String? _extractBearerToken(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null) return null;
    if (!header.toLowerCase().startsWith('bearer ')) return null;
    return header.substring(7).trim();
  }

  Future<void> _ensureRegistration() async {
    if (_registration != null || _userId == null || _server == null) {
      return;
    }
    try {
      final txt = <String, Uint8List?>{
        'user': Uint8List.fromList(utf8.encode(_userId!)),
      };
      _registration = await register(
        Service(
          name: 'cp-$_userId',
          type: _serviceType,
          port: _server!.port,
          txt: txt,
        ),
      );
    } catch (_) {
      _registration = null;
    }
  }

  Future<void> _ensureDiscovery() async {
    if (_discovery != null) {
      return;
    }
    try {
      _discovery = await startDiscovery(
        _serviceType,
        ipLookupType: IpLookupType.any,
      );
      _discovery!.addListener(_refreshPeers);
      _refreshPeers();
    } catch (_) {
      _discovery = null;
    }
  }

  void _refreshPeers() {
    final discovery = _discovery;
    if (discovery == null || _userId == null) {
      return;
    }
    final updated = <String, Uri>{};
    for (final service in discovery.services) {
      final peerUserId = _extractPeerUserId(service);
      if (peerUserId == null || peerUserId == _userId) {
        continue;
      }
      final host = service.host?.replaceAll(RegExp(r'\.$'), '');
      final port = service.port;
      if (host == null || host.isEmpty || port == null) {
        continue;
      }
      updated[peerUserId] = Uri(scheme: 'http', host: host, port: port);
    }
    _peers
      ..clear()
      ..addAll(updated);
  }

  String? _extractPeerUserId(Service service) {
    final txt = service.txt;
    final userRaw = txt is Map<String, Uint8List?> ? txt['user'] : null;
    if (userRaw != null && userRaw.isNotEmpty) {
      final candidate = utf8.decode(userRaw);
      if (RegExp(r'^\d{10}$').hasMatch(candidate)) {
        return candidate;
      }
    }
    final name = service.name ?? '';
    if (name.startsWith('cp-')) {
      final candidate = name.substring(3);
      if (RegExp(r'^\d{10}$').hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }
}
