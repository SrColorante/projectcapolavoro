import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/message_translation_service.dart';
import 'home_screen.dart'; // To get SettingsPanel

class MobileSettingsScreen extends StatelessWidget {
  const MobileSettingsScreen({
    super.key,
    required this.profileNotifier,
    required this.nicknameController,
    required this.themeColorNotifier,
    required this.backgroundColorNotifier,
    required this.backgroundImageNotifier,
    required this.languageNotifier,
    required this.supportedLanguages,
    required this.presetColors,
    required this.onThemeColorChanged,
    required this.onBackgroundColorChanged,
    required this.onPickBackgroundImage,
    required this.onClearBackgroundImage,
    required this.onBackgroundImageChanged,
    required this.onLanguageChanged,
    required this.isSavingNotifier,
    required this.onSavePressed,
    required this.vibrationNotifier,
    required this.onVibrationToggled,
    required this.ringtoneNotifier,
    required this.onPickRingtone,
    required this.onEditProfilePressed,
    required this.onLogoutPressed,
  });

  final ValueNotifier<UserProfile> profileNotifier;
  final TextEditingController nicknameController;
  final ValueNotifier<Color> themeColorNotifier;
  final ValueNotifier<Color> backgroundColorNotifier;
  final ValueNotifier<String?> backgroundImageNotifier;
  final ValueNotifier<String> languageNotifier;
  final List<LanguageOption> supportedLanguages;
  final List<Color> presetColors;
  final ValueChanged<Color> onThemeColorChanged;
  final ValueChanged<Color> onBackgroundColorChanged;
  final VoidCallback onPickBackgroundImage;
  final VoidCallback onClearBackgroundImage;
  final ValueChanged<String?> onBackgroundImageChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueNotifier<bool> isSavingNotifier;
  final Future<void> Function() onSavePressed;
  final ValueNotifier<bool> vibrationNotifier;
  final ValueChanged<bool> onVibrationToggled;
  final ValueNotifier<String?> ringtoneNotifier;
  final VoidCallback onPickRingtone;
  final VoidCallback onEditProfilePressed;
  final VoidCallback onLogoutPressed;

  @override
  Widget build(BuildContext context) {
    final mergedListenable = Listenable.merge([
      profileNotifier,
      themeColorNotifier,
      backgroundColorNotifier,
      backgroundImageNotifier,
      languageNotifier,
      isSavingNotifier,
      vibrationNotifier,
      ringtoneNotifier,
    ]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: mergedListenable,
        builder: (context, _) {
          return SettingsPanel(
            profile: profileNotifier.value,
            nicknameController: nicknameController,
            selectedThemeColor: themeColorNotifier.value,
            selectedBackgroundColor: backgroundColorNotifier.value,
            selectedBackgroundImagePath: backgroundImageNotifier.value,
            selectedLanguageCode: languageNotifier.value,
            supportedLanguages: supportedLanguages,
            presetColors: presetColors,
            onThemeColorChanged: onThemeColorChanged,
            onBackgroundColorChanged: onBackgroundColorChanged,
            onPickBackgroundImage: onPickBackgroundImage,
            onClearBackgroundImage: () {
              onBackgroundImageChanged(null);
              onClearBackgroundImage();
            },
            onLanguageChanged: onLanguageChanged,
            isSaving: isSavingNotifier.value,
            onSavePressed: onSavePressed,
            vibrationEnabled: vibrationNotifier.value,
            onVibrationToggled: onVibrationToggled,
            ringtonePath: ringtoneNotifier.value,
            onPickRingtone: onPickRingtone,
            onEditProfilePressed: onEditProfilePressed,
            onLogoutPressed: onLogoutPressed,
          );
        },
      ),
    );
  }
}
