import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_thread.dart';
import 'auth_api.dart';

class ChatApi {
  ChatApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AuthApi.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<List<ChatThread>> fetchChats({required String userId}) async {
    final uri = Uri.parse('$_baseUrl/chats').replace(
      queryParameters: {'user_id': userId},
    );
    final response = await _client.get(uri);
    final payload = _decodePayload(response);
    final data = payload['data'] as List<dynamic>? ?? <dynamic>[];

    return data.map((item) {
      final chat = Map<String, dynamic>.from(item as Map);
      final chatId = chat['IDchat'].toString();
      final userOne = chat['utente1'].toString();
      final userTwo = chat['utente2'].toString();
      final participantId = userOne == userId ? userTwo : userOne;

      return ChatThread(
        id: chatId,
        title: 'Chat $participantId',
        participantId: participantId,
        messages: <ChatMessage>[],
      );
    }).toList(growable: false);
  }

  Future<List<ChatMessage>> fetchMessages({
    required String userId,
    required String chatId,
  }) async {
    final uri = Uri.parse('$_baseUrl/chat').replace(
      queryParameters: {'user_id': userId, 'chat_id': chatId},
    );
    final response = await _client.get(uri);
    final payload = _decodePayload(response);
    final data = payload['data'] as List<dynamic>? ?? <dynamic>[];

    return data.map((item) {
      final message = Map<String, dynamic>.from(item as Map);
      return ChatMessage(
        text: message['textmessage']?.toString() ?? '',
        senderId: message['senderID']?.toString() ?? '',
      );
    }).toList(growable: false);
  }

  Future<String> createChat({
    required String userId,
    required String targetUserId,
  }) async {
    final uri = Uri.parse('$_baseUrl/chats').replace(
      queryParameters: {'user_id': userId},
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'target_user_id': targetUserId}),
    );
    if (response.statusCode >= 400) {
      throw Exception('Errore server (${response.statusCode}).');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw Exception('Risposta non valida dal server.');
    }
    final chatId = payload['IDchat'] ?? payload['data']?['IDchat'];
    if (chatId == null) {
      throw Exception(payload['error'] ?? 'Risposta chat non valida.');
    }
    return chatId.toString();
  }

  Future<void> sendMessage({
    required String userId,
    required String receiverId,
    required String text,
  }) async {
    final uri = Uri.parse('$_baseUrl/chat').replace(
      queryParameters: {'user_id': userId},
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'textmessage': text, 'reciverID': receiverId}),
    );
    _decodePayload(response);
  }

  Map<String, dynamic> _decodePayload(http.Response response) {
    if (response.statusCode >= 400) {
      throw Exception('Errore server (${response.statusCode}).');
    }
    final payload = jsonDecode(response.body);
    if (payload is Map<String, dynamic>) {
      if (payload['success'] == false) {
        throw Exception(payload['message'] ?? payload['error'] ?? 'Errore API.');
      }
      return payload;
    }
    throw Exception('Risposta non valida dal server.');
  }
}
