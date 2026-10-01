import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'session_store.dart';

/// Risultato di un accesso riuscito: profilo e dati di sessione.
class AuthSession {
  const AuthSession({
    required this.profile,
    required this.token,
    required this.expiresAt,
    this.cancellationPending = false,
  });

  final UserProfile profile;
  final String token;
  final String expiresAt;
  final bool cancellationPending;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl, SessionStore? store})
      : _store = store ?? sessionStore,
        _api = ApiClient(client: client, baseUrl: baseUrl, store: store ?? sessionStore);

  static const String _defaultUserName = 'Nuovo utente';

  final ApiClient _api;
  final SessionStore _store;

  /// Istanza predefinita usata dall'applicazione.
  static final AuthApi instance = AuthApi();

  static String get baseUrl => ApiConfig.baseUrl;

  @visibleForTesting
  ApiClient get api => _api;

  // ------------------------------------------------------------------
  //  Accesso e registrazione
  // ------------------------------------------------------------------

  /// Registra un nuovo account e avvia la sessione.
  ///
  /// Il numero di telefono e' l'identificativo e deve essere di esattamente
  /// 10 cifre. Prima l'app ne accettava da 8 a 15 e la validazione viveva
  /// solo lato client: si poteva registrare un numero che il server avrebbe
  /// poi rifiutato per sempre, bloccando l'utente fuori dal proprio account.
  static String? validatePhone(String value) {
    final digits = value.replaceAll(RegExp(r'[\s.]'), '');
    if (digits.isEmpty) return 'Inserisci il numero di telefono.';
    if (!RegExp(r'^\d{10}$').hasMatch(digits)) {
      return 'Il numero deve essere di esattamente 10 cifre.';
    }
    return null;
  }

  /// Verifica i requisiti minimi di una password, in modo che l'utente
  /// riceva subito l'errore senza attendere il server.
  static String? validatePassword(String value) {
    if (value.length < 10) {
      return 'La password deve contenere almeno 10 caratteri.';
    }
    if (!RegExp(r'[a-z]').hasMatch(value) ||
        !RegExp(r'[A-Z]').hasMatch(value) ||
        !RegExp(r'\d').hasMatch(value)) {
      return 'Servono almeno una minuscola, una maiuscola e una cifra.';
    }
    return null;
  }

  Future<AuthSession> register({
    required String name,
    required String phone,
    required String password,
    String? email,
    String preferredLanguageCode = 'en',
  }) async {
    final phoneError = validatePhone(phone);
    if (phoneError != null) throw ApiException(phoneError);
    final passwordError = validatePassword(password);
    if (passwordError != null) throw ApiException(passwordError);

    final payload = await _api.post('index.php', body: {
      'route': 'auth',
      'action': 'register',
      'name': name.trim().isEmpty ? _defaultUserName : name.trim(),
      'phone': phone.replaceAll(RegExp(r'[\s.]'), ''),
      'password': password,
      'email': email ?? '',
      'preferred_language': preferredLanguageCode,
      'device_label': ApiConfig.deviceLabel,
    }, query: {'route': 'auth'});

    return _consumeSession(payload, fallbackName: name.trim());
  }

  Future<AuthSession> login({
    required String phone,
    required String password,
  }) async {
    final phoneError = validatePhone(phone);
    if (phoneError != null) throw ApiException(phoneError);

    final payload = await _api.post('index.php', body: {
      'route': 'auth',
      'action': 'login',
      'phone': phone.replaceAll(RegExp(r'[\s.]'), ''),
      'password': password,
      'device_label': ApiConfig.deviceLabel,
    }, query: {'route': 'auth'});

    return _consumeSession(payload, fallbackName: 'Utente');
  }

  /// Accesso come ospite: crea un account usa-e-getta, senza email e senza
  /// password utilizzabile. I dati dell'ospite scadono automaticamente.
  Future<AuthSession> guestLogin({
    String name = 'Ospite',
    String preferredLanguageCode = 'en',
  }) async {
    final payload = await _api.post('index.php', body: {
      'route': 'auth',
      'action': 'guest_login',
      'name': name,
      'preferred_language': preferredLanguageCode,
      'device_label': ApiConfig.deviceLabel,
    }, query: {'route': 'auth'});

    return _consumeSession(payload, fallbackName: name.trim().isEmpty ? 'Ospite' : name.trim());
  }

  /// Disconnessione: revoca il token lato server.
  ///
  /// Revocarlo conta: altrimenti il token resterebbe valido fino alla
  /// scadenza, e su un dispositivo ceduto a qualcun altro continuerebbe a
  /// funzionare.
  Future<void> logout() async {
    try {
      await _api.post('index.php', body: const {'route': 'auth', 'action': 'logout'},
          query: const {'route': 'auth'});
    } catch (_) {
      // Anche senza rete il token locale va rimosso.
    } finally {
      await _store.clear();
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final error = validatePassword(newPassword);
    if (error != null) throw ApiException(error);
    if (currentPassword == newPassword) {
      throw ApiException('La nuova password deve essere diversa da quella attuale.');
    }

    final payload = await _api.post('index.php', body: {
      'route': 'auth',
      'action': 'change_password',
      'current_password': currentPassword,
      'new_password': newPassword,
    }, query: {'route': 'auth'});

    // Il server emette un token nuovo e revoca gli altri dispositivi: va
    // salvato subito, altrimenti la sessione corrente si chiude da sola.
    final token = payload['data']?['token']?.toString();
    if (token != null && token.isNotEmpty) {
      await _store.save(
        token: token,
        userId: await _store.readUserId() ?? '',
        expiresAt: payload['data']?['expires_at']?.toString(),
      );
    }
  }

  // ------------------------------------------------------------------
  //  Profilo
  // ------------------------------------------------------------------

  /// Salva le preferenze del profilo. L'identita' dell'utente NON viene
  /// inviata: il server la deduce dal token.
  Future<UserProfile> updateProfile({
    required String userId,
    String? nickname,
    String? preferredLanguageCode,
    String? profileBio,
    String? profilePhotoUrl,
    String? profileAudioUrl,
    double? profileAudioDurationSeconds,
    bool clearAudio = false,
  }) async {
    final payload = await _api.post('settings', body: {
      'nickname': nickname,
      'preferred_language': preferredLanguageCode,
      'profile_bio': profileBio,
      'profile_photo_url': profilePhotoUrl,
      'profile_audio_url': clearAudio ? '' : profileAudioUrl,
      'profile_audio_duration_seconds':
          clearAudio ? null : profileAudioDurationSeconds,
    });

    final data = (payload['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return _profileFromMap(data, fallbackId: userId);
  }

  /// Profilo pubblico di un altro utente. Restituisce solo i dati minimi
  /// (nome, nickname, foto): email, 2FA e stato di cancellazione di terzi non
  /// sono esposti, perche' non servono e sono dati identificativi.
  Future<List<UserProfile>> fetchPublicProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return const <UserProfile>[];
    final payload = await _api.get('users',
        query: {'user_ids': userIds.take(50).join(',')});
    final data = (payload['data'] as List<dynamic>?) ?? const <dynamic>[];
    return data
        .map((item) => _profileFromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  /// I dati propri, compresi quelli identificativi che l'utente stesso puo'
  /// vedere legittimamente.
  Future<UserProfile> fetchOwnProfile() async {
    final payload = await _api.get('users', query: const {'me': '1'});
    return _profileFromMap(
      (payload['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }

  // ------------------------------------------------------------------
  //  Interno
  // ------------------------------------------------------------------

  /// Estrae profilo e token dalla risposta e li scrive nell'archivio sicuro.
  Future<AuthSession> _consumeSession(
    Map<String, dynamic> payload, {
    required String fallbackName,
  }) async {
    final data = (payload['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ApiException('Il server non ha restituito una sessione valida.');
    }

    final userData = (data['user'] as Map<String, dynamic>?) ?? data;
    final profile = _profileFromMap(userData, fallbackName: fallbackName);

    await _store.save(
      token: token,
      userId: profile.id,
      expiresAt: data['expires_at']?.toString(),
    );

    return AuthSession(
      profile: profile,
      token: token,
      expiresAt: data['expires_at']?.toString() ?? '',
      cancellationPending: data['cancellation_pending'] == true,
    );
  }

  UserProfile _profileFromMap(
    Map<String, dynamic> data, {
    String? fallbackId,
    String? fallbackName,
  }) {
    final id = data['id']?.toString() ?? fallbackId ?? '';
    final name = data['name']?.toString().trim();
    final nickname = data['nickname']?.toString().trim();
    final resolvedName = (name == null || name.isEmpty)
        ? (fallbackName ?? 'Utente')
        : name;
    final resolvedNickname =
        (nickname == null || nickname.isEmpty) ? resolvedName : nickname;

    final bio = data['profile_bio']?.toString().trim();
    final photo = data['profile_photo_url']?.toString().trim();
    final audio = data['profile_audio_url']?.toString().trim();
    final durationRaw = data['profile_audio_duration_seconds'];

    return UserProfile(
      id: id,
      name: resolvedName,
      nickname: resolvedNickname,
      email: data['email']?.toString() ?? '',
      isGuest: data['is_guest'] == true,
      preferredLanguageCode: data['preferred_language']?.toString() ?? 'en',
      profileBio: (bio == null || bio.isEmpty) ? null : bio,
      profilePhotoUrl: (photo == null || photo.isEmpty) ? null : photo,
      profileAudioUrl: (audio == null || audio.isEmpty) ? null : audio,
      profileAudioDurationSeconds: durationRaw is num
          ? durationRaw.toDouble()
          : double.tryParse(durationRaw?.toString() ?? ''),
      e2eePublicKey: data['e2ee_public_key']?.toString(),
      twoFactorEnabled: data['two_factor_enabled'] == true,
      twoFactorChannel: data['two_factor_channel']?.toString(),
      twoFactorDestination: data['two_factor_destination']?.toString(),
      isPecCertified: data['pec_certified'] == true,
    );
  }
}
