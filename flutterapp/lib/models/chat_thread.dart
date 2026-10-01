import 'dart:math';

import 'user_profile.dart';

class ChatMessage {
  const ChatMessage({
    this.id,
    required this.text,
    required this.senderId,
    String? canonicalText,
    this.fileAttachmentId,
    this.fileName,
    this.mimeType,
    this.sourceUrl,
    this.previewType,
    this.previewPayload,
    this.status = 'sent',
    this.timestamp,
  }) : canonicalText = canonicalText ?? text;

  final String? id;
  final String text;
  final String senderId;
  final String canonicalText;
  final String status; // 'sent', 'delivered', 'read'
  final DateTime? timestamp;

  // File attachment properties
  final String? fileAttachmentId;
  final String? fileName;
  final String? mimeType;
  final String? sourceUrl;
  final String? previewType;
  final Map<String, dynamic>? previewPayload;

  bool isSentBy(String userId) => senderId == userId;
  bool get hasAttachment => fileAttachmentId != null;
}

class ChatThread {
  ChatThread({
    required this.id,
    required this.title,
    required this.participantId,
    required this.messages,
    this.isGroup = false,
    this.createdBy,
    this.avatarUrl,
    this.members = const [],
    this.backgroundColorValue = 0xFFFFEEF1,
    this.bubbleColorValue = 0xFFDC143C,
    this.backgroundImagePath,
    this.useDefaultTheme = true,
  }) {
    if (!isValidTenDigitId(id)) {
      throw ArgumentError.value(id, 'id', 'Chat ID must be a 10-digit number');
    }
    // Only require valid phone ID participant ID for 1-to-1 chats, in group chats participantId can be an empty placeholder or creator
    if (!isGroup && !UserProfile.isValidPhoneId(participantId)) {
      throw ArgumentError.value(
        participantId,
        'participantId',
        'Participant ID must be a valid phone number (10 digits) for 1-to-1 chats',
      );
    }
  }

  final String id;
  final String title;
  final String participantId;
  final List<ChatMessage> messages;
  final bool isGroup;
  final String? createdBy;
  final String? avatarUrl;
  final List<dynamic> members;
  
  // Customization per-chat
  final int backgroundColorValue;
  final int bubbleColorValue;
  final String? backgroundImagePath;
  final bool useDefaultTheme;

  static final RegExp _tenDigitIdRegex = RegExp(r'^\d{10}$');

  static bool isValidTenDigitId(String value) => _tenDigitIdRegex.hasMatch(value);

  static String generateTenDigitId([Random? random]) {
    final rng = random ?? Random.secure();
    return (1000000000 + rng.nextInt(900000000)).toString();
  }
}
