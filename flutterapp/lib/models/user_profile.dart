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
    if (!isValidPhoneId(id)) {
      throw ArgumentError.value(id, 'id', 'User ID (phone) must be exactly 10 digits');
    }
    if (profileAudioDurationSeconds != null &&
        (profileAudioDurationSeconds! < 0 || profileAudioDurationSeconds! > 5)) {
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'nickname': nickname,
        'isGuest': isGuest,
        'preferredLanguageCode': preferredLanguageCode,
        'profileBio': profileBio,
        'profilePhotoUrl': profilePhotoUrl,
        'profileAudioUrl': profileAudioUrl,
        'profileAudioDurationSeconds': profileAudioDurationSeconds,
        'e2eePublicKey': e2eePublicKey,
        'twoFactorEnabled': twoFactorEnabled,
        'twoFactorChannel': twoFactorChannel,
        'twoFactorDestination': twoFactorDestination,
        'isPecCertified': isPecCertified,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String? ?? '',
        nickname: json['nickname'] as String?,
        isGuest: json['isGuest'] as bool? ?? false,
        preferredLanguageCode: json['preferredLanguageCode'] as String? ?? 'en',
        profileBio: json['profileBio'] as String?,
        profilePhotoUrl: json['profilePhotoUrl'] as String?,
        profileAudioUrl: json['profileAudioUrl'] as String?,
        profileAudioDurationSeconds: json['profileAudioDurationSeconds'] is num
            ? (json['profileAudioDurationSeconds'] as num).toDouble()
            : null,
        e2eePublicKey: json['e2eePublicKey'] as String?,
        twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
        twoFactorChannel: json['twoFactorChannel'] as String?,
        twoFactorDestination: json['twoFactorDestination'] as String?,
        isPecCertified: json['isPecCertified'] as bool? ?? false,
      );

  static final RegExp _tenDigitIdRegex = RegExp(r'^\d{10}$');
  static final RegExp _phoneIdRegex = RegExp(r'^\d{10}$');

  static bool isValidTenDigitId(String value) => _tenDigitIdRegex.hasMatch(value);
  static bool isValidPhoneId(String value) => _phoneIdRegex.hasMatch(value);

  static String generateTenDigitId([Random? random]) {
    final rng = random ?? Random.secure();
    return (1000000000 + rng.nextInt(900000000)).toString();
  }
}
