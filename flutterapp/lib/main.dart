import 'dart:io';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_preferences.dart';

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _MyHttpOverrides();
  await AppPreferences.instance.load();
  runApp(const CrimsonChatApp());
}
