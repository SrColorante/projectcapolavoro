import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutterapp/api/chat_api.dart';
import 'package:flutterapp/services/offline_message_store.dart';
import 'package:flutterapp/services/p2p_sync_service.dart';

void main() {
  group('ChatApi offline-first', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('offline_first_test_');
      await OfflineMessageStore.instance.resetForTests(basePath: tempDir.path);
    });

    tearDown(() async {
      await P2PSyncService.instance.dispose();
      await OfflineMessageStore.instance.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('queues outgoing message locally when WS is unreachable', () async {
      final offlineClient = MockClient((request) async {
        throw const SocketException('No network');
      });
      final api = ChatApi(
        client: offlineClient,
        baseUrl: 'https://example.test/webService',
      );

      await api.sendMessage(
        userId: '1234567890',
        receiverId: '1234567891',
        text: 'Ciao offline',
        chatId: '2345678901',
      );

      final pending = await OfflineMessageStore.instance.listPendingOutgoing(
        ownerId: '1234567890',
      );
      expect(pending.length, 1);
      expect(pending.first['text'], 'Ciao offline');
    });

    test('syncPendingMessages flushes local queue when WS is online again', () async {
      final offlineClient = MockClient((request) async {
        throw const SocketException('No network');
      });
      final offlineApi = ChatApi(
        client: offlineClient,
        baseUrl: 'https://example.test/webService',
      );

      await offlineApi.sendMessage(
        userId: '1234567890',
        receiverId: '1234567891',
        text: 'Messaggio in coda',
        chatId: '2345678901',
      );

      final onlineClient = MockClient((request) async {
        return http.Response('{"success":true}', 200);
      });
      final onlineApi = ChatApi(
        client: onlineClient,
        baseUrl: 'https://example.test/webService',
      );

      await onlineApi.syncPendingMessages(userId: '1234567890');

      final pending = await OfflineMessageStore.instance.listPendingOutgoing(
        ownerId: '1234567890',
      );
      expect(pending, isEmpty);
    });
  });
}
