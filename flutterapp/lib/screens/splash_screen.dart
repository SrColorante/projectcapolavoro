import 'dart:async';
import 'package:flutter/material.dart';

import 'onboarding_wizard.dart';
import '../services/app_preferences.dart';
import '../api/auth_api.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  final Widget? nextScreen;
  const SplashScreen({super.key, this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pulseController;
  
  late Animation<double> _logoScale;
  late Animation<double> _textFade;
  late Animation<double> _textSlide;
  late Animation<double> _logoPulse;
  
  late Animation<double> _wave1Scale;
  late Animation<double> _wave1Opacity;
  late Animation<double> _wave2Scale;
  late Animation<double> _wave2Opacity;

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    // Entrance animation controller (2.5 seconds total for morphing dot + wave effect)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Pulse animation controller (breathing effect, 2 seconds loop)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Logo scale in: elastic expansion in the first 50% of entrance (starts as a dot)
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    // Wave 1 Scale and Opacity (Inner concentric wave)
    _wave1Scale = Tween<double>(begin: 0.8, end: 2.2).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _wave1Opacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeIn),
      ),
    );

    // Wave 2 Scale and Opacity (Outer concentric wave)
    _wave2Scale = Tween<double>(begin: 0.8, end: 3.2).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _wave2Opacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeIn),
      ),
    );

    // Text fade in: from 40% to 90% of entrance
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 0.9, curve: Curves.easeIn),
      ),
    );

    // Text slide up: from 40% to 90% of entrance
    _textSlide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    // Logo breathing pulse: scales between 1.0 and 1.04
    _logoPulse = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Start entrance animation
    _entranceController.forward().then((_) {
      if (mounted) {
        // Once entrance finishes, start the breathing pulse
        _pulseController.repeat(reverse: true);
      }
    });

    // Navigate or auto-login after 3.2 seconds
    _navigationTimer = Timer(const Duration(milliseconds: 3200), () {
      if (widget.nextScreen != null) {
        _navigateTo(widget.nextScreen!);
      } else {
        _checkAutoLogin();
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Color(AppPreferences.instance.themeColorValue);

    return Scaffold(
      body: Stack(
        children: [
          // Dynamic crimson premium gradient background matching AuthScreen for seamless fade
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF000000), const Color(0xFF0C0C0E), const Color(0xFF121212)]
                    : [const Color(0xFFFFFFFF), const Color(0xFFF6F6F9), const Color(0xFFEAEAEE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          Positioned(
            top: size.height * 0.2,
            left: size.width * 0.1,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: themeColor.withValues(alpha: isDark ? 0.08 : 0.15),
              ),
            ),
          ),
          
          // Central Content Area
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Glowing Logo
                ScaleTransition(
                  scale: _logoScale,
                  child: AnimatedBuilder(
                    animation: _logoPulse,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _logoPulse.value,
                        child: child,
                      );
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Concentric Ripple Wave 2 (Outer)
                        AnimatedBuilder(
                          animation: _entranceController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _wave2Scale.value,
                              child: Opacity(
                                opacity: _wave2Opacity.value,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: themeColor.withValues(alpha: 0.25),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // Concentric Ripple Wave 1 (Inner)
                        AnimatedBuilder(
                          animation: _entranceController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _wave1Scale.value,
                              child: Opacity(
                                opacity: _wave1Opacity.value,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: themeColor.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // Outer concentric glassmorphic ring
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.04),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // Middle concentric glassmorphic ring
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1,
                            ),
                          ),
                        ),
                        // Core Logo Container with rich white-to-rose gradient and deep glowing shadow
                        // Core Logo Container with rich 3D glass specular border and deep glowing shadow
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: isDark ? 0.28 : 0.68),
                                Colors.white.withValues(alpha: isDark ? 0.06 : 0.16),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: isDark ? 0.5 : 0.9),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
                                blurRadius: 18,
                                offset: const Offset(0, 9),
                              ),
                              BoxShadow(
                                color: themeColor.withValues(alpha: isDark ? 0.3 : 0.2),
                                blurRadius: 22,
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: isDark ? Colors.white : themeColor,
                              size: 46,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Sequentially animated title and subtitle
                FadeTransition(
                  opacity: _textFade,
                  child: AnimatedBuilder(
                    animation: _textSlide,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _textSlide.value),
                        child: child,
                      );
                    },
                    child: const Text(
                      'Quice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAutoLogin() async {
    final prefs = AppPreferences.instance;
    if (!prefs.hasSession()) {
      _navigateTo(const OnboardingWizardScreen());
      return;
    }

    final isGuest = prefs.isGuestSession();
    if (isGuest) {
      final guestName = prefs.getSavedGuestName() ?? 'Ospite';
      final cachedProfile = prefs.currentUserProfile;
      if (cachedProfile != null) {
        _navigateTo(HomeScreen(profile: cachedProfile));
        return;
      }
      try {
        final session = await AuthApi.instance.guestLogin(name: guestName);
        await prefs.saveGuestSession(guestName, session.profile);
        _navigateTo(HomeScreen(profile: session.profile));
      } catch (_) {
        _navigateTo(const OnboardingWizardScreen());
      }
      return;
    }

    final phone = prefs.getSavedPhone();

    // Non esiste piu' una password salvata: se il token di sessione non e'
    // piu' valido, l'utente deve autenticarsi di nuovo. Non si puo'
    // "recuperare" la sessione in silenzio, perche' non c'e' piu' nulla da
    // recuperare: e' il comportamento corretto dopo una disconnessione.
    if (phone == null || !prefs.hasSession()) {
      _navigateTo(const OnboardingWizardScreen());
      return;
    }

    try {
      // La validita' della sessione la decide il server: si interroga e'
      // l'endpoint dei propri dati. Se risponde, la sessione e' ancora buona.
      final profile = await AuthApi.instance.fetchOwnProfile();
      await prefs.saveUserSession(phone, profile);
      _navigateTo(HomeScreen(profile: profile));
    } catch (e) {
      final cachedProfile = prefs.currentUserProfile;
      final errorStr = e.toString().toLowerCase();
      final isNetworkError = errorStr.contains('timeout') ||
          errorStr.contains('socket') ||
          errorStr.contains('connection') ||
          errorStr.contains('host') ||
          errorStr.contains('clientexception');

      if (isNetworkError && cachedProfile != null) {
        _navigateTo(HomeScreen(profile: cachedProfile));
      } else {
        await prefs.clearSession();
        _navigateTo(const OnboardingWizardScreen());
      }
    }
  }

  void _navigateTo(Widget nextScreen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }
}
