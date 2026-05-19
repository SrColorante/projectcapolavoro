import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  runApp(const CrimsonChatApp());
}
