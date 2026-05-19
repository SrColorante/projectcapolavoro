import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_translation_service.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();

  static const int defaultThemeColorValue = 0xFFDC143C;
  static const String defaultLanguageCode = 'en';
  static const _themeColorKey = 'app_theme_color';
  static const _preferredLanguageKey = 'preferred_language_code';

  SharedPreferences? _sharedPreferences;
  bool _isLoaded = false;
  int _themeColorValue = defaultThemeColorValue;
  String _preferredLanguageCode = defaultLanguageCode;

  bool get isLoaded => _isLoaded;
  int get themeColorValue => _themeColorValue;
  String get preferredLanguageCode => _preferredLanguageCode;

  Future<void> load() async {
    if (_isLoaded) {
      return;
    }
    _sharedPreferences = await SharedPreferences.getInstance();
    _themeColorValue =
        _sharedPreferences!.getInt(_themeColorKey) ?? defaultThemeColorValue;
    _preferredLanguageCode = _normalizeLanguageCode(
      _sharedPreferences!.getString(_preferredLanguageKey) ??
          PlatformDispatcher.instance.locale.languageCode,
    );
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> saveSettings({
    required int themeColorValue,
    required String preferredLanguageCode,
  }) async {
    final preferences = _sharedPreferences ?? await SharedPreferences.getInstance();
    final normalizedLanguage = _normalizeLanguageCode(preferredLanguageCode);
    await preferences.setInt(_themeColorKey, themeColorValue);
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
    _preferredLanguageCode = defaultLanguageCode;
  }

  String _normalizeLanguageCode(String rawLanguageCode) {
    return MessageTranslationService.normalizeLanguageCode(rawLanguageCode);
  }
}
