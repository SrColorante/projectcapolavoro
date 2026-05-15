import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';

class CrimsonChatApp extends StatelessWidget {
  const CrimsonChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    const crimson = Color(0xFFDC143C);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Crimson Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: crimson,
          primary: crimson,
          secondary: const Color(0xFF8B0000),
          surface: const Color(0xFFFFF5F6),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF5F6),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
