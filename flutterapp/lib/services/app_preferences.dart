import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'message_translation_service.dart';

/// Preferenze locali dell'applicazione.
///
/// NOTA SULLA MEMORIA DELLA PASSWORD
/// -----------------------------------
/// La versione precedente salvava la password in chiaro sotto la chiave
/// `session_password` e la reinviava a ogni avvio a freddo. Su Android
/// `SharedPreferences` e' un XML leggibile da qualunque app con accesso
/// all'archivio dell'utente; su Windows e' un file di testo semplice. La
/// password era quindi recuperabile da un dispositivo bloccato o da un backup
/// non cifrato — e non serviva a nulla, perche' da quando esiste la sessione
/// con token l'accesso non richiede piu' la password.
///
/// Ora la password non viene memorizzata. Resta solo il token di sessione, che
/// vive in `flutter_secure_storage`. Qui si conservano solo dati di
/// impostazione e il profilo, che non sono credenziali.
class AppPreferences extends ChangeNotifier {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();

  static const int defaultThemeColorValue = 0xFF1E1E1E;
  static const int defaultBackgroundColorValue = 0xFFFFFFFF;
  static const String defaultLanguageCode = 'en';

  static const String _themeColorKey = 'app_theme_color';
  static const String _backgroundColorKey = 'app_background_color';
  static const String _backgroundImagePathKey = 'app_background_image_path';
  static const String _preferredLanguageKey = 'preferred_language_code';
  static const String _sessionPhoneKey = 'session_phone';
  static const String _sessionIsGuestKey = 'session_is_guest';
  static const String _sessionGuestNameKey = 'session_guest_name';
  static const String _sessionProfileKey = 'session_user_profile';
  static const String _lanPeerConsentKey = 'consent_lan_peer_transfer';
  static const String _translationConsentKey = 'consent_translation_ondevice';
  static const String _voiceBioConsentKey = 'consent_voice_bio';

  SharedPreferences? _sharedPreferences;
  bool _isLoaded = false;
  int _themeColorValue = defaultThemeColorValue;
  int _backgroundColorValue = defaultBackgroundColorValue;
  String? _backgroundImagePath;
  String _preferredLanguageCode = defaultLanguageCode;
  UserProfile? _currentUserProfile;
  bool _lanPeerTransferConsented = false;
  bool _translationConsented = false;
  bool _voiceBioConsented = false;

  UserProfile? get currentUserProfile => _currentUserProfile;

  /// Consenso alla condivisione diretta con i dispositivi vicini (Art. 6(1)(a)).
  /// Senza questo consenso la sincronizzazione peer-to-peer non parte.
  bool get lanPeerTransferConsented => _lanPeerTransferConsented;

  bool get translationConsented => _translationConsented;

  bool get voiceBioConsented => _voiceBioConsented;

