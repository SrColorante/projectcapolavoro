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
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AuthApi.baseUrl,
        _translationService =
            translationService ?? MessageTranslationService.instance;

  static const _requestTimeout = Duration(seconds: 10);

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
        final isGroup = int.tryParse(chat['is_group']?.toString() ?? '0') == 1;

        final lastMsgText = chat['last_message']?.toString();
        final lastMsgSender = chat['last_message_sender']?.toString();
        final chatMessages = <ChatMessage>[];
        if (lastMsgText != null && lastMsgSender != null) {
          chatMessages.add(ChatMessage(
            text: lastMsgText,
            senderId: lastMsgSender,
          ));
        }

        if (isGroup) {
          final name = chat['name']?.toString() ?? 'Gruppo $chatId';
          final createdBy = chat['created_by']?.toString();
          final avatarUrl = chat['avatar_url']?.toString();
          final members = chat['members'] as List<dynamic>? ?? [];
          
          return ChatThread(
            id: chatId,
            title: name,
            participantId: createdBy ?? userId,
            isGroup: true,
            createdBy: createdBy,
            avatarUrl: avatarUrl,
            members: members,
            messages: chatMessages,
          );
        } else {
          final userOne = chat['utente1']?.toString() ?? '';
          final userTwo = chat['utente2']?.toString() ?? '';
          final participantId = userOne == userId ? userTwo : userOne;
          final isSelf = participantId == userId;
          
          final otherNickname = chat['other_user_nickname']?.toString();
          final otherName = chat['other_user_name']?.toString();
          final displayName = (otherNickname != null && otherNickname.isNotEmpty)
              ? otherNickname
              : ((otherName != null && otherName.isNotEmpty) ? otherName : 'Chat $participantId');
          
          return ChatThread(
            id: chatId,
            title: isSelf ? 'Note personali (Tu)' : displayName,
            participantId: participantId,
            isGroup: false,
            messages: chatMessages,
          );
        }
      }).toList(growable: false);

      for (final chat in chats) {
        if (!chat.isGroup) {
          await _p2pSyncService.rememberChat(
            ownerId: userId,
            chatId: chat.id,
            participantId: chat.participantId,
            title: chat.title,
          );
        }
      }
      return chats;
    } catch (error) {
      if (!_isConnectivityError(error)) {
        rethrow;
      }
      return _p2pSyncService.buildLocalChats(userId: userId);
    }
  }

  Future<MessagesFetchResult> fetchMessages({
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
      final typingData = payload['typing'] as List<dynamic>? ?? <dynamic>[];
      
      final remoteMessages = data.map((item) {
        final message = Map<String, dynamic>.from(item as Map);
        
        final attachmentId = message['file_attachment_id']?.toString();
        final fileName = message['file_name']?.toString();
        final mimeType = message['mime_type']?.toString();
        final sourceUrl = message['source_url']?.toString();
        final previewType = message['preview_type']?.toString();
        final msgId = message['id']?.toString();
        final msgStatus = message['status']?.toString() ?? 'sent';
        final rawTime = message['timenow']?.toString();
        DateTime? timestamp;
        if (rawTime != null) {
          timestamp = DateTime.tryParse(rawTime)?.toLocal();
        }
        
        Map<String, dynamic>? previewPayload;
        if (message['preview_payload'] != null) {
          if (message['preview_payload'] is Map) {
            previewPayload = Map<String, dynamic>.from(message['preview_payload'] as Map);
          } else if (message['preview_payload'] is String) {
            try {
              previewPayload = Map<String, dynamic>.from(jsonDecode(message['preview_payload'] as String) as Map);
            } catch (_) {}
          }
        }

        return ChatMessage(
          id: msgId,
          text: message['textmessage']?.toString() ?? '',
          senderId: message['senderID']?.toString() ?? '',
          canonicalText: message['textmessage']?.toString() ?? '',
          fileAttachmentId: attachmentId,
          fileName: fileName,
          mimeType: mimeType,
          sourceUrl: sourceUrl,
          previewType: previewType,
          previewPayload: previewPayload,
          status: msgStatus,
          timestamp: timestamp,
        );
      }).toList(growable: false);
      
      final mergedMessages = await _p2pSyncService.mergeWithLocalMessages(
        userId: userId,
        chatId: chatId,
        remoteMessages: remoteMessages,
      );
      final localized = await _localizeMessages(mergedMessages);
      return MessagesFetchResult(messages: localized, typingUsers: typingData);
    } catch (error) {
      if (!_isConnectivityError(error)) {
        rethrow;
      }
      final localMessages = await _p2pSyncService.buildLocalMessages(
        userId: userId,
        chatId: chatId,
      );
      final localized = await _localizeMessages(localMessages);
      return MessagesFetchResult(messages: localized, typingUsers: const []);
    }
  }

  Future<void> updateTypingStatus({
    required String userId,
    required String chatId,
    required String status,
  }) async {
    await _initializeOfflineFirst(userId);
    final uri = Uri.parse('$_baseUrl/chat').replace(
      queryParameters: {'user_id': userId},
    );
    try {
      final body = jsonEncode({
        'chat_id': chatId,
        'typing_status': status,
      });
      await _client.post(
        uri,
        headers: AppRequestSigner.buildSignedHeaders(
          method: 'POST',
          uri: uri,
          body: body,
          headers: const {'Content-Type': 'application/json'},
        ),
        body: body,
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Ignora silenziosamente
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

  Future<String> createGroup({
    required String userId,
    required String name,
    required List<String> memberIds,
  }) async {
    await _initializeOfflineFirst(userId);
    final uri = Uri.parse('$_baseUrl/chats').replace(
      queryParameters: {'user_id': userId},
    );
    final body = jsonEncode({
      'is_group': true,
      'name': name,
      'member_ids': memberIds,
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
    if (response.statusCode >= 400) {
      throw Exception('Errore server (${response.statusCode}).');
    }
    final payload = jsonDecode(response.body);
    if (payload['success'] == false) {
      throw Exception(payload['message'] ?? payload['error'] ?? 'Impossibile creare il gruppo');
    }
    return (payload['IDchat'] ?? payload['data']?['IDchat']).toString();
  }

  Future<void> sendMessage({
    required String userId,
    required String receiverId,
    required String text,
    String? chatId,
    String? fileAttachmentId,
  }) async {
    await _initializeOfflineFirst(userId);
    final effectiveChatId = chatId ?? receiverId;
    if (chatId == null || !chatId.startsWith('group_')) {
      await _p2pSyncService.rememberChat(
        ownerId: userId,
        chatId: effectiveChatId,
        participantId: receiverId,
      );
    }
    final translatedText = await _translationService.translateOutgoing(
      text,
      sourceLanguageCode: AppPreferences.instance.preferredLanguageCode,
    );

    final uri = Uri.parse('$_baseUrl/chat').replace(
      queryParameters: {'user_id': userId},
    );
    try {
      final Map<String, dynamic> requestBody = {
        'textmessage': translatedText,
      };
      if (chatId != null) {
        requestBody['chat_id'] = chatId;
      } else {
        requestBody['reciverID'] = receiverId;
      }
      if (fileAttachmentId != null) {
        requestBody['file_attachment_id'] = int.tryParse(fileAttachmentId);
      }
      final body = jsonEncode(requestBody);
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
      // For p2p / offline, standard 1-to-1 flows continue, file uploading is only online
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

  Future<Map<String, dynamic>> uploadFile({
    required String userId,
    required String filePath,
    String? adminPassword,
    bool overrideLimit = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File locale non trovato.');
    }

    final uri = Uri.parse('$_baseUrl/files').replace(
      queryParameters: {'user_id': userId},
    );

    try {
      final request = http.MultipartRequest('POST', uri);

      // Multipart upload uses empty body string for signature because body is not read from php://input
      final signedHeaders = AppRequestSigner.buildSignedHeaders(
        method: 'POST',
        uri: uri,
        body: '',
      );

      request.headers.addAll(signedHeaders);

      if (adminPassword != null && adminPassword.isNotEmpty) {
        request.fields['admin_password'] = adminPassword;
      }
      if (overrideLimit) {
        request.fields['override_limit'] = 'true';
      }

      final stream = http.ByteStream(file.openRead());
      final length = await file.length();

      final filename = file.path.split('/').last.split('\\').last;
      final multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: filename,
      );
      request.files.add(multipartFile);

      final responseStream = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(responseStream);

      if (response.statusCode >= 400) {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Errore caricamento (${response.statusCode})');
      }

      final payload = jsonDecode(response.body);
      if (payload['success'] == false) {
        throw Exception(payload['message'] ?? payload['error'] ?? 'Errore caricamento.');
      }

      return Map<String, dynamic>.from(payload['data'] as Map);
    } catch (error) {
      if (_isConnectivityError(error)) {
        throw Exception('Connessione assente o instabile durante l\'upload del file.');
      }
      rethrow;
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
          id: message.id,
          text: localizedText,
          senderId: message.senderId,
          canonicalText: message.canonicalText,
          fileAttachmentId: message.fileAttachmentId,
          fileName: message.fileName,
          mimeType: message.mimeType,
          sourceUrl: message.sourceUrl,
          previewType: message.previewType,
          previewPayload: message.previewPayload,
          status: message.status,
          timestamp: message.timestamp,
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

class MessagesFetchResult {
  final List<ChatMessage> messages;
  final List<dynamic> typingUsers;
  MessagesFetchResult({required this.messages, required this.typingUsers});
}
