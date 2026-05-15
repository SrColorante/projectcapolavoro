import '../models/user_profile.dart';

class AuthApi {
  static const String _defaultUserName = 'Nuovo utente';

  static Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return UserProfile(name: 'Utente', email: email);
  }

  static Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return UserProfile(
      name: name.isEmpty ? _defaultUserName : name,
      email: email,
    );
  }
}
