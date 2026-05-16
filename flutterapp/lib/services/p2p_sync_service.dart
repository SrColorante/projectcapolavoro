import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart';

import '../models/chat_thread.dart';
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

  String? _userId;
  String? _baseUrl;
  http.Client? _client;

  Future<void> initialize({
    required String userId,
    required String baseUrl,
    required http.Client client,
  }) async {
    final shouldRestart = _userId != null && _userId != userId;
    if (shouldRestart) {
      await dispose();
    }

    _userId = userId;
    _baseUrl = baseUrl;
    _client = client;
    await _store.init();

    await _ensureServer();
    await _ensureRegistration();
    await _ensureDiscovery();
    _syncTimer ??= Timer.periodic(_syncInterval, (_) => syncPendingMessages());
  }

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
          !ChatThread.isValidTenDigitId(participantId)) {
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
        .map((message) => '${message.senderId}::${message.text}')
        .toSet();
    for (final message in localMessages) {
      final key = '${message.senderId}::${message.text}';
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
      final response = await _client!
          .post(
            messageUri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_requestTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncPendingMessages() async {
    if (_isSyncing || _client == null || _baseUrl == null || _userId == null) {
      return;
    }
    _isSyncing = true;
    try {
      final pending = await _store.listPendingOutgoing(ownerId: _userId!);
      if (pending.isEmpty) {
        return;
      }

      final syncedKeys = <String>[];
      for (final message in pending) {
        final response = await _client!
            .post(
              Uri.parse('$_baseUrl/chat').replace(
                queryParameters: {'user_id': message['senderId']?.toString() ?? ''},
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'textmessage': message['text']?.toString() ?? '',
                'reciverID': message['receiverId']?.toString() ?? '',
              }),
            )
            .timeout(_requestTimeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final payload = jsonDecode(response.body);
          if (payload is Map<String, dynamic> && payload['success'] == true) {
            syncedKeys.add(message['key']?.toString() ?? '');
          }
        }
      }
      final filteredKeys = syncedKeys.where((key) => key.isNotEmpty).toList();
      if (filteredKeys.isNotEmpty) {
        await _store.removeByKeys(filteredKeys);
      }
    } catch (_) {
      // Manteniamo la coda locale intatta finché il WS non torna raggiungibile.
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

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/p2p/message') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final payload = await utf8.decoder.bind(request).join();
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final senderId = data['senderId']?.toString() ?? '';
      final receiverId = data['receiverId']?.toString() ?? '';
      final chatId = data['chatId']?.toString() ?? receiverId;
      final text = data['text']?.toString() ?? '';
      if (senderId.isEmpty || receiverId.isEmpty || text.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('{"success":false,"error":"Payload non valido"}');
      } else {
        await _store.rememberChatLink(
          ownerId: receiverId,
          chatId: chatId,
          participantId: senderId,
          title: 'Chat $senderId',
        );
        await _store.enqueueIncoming(
          ownerId: receiverId,
          senderId: senderId,
          receiverId: receiverId,
          text: text,
          chatId: chatId,
          transport: 'p2p',
        );
        request.response.statusCode = HttpStatus.ok;
        request.response.write('{"success":true}');
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('{"success":false}');
    } finally {
      request.response.headers.contentType = ContentType.json;
      await request.response.close();
    }
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
