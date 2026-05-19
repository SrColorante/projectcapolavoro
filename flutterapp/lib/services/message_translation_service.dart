import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

abstract class MessageTranslator {
  Future<String> translateOutgoing(
    String text, {
    required String sourceLanguageCode,
  });

  Future<String> translateIncoming(
    String text, {
    required String targetLanguageCode,
  });
}

class MessageTranslationService implements MessageTranslator {
  MessageTranslationService._();

  static final MessageTranslationService instance = MessageTranslationService._();

  static const String fallbackLanguageCode = 'en';
  static const Map<String, String> _languageLabels = <String, String>{
    'ar': 'العربية',
    'de': 'Deutsch',
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'hi': 'हिन्दी',
    'it': 'Italiano',
    'ja': '日本語',
    'ko': '한국어',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'pt': 'Português',
    'ru': 'Русский',
    'tr': 'Türkçe',
    'uk': 'Українська',
    'zh': '中文',
  };

  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translatorCache =
      <String, OnDeviceTranslator>{};
  final Set<String> _downloadedModels = <String>{};

  static List<LanguageOption> supportedLanguages() {
    final seenCodes = <String>{};
    final options = TranslateLanguage.values
        .map((language) => language.bcpCode)
        .where(seenCodes.add)
        .map(
          (code) => LanguageOption(
            code: code,
            label: _languageLabels[code] ?? code.toUpperCase(),
          ),
        )
        .toList(growable: false)
      ..sort((left, right) => left.label.compareTo(right.label));
    return options;
  }

  static String normalizeLanguageCode(String rawLanguageCode) {
    final normalized = rawLanguageCode
        .trim()
        .replaceAll('_', '-')
        .split('-')
        .first
        .toLowerCase();
    if (normalized.isEmpty) {
      return fallbackLanguageCode;
    }
    return isSupportedLanguageCode(normalized)
        ? normalized
        : fallbackLanguageCode;
  }

  static bool isSupportedLanguageCode(String languageCode) {
    return TranslateLanguage.values.any(
      (language) => language.bcpCode == languageCode,
    );
  }

  static bool get supportsRuntimeTranslationOnCurrentPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<String> translateOutgoing(
    String text, {
    required String sourceLanguageCode,
  }) {
    return _translate(
      text,
      fromLanguageCode: normalizeLanguageCode(sourceLanguageCode),
      toLanguageCode: fallbackLanguageCode,
    );
  }

  @override
  Future<String> translateIncoming(
    String text, {
    required String targetLanguageCode,
  }) {
    return _translate(
      text,
      fromLanguageCode: fallbackLanguageCode,
      toLanguageCode: normalizeLanguageCode(targetLanguageCode),
    );
  }

  Future<String> _translate(
    String text, {
    required String fromLanguageCode,
    required String toLanguageCode,
  }) async {
    if (text.trim().isEmpty || fromLanguageCode == toLanguageCode) {
      return text;
    }
    if (!supportsRuntimeTranslationOnCurrentPlatform) {
      return text;
    }

    final sourceLanguage = _resolveLanguage(fromLanguageCode);
    final targetLanguage = _resolveLanguage(toLanguageCode);
    if (sourceLanguage == null || targetLanguage == null) {
      return text;
    }

    try {
      await _ensureModelDownloaded(sourceLanguage.bcpCode);
      await _ensureModelDownloaded(targetLanguage.bcpCode);
      final translator = _translatorFor(sourceLanguage, targetLanguage);
      return await translator.translateText(text);
    } catch (_) {
      return text;
    }
  }

  Future<void> _ensureModelDownloaded(String languageCode) async {
    if (_downloadedModels.contains(languageCode)) {
      return;
    }
    await _modelManager.downloadModel(languageCode);
    _downloadedModels.add(languageCode);
  }

  TranslateLanguage? _resolveLanguage(String languageCode) {
    for (final language in TranslateLanguage.values) {
      if (language.bcpCode == languageCode) {
        return language;
      }
    }
    return null;
  }

  OnDeviceTranslator _translatorFor(
    TranslateLanguage sourceLanguage,
    TranslateLanguage targetLanguage,
  ) {
    final cacheKey = '${sourceLanguage.bcpCode}->${targetLanguage.bcpCode}';
    return _translatorCache.putIfAbsent(
      cacheKey,
      () => OnDeviceTranslator(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ),
    );
  }
}

class LanguageOption {
  const LanguageOption({required this.code, required this.label});

  final String code;
  final String label;
}
