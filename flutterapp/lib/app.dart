import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/app_preferences.dart';

DecorationImage? _buildAppBackgroundImage(String? backgroundImagePath) {
  final path = backgroundImagePath?.trim();
  if (path == null || path.isEmpty) {
    return null;
  }

  if (path.startsWith('http://') || path.startsWith('https://')) {
    return DecorationImage(
      image: NetworkImage(path),
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(Colors.white.withOpacity(0.16), BlendMode.dstATop),
    );
  }

  if (path.startsWith('assets/')) {
    return DecorationImage(
      image: AssetImage(path),
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(Colors.white.withOpacity(0.16), BlendMode.dstATop),
    );
  }

  final file = File(path);
  if (file.existsSync()) {
    return DecorationImage(
      image: FileImage(file),
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(Colors.white.withOpacity(0.16), BlendMode.dstATop),
    );
  }

  return null;
}

ThemeData _buildGlassTheme({required bool isDarkBase, required Color accentColor}) {
  final scaffoldColor = Colors.transparent;
  final surfaceColor = isDarkBase ? const Color(0xFF101010).withOpacity(0.42) : Colors.white.withOpacity(0.34);
  final textOnBase = isDarkBase ? Colors.white : Colors.black87;

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      brightness: isDarkBase ? Brightness.dark : Brightness.light,
      seedColor: accentColor,
      primary: accentColor,
      secondary: isDarkBase ? Colors.white : Colors.black,
      surface: surfaceColor,
      surfaceTint: Colors.transparent,
      onSurface: textOnBase,
    ),
    scaffoldBackgroundColor: scaffoldColor,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: textOnBase,
      surfaceTintColor: Colors.transparent,
    ),
    cardColor: surfaceColor,
    dialogBackgroundColor: surfaceColor,
    useMaterial3: true,
  );
}

class CrimsonChatApp extends StatelessWidget {
  const CrimsonChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPreferences.instance,
      builder: (context, _) {
        final crimson = Color(AppPreferences.instance.themeColorValue);
        final baseBackground = Color(AppPreferences.instance.backgroundColorValue);
        final backgroundImage = AppPreferences.instance.backgroundImagePath;
        final isDarkBase = AppPreferences.instance.isDarkBaseTheme;
        final lightTheme = _buildGlassTheme(isDarkBase: false, accentColor: crimson);
        final darkTheme = _buildGlassTheme(isDarkBase: true, accentColor: crimson);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Quice',
          theme: lightTheme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: lightTheme.colorScheme.copyWith(
              surface: Colors.white.withOpacity(0.34),
            ),
          ),
          darkTheme: darkTheme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: darkTheme.colorScheme.copyWith(
              surface: Colors.black.withOpacity(0.42),
            ),
          ),
          themeMode: isDarkBase ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: baseBackground,
                image: _buildAppBackgroundImage(backgroundImage),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
