import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class OfflineMessageStore {
  OfflineMessageStore._();

  static final OfflineMessageStore instance = OfflineMessageStore._();

  static const _messagesBoxName = 'offline_messages';
  static const _chatLinksBoxName = 'offline_chat_links';

  Box<dynamic>? _messagesBox;
  Box<dynamic>? _chatLinksBox;

  Future<void> init({String? basePath}) async {
    if (_messagesBox != null && _chatLinksBox != null) {
      return;
    }

    if (!Hive.isBoxOpen(_messagesBoxName) || !Hive.isBoxOpen(_chatLinksBoxName)) {
      if (basePath != null) {
        Hive.init(basePath);
      } else {
        try {
          final supportDir = await getApplicationSupportDirectory();
          Hive.init(path.join(supportDir.path, 'crimson_chat'));
        } catch (_) {
          final fallbackDir = await Directory.systemTemp.createTemp(
            'crimson_chat_offline_store_',
          );
          Hive.init(fallbackDir.path);
        }
      }
    }

    _messagesBox ??= await Hive.openBox<dynamic>(_messagesBoxName);
    _chatLinksBox ??= await Hive.openBox<dynamic>(_chatLinksBoxName);
  }

  Future<void> rememberChatLink({
    required String ownerId,
    required String chatId,
    required String participantId,
    String? title,
  }) async {
    final box = _requireChatLinksBox();
    await box.put(_chatLinkKey(ownerId, chatId), <String, dynamic>{
      'ownerId': ownerId,
      'chatId': chatId,
      'participantId': participantId,
      'title': title ?? 'Chat $participantId',
    });
  }

  Future<void> enqueueOutgoing({
    required String ownerId,
    required String senderId,
    required String receiverId,
    required String text,
    required String chatId,
    String transport = 'offline',
  }) async {
    final box = _requireMessagesBox();
    final timestamp = DateTime.now().toUtc();
    await box.put('${timestamp.microsecondsSinceEpoch}-$senderId-$receiverId', {
      'ownerId': ownerId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'chatId': chatId,
      'createdAt': timestamp.toIso8601String(),
      'direction': 'outgoing',
      'pendingSync': true,
      'transport': transport,
    });
  }

  Future<void> enqueueIncoming({
    required String ownerId,
    required String senderId,
    required String receiverId,
    required String text,
    required String chatId,
    String transport = 'p2p',
  }) async {
    final box = _requireMessagesBox();
    final timestamp = DateTime.now().toUtc();
    await box.put('${timestamp.microsecondsSinceEpoch}-$senderId-$receiverId', {
      'ownerId': ownerId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'chatId': chatId,
      'createdAt': timestamp.toIso8601String(),
      'direction': 'incoming',
      'pendingSync': false,
      'transport': transport,
    });
  }

  Future<List<Map<String, dynamic>>> listPendingOutgoing({
    required String ownerId,
  }) async {
    final box = _requireMessagesBox();
    return box.toMap().entries
        .map((entry) {
          final value = entry.value;
          if (value is! Map) {
            return null;
          }
          final item = Map<String, dynamic>.from(value);
          if (item['ownerId'] == ownerId &&
              item['direction'] == 'outgoing' &&
              item['pendingSync'] == true) {
            item['key'] = entry.key.toString();
            return item;
          }
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false)
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt']?.toString() ?? '');
        final bTime = DateTime.tryParse(b['createdAt']?.toString() ?? '');
        if (aTime == null || bTime == null) {
          return 0;
        }
        return aTime.compareTo(bTime);
      });
  }

  Future<void> removeByKeys(List<String> keys) async {
    final box = _requireMessagesBox();
    await box.deleteAll(keys);
  }

  Future<List<Map<String, dynamic>>> listConversation({
    required String ownerId,
    required String chatId,
  }) async {
    final box = _requireMessagesBox();
    return box.values
        .map((raw) => raw is Map ? Map<String, dynamic>.from(raw) : null)
        .whereType<Map<String, dynamic>>()
        .where((item) => item['ownerId'] == ownerId && item['chatId'] == chatId)
        .toList(growable: false)
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt']?.toString() ?? '');
        final bTime = DateTime.tryParse(b['createdAt']?.toString() ?? '');
        if (aTime == null || bTime == null) {
          return 0;
        }
        return aTime.compareTo(bTime);
      });
  }

  List<Map<String, dynamic>> listChatLinks({required String ownerId}) {
    final box = _requireChatLinksBox();
    return box.values
        .map((raw) => raw is Map ? Map<String, dynamic>.from(raw) : null)
        .whereType<Map<String, dynamic>>()
        .where((item) => item['ownerId'] == ownerId)
        .toList(growable: false);
  }

  String resolveParticipant({
    required String ownerId,
    required String chatId,
  }) {
    final box = _requireChatLinksBox();
    final raw = box.get(_chatLinkKey(ownerId, chatId));
    if (raw is! Map) {
      return chatId;
    }
    return raw['participantId']?.toString() ?? chatId;
  }

  Future<void> clearAll() async {
    await _messagesBox?.clear();
    await _chatLinksBox?.clear();
  }

  Future<void> dispose() async {
    if (_messagesBox != null) {
      await _messagesBox!.close();
      _messagesBox = null;
    }
    if (_chatLinksBox != null) {
      await _chatLinksBox!.close();
      _chatLinksBox = null;
    }
  }

  Future<void> resetForTests({required String basePath}) async {
    await dispose();
    await init(basePath: basePath);
    await clearAll();
  }

  Box<dynamic> _requireMessagesBox() {
    final box = _messagesBox;
    if (box == null) {
      throw StateError('OfflineMessageStore non inizializzato.');
    }
    return box;
  }

  Box<dynamic> _requireChatLinksBox() {
    final box = _chatLinksBox;
    if (box == null) {
      throw StateError('OfflineMessageStore non inizializzato.');
    }
    return box;
  }

  String _chatLinkKey(String ownerId, String chatId) => '$ownerId::$chatId';
}
