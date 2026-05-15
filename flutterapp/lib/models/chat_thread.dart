import 'dart:math';

class ChatMessage {
  const ChatMessage({required this.text, required this.senderId});

  final String text;
  final String senderId;

  bool isSentBy(String userId) => senderId == userId;
}

class ChatThread {
  ChatThread({
    required this.id,
    required this.title,
    required this.participantId,
    required this.messages,
    this.backgroundColorValue = 0xFFFFEEF1,
    this.bubbleColorValue = 0xFFDC143C,
  }) {
    if (!isValidTenDigitId(id)) {
      throw ArgumentError.value(id, 'id', 'Chat ID must be a 10-digit number');
    }
    if (!isValidTenDigitId(participantId)) {
      throw ArgumentError.value(
        participantId,
        'participantId',
        'Participant ID must be a 10-digit number',
      );
    }
  }

  final String id;
  final String title;
  final String participantId;
  final List<ChatMessage> messages;
  final int backgroundColorValue;
  final int bubbleColorValue;

  static final RegExp _tenDigitIdRegex = RegExp(r'^\d{10}$');

  static bool isValidTenDigitId(String value) => _tenDigitIdRegex.hasMatch(value);

  static String generateTenDigitId([Random? random]) {
    final rng = random ?? Random.secure();
    return (1000000000 + rng.nextInt(900000000)).toString();
  }
}
