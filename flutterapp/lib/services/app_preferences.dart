import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'message_translation_service.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();

  static const int defaultThemeColorValue = 0xFF1E1E1E;
  static const int defaultBackgroundColorValue = 0xFFFFFFFF;
  static const String defaultLanguageCode = 'en';
  static const _themeColorKey = 'app_theme_color';
  static const _backgroundColorKey = 'app_background_color';
  static const _backgroundImagePathKey = 'app_background_image_path';
  static const _preferredLanguageKey = 'preferred_language_code';
  static const _sessionPhoneKey = 'session_phone';
  static const _sessionPasswordKey = 'session_password';
  static const _sessionIsGuestKey = 'session_is_guest';
  static const _sessionGuestNameKey = 'session_guest_name';
  static const _sessionProfileKey = 'session_user_profile';

  SharedPreferences? _sharedPreferences;
  bool _isLoaded = false;
  int _themeColorValue = defaultThemeColorValue;
  int _backgroundColorValue = defaultBackgroundColorValue;
  String? _backgroundImagePath;
  String _preferredLanguageCode = defaultLanguageCode;
  UserProfile? _currentUserProfile;

  UserProfile? get currentUserProfile => _currentUserProfile;

  Future<void> saveUserSession(String phone, String password, UserProfile profile) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.setString(_sessionPhoneKey, phone);
    await preferences.setString(_sessionPasswordKey, password);
    await preferences.setBool(_sessionIsGuestKey, false);
    await preferences.setString(_sessionProfileKey, jsonEncode(profile.toJson()));
    await preferences.remove(_sessionGuestNameKey);
    _currentUserProfile = profile;
    notifyListeners();
  }

  Future<void> saveGuestSession(String guestName, UserProfile profile) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.setBool(_sessionIsGuestKey, true);
    await preferences.setString(_sessionGuestNameKey, guestName);
    await preferences.setString(_sessionProfileKey, jsonEncode(profile.toJson()));
    await preferences.remove(_sessionPhoneKey);
    await preferences.remove(_sessionPasswordKey);
    _currentUserProfile = profile;
    notifyListeners();
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.setString(_sessionProfileKey, jsonEncode(profile.toJson()));
    _currentUserProfile = profile;
    notifyListeners();
  }

  Future<void> clearSession() async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    await preferences.remove(_sessionPhoneKey);
    await preferences.remove(_sessionPasswordKey);
    await preferences.remove(_sessionIsGuestKey);
    await preferences.remove(_sessionGuestNameKey);
    await preferences.remove(_sessionProfileKey);
    _currentUserProfile = null;
    notifyListeners();
  }

  bool hasSession() {
    final prefs = _sharedPreferences;
    if (prefs == null) return false;
    final isGuest = prefs.getBool(_sessionIsGuestKey) ?? false;
    if (isGuest) {
      return prefs.getString(_sessionGuestNameKey) != null;
    } else {
      return prefs.getString(_sessionPhoneKey) != null && prefs.getString(_sessionPasswordKey) != null;
    }
  }

  bool isGuestSession() {
    return _sharedPreferences?.getBool(_sessionIsGuestKey) ?? false;
  }

  String? getSavedPhone() {
    return _sharedPreferences?.getString(_sessionPhoneKey);
  }

  String? getSavedPassword() {
    return _sharedPreferences?.getString(_sessionPasswordKey);
  }

  String? getSavedGuestName() {
    return _sharedPreferences?.getString(_sessionGuestNameKey);
  }

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
    _sharedPreferences = await SharedPreferences.getInstance();
    _themeColorValue =
        _sharedPreferences!.getInt(_themeColorKey) ?? defaultThemeColorValue;
    _backgroundColorValue =
        _sharedPreferences!.getInt(_backgroundColorKey) ?? defaultBackgroundColorValue;
    _backgroundImagePath = _sharedPreferences!.getString(_backgroundImagePathKey);
    _preferredLanguageCode = _normalizeLanguageCode(
        _sharedPreferences!.getString(_preferredLanguageKey) ??
            PlatformDispatcher.instance.locale.languageCode,
    );

    final profileJson = _sharedPreferences!.getString(_sessionProfileKey);
    if (profileJson != null) {
      try {
        _currentUserProfile = UserProfile.fromJson(jsonDecode(profileJson));
      } catch (_) {}
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

  @visibleForTesting
  Future<void> resetForTests() async {
    _sharedPreferences = null;
    _isLoaded = false;
    _themeColorValue = defaultThemeColorValue;
    _backgroundColorValue = defaultBackgroundColorValue;
    _backgroundImagePath = null;
    _preferredLanguageCode = defaultLanguageCode;
  }

  String _normalizeLanguageCode(String rawLanguageCode) {
    return MessageTranslationService.normalizeLanguageCode(rawLanguageCode);
  }
}
