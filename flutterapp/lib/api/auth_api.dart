import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import '../services/app_request_signer.dart';

class AuthApi { 
  static const String _defaultUserName = 'Nuovo utente';
  static const String _defaultBaseUrl =
      'https://1cdc-93-71-139-206.ngrok-free.app/index.php';
  static http.Client _client = http.Client();
  static String baseUrl = _defaultBaseUrl;

  static void configure({http.Client? client, String? baseUrl}) {
    if (client != null) {
      _client = client;
    }
    if (baseUrl != null) {
      AuthApi.baseUrl = baseUrl;
    }
  }

  static void reset() {
    _client = http.Client();
    baseUrl = _defaultBaseUrl;
  }

  static Future<UserProfile> login({
    required String phone,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl?route=auth');
    final body = jsonEncode({
      'action': 'login',
      'phone': phone,
      'password': password,
    });
    final response = await _client.post(
      uri,
      headers: AppRequestSigner.buildSignedHeaders(
        method: 'POST',
        uri: uri,
        body: body,
        headers: const {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'User-Agent': 'QuiceApp/1.0.0',
        },
      ),
      body: body,
    );

    return _parseProfile(response, fallbackName: 'Utente');
  }

  static Future<UserProfile> register({
    required String name,
    required String phone,
    String? email,
    required String password,
    String preferredLanguageCode = 'en',
    String? profileBio,
    String? profilePhotoUrl,
    String? profileAudioUrl,
    double? profileAudioDurationSeconds,
    String? e2eePublicKey,
    bool twoFactorEnabled = false,
    String? twoFactorChannel,
    String? twoFactorDestination,
  }) async {
    final normalizedName = name.trim().isEmpty ? _defaultUserName : name.trim();
    final uri = Uri.parse('$baseUrl?route=auth');
    final body = jsonEncode({
      'action': 'register',
      'name': normalizedName,
      'phone': phone,
      'email': email ?? '',
      'password': password,
      'preferred_language': preferredLanguageCode,
      'profile_bio': profileBio,
      'profile_photo_url': profilePhotoUrl,
      'profile_audio_url': profileAudioUrl,
      'profile_audio_duration_seconds': profileAudioDurationSeconds,
      'e2ee_public_key': e2eePublicKey,
      'two_factor_enabled': twoFactorEnabled,
      'two_factor_channel': twoFactorChannel,
      'two_factor_destination': twoFactorDestination,
    });
    final response = await _client.post(
      uri,
      headers: AppRequestSigner.buildSignedHeaders(
        method: 'POST',
        uri: uri,
        body: body,
        headers: const {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'User-Agent': 'QuiceApp/1.0.0',
        },
      ),
      body: body,
    );

    return _parseProfile(response, fallbackName: normalizedName);
  }

  static Future<UserProfile> guestLogin({
    String name = 'Ospite',
    String preferredLanguageCode = 'en',
    String? e2eePublicKey,
  }) async {
    final uri = Uri.parse('$baseUrl?route=auth');
    final body = jsonEncode({
      'action': 'guest_login',
      'name': name,
      'preferred_language': preferredLanguageCode,
      'e2ee_public_key': e2eePublicKey,
    });
    final response = await _client.post(
      uri,
      headers: AppRequestSigner.buildSignedHeaders(
        method: 'POST',
        uri: uri,
        body: body,
        headers: const {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'User-Agent': 'QuiceApp/1.0.0',
        },
      ),
      body: body,
    );

    return _parseProfile(response, fallbackName: name.trim().isEmpty ? 'Ospite' : name.trim());
  }

  static UserProfile _parseProfile(
    http.Response response, {
    required String fallbackName,
  }) {
    print('--- HTTP RESPONSE DEBUG ---');
    print('Status Code: ${response.statusCode}');
    print('Headers: ${response.headers}');
    print('Body: ${response.body}');
    print('---------------------------');

    if (response.statusCode >= 400) {
      throw Exception('Errore server (${response.statusCode}):\n${response.body}');
    }

    dynamic payload;
    try {
      payload = jsonDecode(response.body);
    } catch (e) {
      print('====== ERRORE DAL SERVER PHP ======');
      print('Status: ${response.statusCode}');
      print('Headers: ${response.headers}');
      print('Body: ${response.body}');
      print('===================================');
      throw Exception('Il server PHP ha restituito un errore HTML. Controlla la console per i dettagli.');
    }

    if (payload is! Map<String, dynamic>) {
      throw Exception('Risposta non valida dal server.');
    }

    if (payload['success'] != true) {
      throw Exception(payload['error'] ?? 'Errore autenticazione.');
    }

    final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final id = data['id']?.toString() ?? UserProfile.generateTenDigitId();
    final name = data['name']?.toString().trim();
    final nickname = data['nickname']?.toString().trim();
    final email = data['email']?.toString() ?? '';
    final profileBio = data['profile_bio']?.toString().trim();
    final profilePhotoUrl = data['profile_photo_url']?.toString().trim();
    final profileAudioUrl = data['profile_audio_url']?.toString().trim();
    final profileAudioDurationRaw = data['profile_audio_duration_seconds'];
    final profileAudioDuration = profileAudioDurationRaw is num
        ? profileAudioDurationRaw.toDouble()
        : double.tryParse(profileAudioDurationRaw?.toString() ?? '');

    return UserProfile(
      id: id,
      name: (name == null || name.isEmpty) ? fallbackName : name,
      nickname: (nickname == null || nickname.isEmpty)
          ? fallbackName
          : nickname,
      email: email,
      isGuest: data['is_guest'] == true,
      preferredLanguageCode:
          data['preferred_language']?.toString() ?? 'en',
      profileBio: (profileBio == null || profileBio.isEmpty) ? null : profileBio,
      profilePhotoUrl: (profilePhotoUrl == null || profilePhotoUrl.isEmpty)
          ? null
          : profilePhotoUrl,
      profileAudioUrl: (profileAudioUrl == null || profileAudioUrl.isEmpty)
          ? null
          : profileAudioUrl,
      profileAudioDurationSeconds: profileAudioDuration,
      e2eePublicKey: data['e2ee_public_key']?.toString(),
      twoFactorEnabled: data['two_factor_enabled'] == true,
      twoFactorChannel: data['two_factor_channel']?.toString(),
      twoFactorDestination: data['two_factor_destination']?.toString(),
      isPecCertified: data['pec_certified'] == true,
    );
  }

  static Future<UserProfile> updateProfile({
    required String userId,
    required String nickname,
    required String preferredLanguageCode,
    String? profileBio,
    String? profilePhotoUrl,
    String? profileAudioUrl,
    double? profileAudioDurationSeconds,
  }) async {
    final parsedBase = Uri.parse('$baseUrl?route=settings');
    final uri = parsedBase.replace(
      queryParameters: {
        ...parsedBase.queryParameters,
        'user_id': userId,
      },
    );
    final body = jsonEncode({
      'nickname': nickname,
      'preferred_language': preferredLanguageCode,
      'profile_bio': profileBio ?? '',
      'profile_photo_url': profilePhotoUrl ?? '',
      'profile_audio_url': profileAudioUrl ?? '',
      'profile_audio_duration_seconds': profileAudioDurationSeconds,
    });

    final response = await _client.post(
      uri,
      headers: AppRequestSigner.buildSignedHeaders(
        method: 'POST',
        uri: uri,
        body: body,
        headers: const {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'User-Agent': 'QuiceApp/1.0.0',
        },
      ),
      body: body,
    );

    if (response.statusCode >= 400) {
      throw Exception('Errore salvataggio profilo (${response.statusCode}).');
    }
    final payload = jsonDecode(response.body);
    if (payload['success'] != true) {
      throw Exception(payload['error'] ?? 'Impossibile aggiornare le impostazioni.');
    }
    
    return UserProfile(
      id: userId,
      name: nickname,
      nickname: nickname,
      email: '',
      preferredLanguageCode: preferredLanguageCode,
      profileBio: (profileBio == null || profileBio.isEmpty) ? null : profileBio,
      profilePhotoUrl: (profilePhotoUrl == null || profilePhotoUrl.isEmpty) ? null : profilePhotoUrl,
      profileAudioUrl: (profileAudioUrl == null || profileAudioUrl.isEmpty) ? null : profileAudioUrl,
      profileAudioDurationSeconds: profileAudioDurationSeconds,
    );
  }

  static Future<UserProfile> fetchUserProfile(String targetUserId) async {
    final parsedBase = Uri.parse('$baseUrl?route=settings');
    final uri = parsedBase.replace(
      queryParameters: {
        ...parsedBase.queryParameters,
        'user_id': targetUserId,
      },
    );

    final response = await _client.get(
      uri,
      headers: AppRequestSigner.buildSignedHeaders(
        method: 'GET',
        uri: uri,
        body: '',
        headers: const {
          'ngrok-skip-browser-warning': 'true',
          'User-Agent': 'QuiceApp/1.0.0',
        },
      ),
    );

    if (response.statusCode >= 400) {
      throw Exception('Impossibile caricare il profilo (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body);
    if (payload['success'] != true) {
      throw Exception(payload['error'] ?? 'Errore nel recupero dati profilo.');
    }

    final data = payload['data'] as Map<String, dynamic>;
    final nickname = data['nickname']?.toString() ?? 'Utente $targetUserId';
    final profileBio = data['profile_bio']?.toString();
    final profilePhotoUrl = data['profile_photo_url']?.toString();
    final profileAudioUrl = data['profile_audio_url']?.toString();
    final profileAudioDurationRaw = data['profile_audio_duration_seconds'];
    final profileAudioDuration = profileAudioDurationRaw is num
        ? profileAudioDurationRaw.toDouble()
        : double.tryParse(profileAudioDurationRaw?.toString() ?? '');

    return UserProfile(
      id: targetUserId,
      name: nickname,
      nickname: nickname,
      email: '',
      preferredLanguageCode: data['preferred_language']?.toString() ?? 'en',
      profileBio: (profileBio == null || profileBio.isEmpty) ? null : profileBio,
      profilePhotoUrl: (profilePhotoUrl == null || profilePhotoUrl.isEmpty) ? null : profilePhotoUrl,
      profileAudioUrl: (profileAudioUrl == null || profileAudioUrl.isEmpty) ? null : profileAudioUrl,
      profileAudioDurationSeconds: profileAudioDuration,
    );
  }
}
