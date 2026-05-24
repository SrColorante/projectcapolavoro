import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutterapp/api/chat_api.dart';
import 'package:flutterapp/services/app_preferences.dart';
import 'package:flutterapp/services/message_translation_service.dart';
import 'package:flutterapp/services/offline_message_store.dart';
import 'package:flutterapp/services/p2p_sync_service.dart';

class FakeMessageTranslator implements MessageTranslator {
  @override
  Future<String> translateIncoming(
    String text, {
    required String targetLanguageCode,
  }) async {
    if (text == 'Hello world' && targetLanguageCode == 'it') {
      return 'Ciao mondo';
    }
    return text;
  }

  @override
  Future<String> translateOutgoing(
    String text, {
    required String sourceLanguageCode,
  }) async {
    if (text == 'Ciao mondo' && sourceLanguageCode == 'it') {
      return 'Hello world';
    }
    return text;
  }
}

void main() {
  group('ChatApi translation flow', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chat_translation_test_');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppPreferences.instance.resetForTests();
      await AppPreferences.instance.saveSettings(
        themeColorValue: AppPreferences.defaultThemeColorValue,
        preferredLanguageCode: 'it',
      );
      await OfflineMessageStore.instance.resetForTests(basePath: tempDir.path);
    });

    tearDown(() async {
      await P2PSyncService.instance.dispose();
      await OfflineMessageStore.instance.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('translates outgoing messages to English before sending', () async {
      late Map<String, dynamic> sentPayload;
      final api = ChatApi(
        client: MockClient((request) async {
          sentPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"success":true}', 200);
        }),
        baseUrl: 'https://example.test/webService/index.php',
        translationService: FakeMessageTranslator(),
      );

      await api.sendMessage(
        userId: '1234567890',
        receiverId: '1234567891',
        text: 'Ciao mondo',
        chatId: '2345678901',
      );

      expect(sentPayload['textmessage'], 'Hello world');
    });

    test('translates incoming English messages to the preferred language', () async {
      final api = ChatApi(
        client: MockClient((request) async {
          return http.Response(
            '{"success":true,"data":[{"textmessage":"Hello world","senderID":"1234567891"}]}',
            200,
          );
        }),
        baseUrl: 'https://example.test/webService/index.php',
        translationService: FakeMessageTranslator(),
      );

      final messages = await api.fetchMessages(
        userId: '1234567890',
        chatId: '2345678901',
      );

      expect(messages.messages.single.text, 'Ciao mondo');
      expect(messages.messages.single.canonicalText, 'Hello world');
    });
  });
}
