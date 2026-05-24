import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_thread.dart';

class TypingStatus {
  final String userId;
  final String username;
  final String status; // 'typing'|'recording'|'idle'
  TypingStatus(this.userId, this.username, this.status);
}

class ChatService extends ChangeNotifier {
  final String wsUrl;
  final String userId;
  final String username;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _typingTimer;
  bool _isTyping = false;

  String? _currentRoomId;
  final List<ChatMessage> _messages = [];
  final Map<String, TypingStatus> _typingUsers = {};
  bool get connected => _channel != null;

  ChatService({required this.wsUrl, required this.userId, required this.username});

  String? get currentRoomId => _currentRoomId;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  Map<String, TypingStatus> get typingUsers => Map.unmodifiable(_typingUsers);

  void connectToRoom(String roomId) {
    _currentRoomId = roomId;
    _connect();
  }

  void _connect() {
    if (_channel != null) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(_onRawMessage, onDone: _onDone, onError: (e) => _onError(e));
      // send join once connected
      _send({'type': 'join', 'userId': userId, 'payload': {'roomId': _currentRoomId, 'username': username}});
      notifyListeners();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void disconnect() {
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    notifyListeners();
  }

  void dispose() {
    _typingTimer?.cancel();
    _reconnectTimer?.cancel();
    disconnect();
    super.dispose();
  }

  void _onRawMessage(dynamic raw) {
    try {
      final Map<String, dynamic> data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final fromUser = data['userId']?.toString();
      final payload = data['payload'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'new_message':
          final msg = _parseMessage(payload);
          final exists = _messages.any((m) => m.id != null && m.id == msg.id);
          if (!exists) {
            _messages.add(msg);
            notifyListeners();
          }
          break;
        case 'typing_start':
        case 'typing_stop':
        case 'recording_start':
        case 'recording_stop':
          final username = payload['username']?.toString() ?? '';
          final status = (type == 'typing_start') ? 'typing' : (type == 'recording_start' ? 'recording' : 'idle');
          if (status == 'idle') {
            _typingUsers.remove(fromUser);
          } else {
            _typingUsers[fromUser ?? ''] = TypingStatus(fromUser ?? '', username, status);
          }
          notifyListeners();
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  ChatMessage _parseMessage(Map<String, dynamic> payload) {
    final id = payload['id']?.toString() ?? payload['tempId']?.toString();
    final text = payload['text']?.toString() ?? '';
    final senderId = payload['senderId']?.toString() ?? payload['userId']?.toString() ?? '';
    DateTime? timestamp;
    if (payload['createdAt'] != null) {
      timestamp = DateTime.tryParse(payload['createdAt'].toString())?.toLocal();
    }
    return ChatMessage(
      id: id,
      text: text,
      senderId: senderId,
      canonicalText: text,
      fileAttachmentId: payload['fileAttachmentId']?.toString(),
      fileName: payload['fileName']?.toString(),
      mimeType: payload['mimeType']?.toString(),
      sourceUrl: payload['sourceUrl']?.toString(),
      previewType: payload['previewType']?.toString(),
      previewPayload: payload['previewPayload'] is Map ? Map<String, dynamic>.from(payload['previewPayload']) : null,
      status: payload['status']?.toString() ?? 'sent',
      timestamp: timestamp,
    );
  }

  void _onDone() {
    _channel = null;
    _scheduleReconnect();
    notifyListeners();
  }

  void _onError(error) {
    _channel = null;
    _scheduleReconnect();
    notifyListeners();
  }

  void onKeystroke() {
    if (!_isTyping) {
      _isTyping = true;
      _send({'type': 'typing_start', 'userId': userId, 'payload': {}});
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1500), () => _stopTyping());
  }

  void _stopTyping() {
    if (!_isTyping) return;
    _isTyping = false;
    _typingTimer?.cancel();
    _send({'type': 'typing_stop', 'userId': userId, 'payload': {}});
  }

  Future<void> sendMessage(String text, {String? tempId}) async {
    _stopTyping();
    final payload = {'tempId': tempId ?? UniqueKey().toString(), 'text': text, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'senderId': userId};
    _send({'type': 'new_message', 'userId': userId, 'payload': payload});
    final optimistic = ChatMessage(id: payload['tempId'], text: text, senderId: userId, canonicalText: text, status: 'sending', timestamp: DateTime.now());
    _messages.add(optimistic);
    notifyListeners();
    _maybeAutoScroll();
  }

  void startRecording() {
    _send({'type': 'recording_start', 'userId': userId, 'payload': {}});
  }

  void stopRecording() {
    _send({'type': 'recording_stop', 'userId': userId, 'payload': {}});
  }

  void _send(Map<String, dynamic> obj) {
    final str = jsonEncode(obj);
    try {
      _channel?.sink.add(str);
    } catch (_) {
      // ignore: no-op fallback
    }
  }

  void _maybeAutoScroll() {
    // UI-driven: home_screen will check scroll controller when notified
  }
}
