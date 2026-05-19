import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/chat_thread.dart';
import '../services/app_preferences.dart';
import '../services/app_request_signer.dart';
import '../services/message_translation_service.dart';
import 'auth_api.dart';
import '../services/p2p_sync_service.dart';

class ChatApi {
  ChatApi({
    http.Client? client,
    String? baseUrl,
    MessageTranslator? translationService,
  })
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AuthApi.baseUrl,
        _translationService =
            translationService ?? MessageTranslationService.instance;

  static const _requestTimeout = Duration(seconds: 5);

  final http.Client _client;
  final String _baseUrl;
  final P2PSyncService _p2pSyncService = P2PSyncService.instance;
  final MessageTranslator _translationService;

  Future<List<ChatThread>> fetchChats({required String userId}) async {
    await _initializeOfflineFirst(userId);
    final uri = Uri.parse('$_baseUrl/chats').replace(
      queryParameters: {'user_id': userId},
    );
    try {
      final response = await _client
          .get(
            uri,
            headers: AppRequestSigner.buildSignedHeaders(
              method: 'GET',
              uri: uri,
              body: '',
            ),
          )
          .timeout(_requestTimeout);
      final payload = _decodePayload(response);
      final data = payload['data'] as List<dynamic>? ?? <dynamic>[];

      final chats = data.map((item) {
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

      for (final chat in chats) {
        await _p2pSyncService.rememberChat(
          ownerId: userId,
          chatId: chat.id,
          participantId: chat.participantId,
          title: chat.title,
        );
      }
      return chats;
    } catch (error) {
      if (!_isConnectivityError(error)) {
        rethrow;
      }
      return _p2pSyncService.buildLocalChats(userId: userId);
    }
  }

  Future<List<ChatMessage>> fetchMessages({
    required String userId,
    required String chatId,
  }) async {
    await _initializeOfflineFirst(userId);
    final uri = Uri.parse('$_baseUrl/chat').replace(
      queryParameters: {'user_id': userId, 'chat_id': chatId},
    );
    try {
      final response = await _client
          .get(
            uri,
            headers: AppRequestSigner.buildSignedHeaders(
              method: 'GET',
              uri: uri,
              body: '',
            ),
          )
          .timeout(_requestTimeout);
      final payload = _decodePayload(response);
      final data = payload['data'] as List<dynamic>? ?? <dynamic>[];
      final remoteMessages = data.map((item) {
        final message = Map<String, dynamic>.from(item as Map);
        return ChatMessage(
          text: message['textmessage']?.toString() ?? '',
          senderId: message['senderID']?.toString() ?? '',
          canonicalText: message['textmessage']?.toString() ?? '',
        );
      }).toList(growable: false);
      final mergedMessages = await _p2pSyncService.mergeWithLocalMessages(
        userId: userId,
        chatId: chatId,
        remoteMessages: remoteMessages,
      );
      return _localizeMessages(mergedMessages);
    } catch (error) {
      if (!_isConnectivityError(error)) {
        rethrow;
      }
      final localMessages = await _p2pSyncService.buildLocalMessages(
        userId: userId,
        chatId: chatId,
      );
      return _localizeMessages(localMessages);
    }
  }

  Future<String> createChat({
    required String userId,
    required String targetUserId,
  }) async {
    await _initializeOfflineFirst(userId);
    final uri = Uri.parse('$_baseUrl/chats').replace(
      queryParameters: {'user_id': userId},
    );
    try {
      final body = jsonEncode({'target_user_id': targetUserId});
      final response = await _client
          .post(
            uri,
            headers: AppRequestSigner.buildSignedHeaders(
              method: 'POST',
              uri: uri,
              body: body,
              headers: const {'Content-Type': 'application/json'},
            ),
            body: body,
          )
          .timeout(_requestTimeout);
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
      final normalizedChatId = chatId.toString();
      await _p2pSyncService.rememberChat(
        ownerId: userId,
        chatId: normalizedChatId,
        participantId: targetUserId,
      );
      return normalizedChatId;
    } catch (error) {
      if (!_isConnectivityError(error)) {
        rethrow;
      }
      final localChatId = ChatThread.generateTenDigitId();
      await _p2pSyncService.rememberChat(
        ownerId: userId,
        chatId: localChatId,
        participantId: targetUserId,
      );
      return localChatId;
    }
  }

  Future<void> sendMessage({
    required String userId,
    required String receiverId,
    required String text,
    String? chatId,
  }) async {
    await _initializeOfflineFirst(userId);
    final effectiveChatId = chatId ?? receiverId;
    await _p2pSyncService.rememberChat(
      ownerId: userId,
      chatId: effectiveChatId,
      participantId: receiverId,
    );
    final translatedText = await _translationService.translateOutgoing(
      text,
      sourceLanguageCode: AppPreferences.instance.preferredLanguageCode,
    );

    final uri = Uri.parse('$_baseUrl/chat').replace(
      queryParameters: {'user_id': userId},
    );
    try {
      final body = jsonEncode({
        'textmessage': translatedText,
        'reciverID': receiverId,
      });
      final response = await _client
          .post(
            uri,
            headers: AppRequestSigner.buildSignedHeaders(
              method: 'POST',
              uri: uri,
              body: body,
              headers: const {'Content-Type': 'application/json'},
            ),
            body: body,
          )
          .timeout(_requestTimeout);
      _decodePayload(response);
      await _p2pSyncService.syncPendingMessages();
    } catch (error) {
      if (!_isConnectivityError(error)) {
        rethrow;
      }
      final deliveredByP2P = await _p2pSyncService.sendP2P(
        senderId: userId,
        receiverId: receiverId,
        chatId: effectiveChatId,
        text: translatedText,
      );
      await _p2pSyncService.queueOutgoing(
        ownerId: userId,
        receiverId: receiverId,
        text: translatedText,
        chatId: effectiveChatId,
        p2pDelivered: deliveredByP2P,
      );
    }
  }

  Future<void> syncPendingMessages({required String userId}) async {
    await _initializeOfflineFirst(userId);
    await _p2pSyncService.syncPendingMessages();
  }

  Future<List<ChatMessage>> _localizeMessages(List<ChatMessage> messages) async {
    final preferredLanguageCode = AppPreferences.instance.preferredLanguageCode;
    final localizedMessages = <ChatMessage>[];
    for (final message in messages) {
      final localizedText = await _translationService.translateIncoming(
        message.canonicalText,
        targetLanguageCode: preferredLanguageCode,
      );
      localizedMessages.add(
        ChatMessage(
          text: localizedText,
          senderId: message.senderId,
          canonicalText: message.canonicalText,
        ),
      );
    }
    return localizedMessages;
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

  Future<void> _initializeOfflineFirst(String userId) async {
    await _p2pSyncService.initialize(
      userId: userId,
      baseUrl: _baseUrl,
      client: _client,
    );
  }

  bool _isConnectivityError(Object error) =>
      error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException;
}
