import 'dart:math';

class UserProfile {
  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    String? nickname,
  }) : nickname = (nickname == null || nickname.trim().isEmpty)
            ? name
            : nickname.trim() {
    if (!isValidTenDigitId(id)) {
      throw ArgumentError.value(id, 'id', 'User ID must be a 10-digit number');
    }
  }

  final String id;
  final String name;
  final String email;
  final String nickname;

  static final RegExp _tenDigitIdRegex = RegExp(r'^\d{10}$');

  static bool isValidTenDigitId(String value) => _tenDigitIdRegex.hasMatch(value);

  static String generateTenDigitId([Random? random]) {
    final rng = random ?? Random.secure();
    return (1000000000 + rng.nextInt(900000000)).toString();
  }
}
