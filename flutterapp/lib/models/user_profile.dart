import 'dart:math';

class UserProfile {
  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    String? nickname,
    this.isGuest = false,
    this.preferredLanguageCode = 'en',
    this.profileBio,
    this.profilePhotoUrl,
    this.profileAudioUrl,
    this.profileAudioDurationSeconds,
    this.e2eePublicKey,
    this.twoFactorEnabled = false,
    this.twoFactorChannel,
    this.twoFactorDestination,
    this.isPecCertified = false,
  }) : nickname = (nickname == null || nickname.trim().isEmpty)
            ? name
            : nickname.trim() {
    if (!isValidTenDigitId(id)) {
      throw ArgumentError.value(id, 'id', 'User ID must be a 10-digit number');
    }
    if (profileAudioDurationSeconds != null &&
        (profileAudioDurationSeconds < 0 || profileAudioDurationSeconds > 5)) {
      throw ArgumentError.value(
        profileAudioDurationSeconds,
        'profileAudioDurationSeconds',
        'Audio profile duration must be between 0 and 5 seconds',
      );
    }
  }

  final String id;
  final String name;
  final String email;
  final String nickname;
  final bool isGuest;
  final String preferredLanguageCode;
  final String? profileBio;
  final String? profilePhotoUrl;
  final String? profileAudioUrl;
  final double? profileAudioDurationSeconds;
  final String? e2eePublicKey;
  final bool twoFactorEnabled;
  final String? twoFactorChannel;
  final String? twoFactorDestination;
  final bool isPecCertified;

  static final RegExp _tenDigitIdRegex = RegExp(r'^\d{10}$');

  static bool isValidTenDigitId(String value) => _tenDigitIdRegex.hasMatch(value);

  static String generateTenDigitId([Random? random]) {
    final rng = random ?? Random.secure();
    return (1000000000 + rng.nextInt(900000000)).toString();
  }
}