  /// Registra l'identita' dell'utente corrente. La password non viene salvata.
  Future<void> saveUserSession(String phone, UserProfile profile) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.setString(_sessionPhoneKey, phone);
    await preferences.setBool(_sessionIsGuestKey, false);
    await preferences.setString(_sessionProfileKey, jsonEncode(profile.toJson()));
    await preferences.remove(_sessionGuestNameKey);
    _sharedPreferences = preferences;
    _currentUserProfile = profile;
    notifyListeners();
  }

  Future<void> saveGuestSession(String guestName, UserProfile profile) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.setBool(_sessionIsGuestKey, true);
    await preferences.setString(_sessionGuestNameKey, guestName);
    await preferences.setString(_sessionProfileKey, jsonEncode(profile.toJson()));
    // Nessun numero di telefono per un ospite: l'identita' vive solo nel token.
    await preferences.remove(_sessionPhoneKey);
    _sharedPreferences = preferences;
    _currentUserProfile = profile;
    notifyListeners();
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.setString(_sessionProfileKey, jsonEncode(profile.toJson()));
    _sharedPreferences = preferences;
    _currentUserProfile = profile;
    notifyListeners();
  }

  /// Chiude la sessione locale.
  ///
  /// Rimuove anche le preferenze di consenso gia' memorizzate: leaving
  /// l'app deve azzerare le scelte privacy, cosi' un account successivo non
  /// eredita decisioni prese da un altro.
  Future<void> clearSession() async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.remove(_sessionPhoneKey);
    await preferences.remove(_sessionIsGuestKey);
    await preferences.remove(_sessionGuestNameKey);
    await preferences.remove(_sessionProfileKey);
    _sharedPreferences = preferences;
    _currentUserProfile = null;
    notifyListeners();
  }

  /// Elimina anche le preferenze di aspetto e consenso. Usato dalla
  /// cancellazione dell'account, che deve lasciare il dispositivo pulito.
  Future<void> clearAll() async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.clear();
    _sharedPreferences = preferences;
    _currentUserProfile = null;
    _themeColorValue = defaultThemeColorValue;
    _backgroundColorValue = defaultBackgroundColorValue;
    _backgroundImagePath = null;
    _preferredLanguageCode = defaultLanguageCode;
    _lanPeerTransferConsented = false;
    _translationConsented = false;
    _voiceBioConsented = false;
    notifyListeners();
  }

  /// Segnala la presenza di una sessione valida.
  ///
  /// Nota: non basta la presenza del profilo salvato. Il token vive in
  /// `flutter_secure_storage` ed e' l'unica prova di una sessione valida; se il
  /// server lo ha revocato, l'app deve tornare alla schermata di accesso.
  bool hasSession() {
    final prefs = _sharedPreferences;
    if (prefs == null) return false;
    final profileJson = prefs.getString(_sessionProfileKey);
    if (profileJson == null) return false;
    final isGuest = prefs.getBool(_sessionIsGuestKey) ?? false;
    return isGuest
        ? prefs.getString(_sessionGuestNameKey) != null
        : prefs.getString(_sessionPhoneKey) != null;
  }

  bool isGuestSession() => _sharedPreferences?.getBool(_sessionIsGuestKey) ?? false;

  String? getSavedPhone() => _sharedPreferences?.getString(_sessionPhoneKey);

  String? getSavedGuestName() => _sharedPreferences?.getString(_sessionGuestNameKey);

  bool get isLoaded => _isLoaded;
  int get themeColorValue => _themeColorValue;
  int get backgroundColorValue => _backgroundColorValue;
  String? get backgroundImagePath => _backgroundImagePath;
  bool get isDarkBaseTheme => Color(_backgroundColorValue).computeLuminance() < 0.5;
  String get preferredLanguageCode => _preferredLanguageCode;

  Future<void> load() async {
    if (_isLoaded) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    _sharedPreferences = preferences;
    _themeColorValue = preferences.getInt(_themeColorKey) ?? defaultThemeColorValue;
    _backgroundColorValue =
        preferences.getInt(_backgroundColorKey) ?? defaultBackgroundColorValue;
    _backgroundImagePath = preferences.getString(_backgroundImagePathKey);
    _preferredLanguageCode = _normalizeLanguageCode(
      preferences.getString(_preferredLanguageKey) ??
          PlatformDispatcher.instance.locale.languageCode,
    );
    _lanPeerTransferConsented = preferences.getBool(_lanPeerConsentKey) ?? false;
    _translationConsented = preferences.getBool(_translationConsentKey) ?? false;
    _voiceBioConsented = preferences.getBool(_voiceBioConsentKey) ?? false;

    final profileJson = preferences.getString(_sessionProfileKey);
    if (profileJson != null) {
      try {
        _currentUserProfile = UserProfile.fromJson(jsonDecode(profileJson));
      } catch (_) {
        // Profilo illeggibile (formato cambiato): si riparte senza sessione.
      }
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> saveSettings({
    required int themeColorValue,
    int? backgroundColorValue,
    String? backgroundImagePath,
    required String preferredLanguageCode,
  }) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    final normalizedLanguage = _normalizeLanguageCode(preferredLanguageCode);
    await preferences.setInt(_themeColorKey, themeColorValue);
    if (backgroundColorValue != null) {
      await preferences.setInt(_backgroundColorKey, backgroundColorValue);
      _backgroundColorValue = backgroundColorValue;
    }
    if (backgroundImagePath != null && backgroundImagePath.isNotEmpty) {
      await preferences.setString(_backgroundImagePathKey, backgroundImagePath);
      _backgroundImagePath = backgroundImagePath;
    } else {
      await preferences.remove(_backgroundImagePathKey);
      _backgroundImagePath = null;
    }
    await preferences.setString(_preferredLanguageKey, normalizedLanguage);
    _sharedPreferences = preferences;
    _themeColorValue = themeColorValue;
    _preferredLanguageCode = normalizedLanguage;
    _isLoaded = true;
    notifyListeners();
  }

  /// Aggiorna in locale lo stato di un consenso. Il valore autorevole resta
  /// quello del server: questa copia serve a non interrogare la rete a ogni
  /// avvio e a rendere l'app utilizzabile anche offline.
  Future<void> setConsent(String type, bool granted) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    _sharedPreferences = preferences;
    switch (type) {
      case 'lan_peer_transfer':
        await preferences.setBool(_lanPeerConsentKey, granted);
        _lanPeerTransferConsented = granted;
        break;
      case 'translation_ondevice':
        await preferences.setBool(_translationConsentKey, granted);
        _translationConsented = granted;
        break;
      case 'voice_bio':
        await preferences.setBool(_voiceBioConsentKey, granted);
        _voiceBioConsented = granted;
        break;
    }
    notifyListeners();
  }

  @visibleForTesting
  Future<void> resetForTests() async {
    _sharedPreferences = null;
    _isLoaded = false;
    _themeColorValue = defaultThemeColorValue;
    _backgroundColorValue = defaultBackgroundColorValue;
    _backgroundImagePath = null;
    _preferredLanguageCode = defaultLanguageCode;
    _currentUserProfile = null;
    _lanPeerTransferConsented = false;
    _translationConsented = false;
    _voiceBioConsented = false;
  }

  String _normalizeLanguageCode(String rawLanguageCode) {
    return MessageTranslationService.normalizeLanguageCode(rawLanguageCode);
  }
}
