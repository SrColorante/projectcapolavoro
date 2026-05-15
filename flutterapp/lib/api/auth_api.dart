import '../models/user_profile.dart';

class AuthApi {
  static const String _defaultUserName = 'Nuovo utente';
  static final Map<String, String> _userIdsByEmail = <String, String>{};

  static Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final userId = _userIdsByEmail.putIfAbsent(
      email,
      UserProfile.generateTenDigitId,
    );
    return UserProfile(
      id: userId,
      name: 'Utente',
      nickname: 'Utente',
      email: email,
    );
  }

  static Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final normalizedName = name.trim().isEmpty ? _defaultUserName : name.trim();
    final userId = _userIdsByEmail.putIfAbsent(
      email,
      UserProfile.generateTenDigitId,
    );
    return UserProfile(
      id: userId,
      name: normalizedName,
      nickname: normalizedName,
      email: email,
    );
  }
}
