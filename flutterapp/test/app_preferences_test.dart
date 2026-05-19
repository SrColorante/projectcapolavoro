import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutterapp/services/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_theme_color': 0xFF1565C0,
      'preferred_language_code': 'it',
    });
    await AppPreferences.instance.resetForTests();
  });

  test('loads saved theme and preferred language from local device storage', () async {
    await AppPreferences.instance.load();

    expect(AppPreferences.instance.themeColorValue, 0xFF1565C0);
    expect(AppPreferences.instance.preferredLanguageCode, 'it');
  });

  test('persists settings updates only in local shared preferences', () async {
    await AppPreferences.instance.load();
    await AppPreferences.instance.saveSettings(
      themeColorValue: 0xFF2E7D32,
      preferredLanguageCode: 'es',
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('app_theme_color'), 0xFF2E7D32);
    expect(preferences.getString('preferred_language_code'), 'es');
  });
}
