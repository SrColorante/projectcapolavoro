import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_api.dart';
import '../api/chat_api.dart';
import '../models/user_profile.dart';
import '../services/api_exception_handler.dart';
import '../services/app_preferences.dart';
import '../services/message_translation_service.dart';
import 'home_screen.dart';
import '../widgets/rich_color_board.dart';

class OnboardingWizardScreen extends StatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  State<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> with TickerProviderStateMixin {
  int _currentStep = 0; // 0: Intro, 1: Signup, 2: Profile Customization, 3: App Customization, 4: Tutorial
  bool _isLoading = false;
  bool _isLoginMode = false;
  late UserProfile _currentProfile;

  // Global Page/Step Transitions
  Offset _transitionCenter = Offset.zero;
  bool _isTransitioningCircle = false;
  bool _isTransitioningStar = false;
  late AnimationController _transitionController;

  // Controllers for Signup Form (Step 3)
  final _signupFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _preferredLanguageCode = 'en';

  // State / Animation Controllers for Sequential Fields in Signup (Step 3)
  late AnimationController _signupSequenceController;
  final List<Animation<double>> _signupFieldAnimations = [];

  // Controllers/State for Profile Customization (Step 4)
  final _profileFormKey = GlobalKey<FormState>();
  late TextEditingController _nicknameController;
  final _bioController = TextEditingController();
  String? _localPhotoPath;
  final _imagePicker = ImagePicker();

  // Settings / Theme customization (Step 5)
  Color _themeColor = const Color(0xFF1E1E1E);
  bool _isDarkMode = false;
  final double _fontSizeFactor = 1.0;
  bool _vibrationEnabled = true;

  // Tutorial Slides (Step 6)
  int _tutorialSlideIndex = 0;
  late PageController _tutorialPageController;

  // Typewriter Animation (Step 2)
  String _introTypewriterText = '';
  final String _introFullText = "Connetti i tuoi contatti istantaneamente in totale sicurezza, con chat ad alta precisione e crittografia all'avanguardia.";
  Timer? _typewriterTimer;

  // Morphing logo wave and scale controllers
  late AnimationController _morphingController;
  late Animation<double> _logoScale;
  late Animation<double> _waveScale;
  late Animation<double> _waveOpacity;

  @override
  void initState() {
    super.initState();
    _tutorialPageController = PageController();
    _nicknameController = TextEditingController();

    // Transition controller
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Initial Splash / Morphing animation
    _morphingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _logoScale = Tween<double>(begin: 0.1, end: 1.0).animate(
      CurvedAnimation(
        parent: _morphingController,
        curve: Curves.elasticOut,
      ),
    );

    _waveScale = Tween<double>(begin: 0.8, end: 2.8).animate(
      CurvedAnimation(
        parent: _morphingController,
        curve: Curves.easeOutCubic,
      ),
    );

    _waveOpacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(
        parent: _morphingController,
        curve: Curves.easeIn,
      ),
    );

    // Initial sequential anim for signup fields
    _signupSequenceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    for (int i = 0; i < 6; i++) {
      _signupFieldAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _signupSequenceController,
            curve: Interval(i * 0.12, i * 0.12 + 0.4, curve: Curves.easeOutBack),
          ),
        ),
      );
    }

    _morphingController.forward().then((_) {
      _startIntroTypewriter();
    });
  }

  void _startIntroTypewriter() {
    int index = 0;
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (index < _introFullText.length) {
        if (mounted) {
          setState(() {
            _introTypewriterText += _introFullText[index];
          });
        }
        index++;
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    _bioController.dispose();
    _tutorialPageController.dispose();
    _transitionController.dispose();
    _morphingController.dispose();
    _signupSequenceController.dispose();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  // Visual Transitions
  void _nextStepSlide() {
    setState(() {
      _currentStep++;
      if (_currentStep == 1) {
        _signupSequenceController.forward();
      }
    });
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (!mounted) return;
      if (image != null) {
        setState(() {
          _localPhotoPath = image.path;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile selezionare la foto')),
      );
    }
  }

  // Action Methods
  Future<void> _submitSignup(Offset buttonOffset) async {
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim().replaceAll(' ', '');
      final email = _emailController.text.trim().isEmpty ? null : _emailController.text.trim();
      final password = _passwordController.text.trim();

      final session = await AuthApi.instance.register(
        name: name,
        phone: phone,
        email: email,
        password: password,
        preferredLanguageCode: _preferredLanguageCode,
      );
      final profile = session.profile;

      // Nessuna password conservata: la sessione vive nel token salvato
      // nell'archivio sicuro del dispositivo.
      await AppPreferences.instance.saveUserSession(phone, profile);

      setState(() {
        _currentProfile = profile;
        _nicknameController.text = profile.name;
      });

      // Play CIRCULAR transition
      _transitionCenter = buttonOffset;
      setState(() {
        _isTransitioningCircle = true;
      });

      await _transitionController.forward();
      setState(() {
        _currentStep = 2; // Move to profile customization
        _isTransitioningCircle = false;
      });
      _transitionController.reset();
    } catch (e) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitLogin(Offset buttonOffset) async {
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final phone = _phoneController.text.trim().replaceAll(' ', '');
      final password = _passwordController.text.trim();

      final session = await AuthApi.instance.login(
        phone: phone,
        password: password,
      );
      final profile = session.profile;

      await AppPreferences.instance.saveUserSession(phone, profile);

      setState(() {
        _currentProfile = profile;
        _nicknameController.text = profile.name;
        _bioController.text = profile.profileBio ?? '';
      });

      // Play CIRCULAR transition
      _transitionCenter = buttonOffset;
      setState(() {
        _isTransitioningCircle = true;
      });

      await _transitionController.forward();
      setState(() {
        if (profile.profileBio != null || profile.profilePhotoUrl != null) {
          _currentStep = 3; // Move directly to app customization if they already have customized profile
        } else {
          _currentStep = 2; // Let them customize profile
        }
        _isTransitioningCircle = false;
      });
      _transitionController.reset();
    } catch (e) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Profile customization save
  Future<void> _saveProfile(bool doLater) async {
    if (!doLater && !_profileFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String? photoUrl;
      if (!doLater && _localPhotoPath != null) {
        final chatApi = ChatApi();
        final attachmentData = await chatApi.uploadFile(
          userId: _currentProfile.id,
          filePath: _localPhotoPath!,
        );
        // Il server assegna una chiave di archiviazione casuale: non viene
        // piu' costruito alcun percorso a partire dal nome del file.
        photoUrl = attachmentData['storage_key']?.toString();
      }

      final nickname = doLater ? _currentProfile.name : _nicknameController.text.trim();
      final bio = doLater ? '' : _bioController.text.trim();

      final updatedProfile = await AuthApi.instance.updateProfile(
        userId: _currentProfile.id,
        nickname: nickname,
        preferredLanguageCode: _preferredLanguageCode,
        profileBio: bio,
        profilePhotoUrl: photoUrl,
      );

      setState(() {
        _currentProfile = updatedProfile;
      });
      await AppPreferences.instance.saveUserProfile(updatedProfile);

      // Slide or crossfade transition
      if (doLater) {
        // Vertical slide transition simulation
        await _transitionController.forward();
        setState(() {
          _currentStep = 3; // Customization
        });
        _transitionController.reset();
      } else {
        // Crossfade / simple slide
        setState(() {
          _currentStep = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Apply customizations & launch Star transition to main app
  Future<void> _finishSetup() async {
    setState(() => _isLoading = true);
    try {
      // Save localized configs
      await AppPreferences.instance.saveSettings(
        themeColorValue: _themeColor.toARGB32(),
        backgroundColorValue: _isDarkMode ? const Color(0xFF050505).toARGB32() : const Color(0xFFFFFFFF).toARGB32(),
        preferredLanguageCode: _preferredLanguageCode,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_vibration_enabled', _vibrationEnabled);

      // Play STAR WIPE transition
      setState(() {
        _isTransitioningStar = true;
      });

      _transitionController.duration = const Duration(milliseconds: 1200);
      await _transitionController.forward();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(profile: _currentProfile),
        ),
      );
    } catch (e) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDarkGlobal = _isDarkMode;

    return Theme(
      data: isDarkGlobal ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        body: Stack(
          children: [
            // Elegant background matching global crimson
            AnimatedContainer(
              duration: const Duration(milliseconds: 550),
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDarkGlobal
                      ? [const Color(0xFF000000), const Color(0xFF0C0C0E), const Color(0xFF121212)]
                      : [const Color(0xFFFFFFFF), const Color(0xFFF6F6F9), const Color(0xFFEAEAEE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            // Floating contrast circles for glassmorphism
            Positioned(
              top: size.height * 0.15,
              left: size.width * 0.1,
              child: _OnboardingFloatingCircle(
                size: 200,
                color: _themeColor.withValues(alpha: isDarkGlobal ? 0.05 : 0.15),
              ),
            ),
            Positioned(
              bottom: size.height * 0.15,
              right: size.width * 0.1,
              child: _OnboardingFloatingCircle(
                size: 260,
                color: _themeColor.withValues(alpha: isDarkGlobal ? 0.08 : 0.2),
              ),
            ),

            // Main Contents
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _buildStepCard(isDarkGlobal),
                  ),
                ),
              ),
            ),

            // Expanding circular wipe transition overlay
            if (_isTransitioningCircle)
              AnimatedBuilder(
                animation: _transitionController,
                builder: (context, child) {
                  return ClipPath(
                    clipper: CircleTransitionClipper(
                      fraction: _transitionController.value,
                      center: _transitionCenter,
                    ),
                    child: Container(
                      color: _themeColor,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  );
                },
              ),

            // Star Wipe transition overlay
            if (_isTransitioningStar)
              AnimatedBuilder(
                animation: _transitionController,
                builder: (context, child) {
                  return ClipPath(
                    clipper: StarTransitionClipper(
                      fraction: _transitionController.value,
                    ),
                    child: Container(
                      color: _themeColor,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard(bool isDark) {
    return _GlassCard(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress Indicator Dot Row (Hidden on Step 0 - Intro)
            if (_currentStep > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final active = _currentStep - 1 == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? _themeColor : Colors.grey.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
            ],

            // Content matching the step
            _getStepWidget(isDark),
          ],
        ),
      ),
    );
  }

  Widget _getStepWidget(bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStep2Intro(isDark);
      case 1:
        return _buildStep3Signup(isDark);
      case 2:
        return _buildStep4ProfileCustom(isDark);
      case 3:
        return _buildStep5AppCustom(isDark);
      case 4:
        return _buildStep6Tutorial(isDark);
      default:
        return Container();
    }
  }

  // --- Step 2: Small App Introduction ---
  Widget _buildStep2Intro(bool isDark) {
    return Column(
      children: [
        // Fluid Concentric Wave Morphing Logo
        AnimatedBuilder(
          animation: _morphingController,
          builder: (context, child) {
            return SizedBox(
              height: 180,
              width: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Wave Ripple 2
                  Transform.scale(
                    scale: _waveScale.value * 1.2,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _themeColor.withValues(alpha: _waveOpacity.value * 0.4),
                      ),
                    ),
                  ),
                  // Wave Ripple 1
                  Transform.scale(
                    scale: _waveScale.value,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _themeColor.withValues(alpha: _waveOpacity.value * 0.7),
                      ),
                    ),
                  ),
                  // Glowing Logo Core (3D Glossy Sphere)
                  Transform.scale(
                    scale: _logoScale.value,
                    child: Container(
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
                            color: _themeColor.withValues(alpha: isDark ? 0.3 : 0.2),
                            blurRadius: 22,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: isDark ? Colors.white : _themeColor,
                          size: 46,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Quice',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 16),

        // Typewriter intro text
        SizedBox(
          height: 80,
          child: Text(
            _introTypewriterText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.white70),
          ),
        ),
        const SizedBox(height: 24),

        // Floating message bubble micro-animation
        SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AnimatedBubbleNode(delay: 0, color: _themeColor),
              const SizedBox(width: 12),
              _AnimatedBubbleNode(delay: 200, color: _themeColor.withValues(alpha: 0.7)),
              const SizedBox(width: 12),
              _AnimatedBubbleNode(delay: 400, color: _themeColor.withValues(alpha: 0.5)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Next Button with Slide transition
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _nextStepSlide,
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('AVANTI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Signup(bool isDark) {
    return Form(
      key: _signupFormKey,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isLoginMode ? 'Accedi a Quice' : 'Registrati a Quice',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            if (!_isLoginMode) ...[
              // Name Field
              _buildSignupField(
                index: 0,
                child: _buildFormTextField(
                  controller: _nameController,
                  label: 'Nome completo',
                  icon: Icons.person_rounded,
                  validator: (val) {
                    if (_isLoginMode) return null;
                    return val == null || val.trim().isEmpty ? 'Inserisci il tuo nome' : null;
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Preferred Language
              _buildSignupField(
                index: 1,
                child: _buildLanguageDropdown(isDark),
              ),
              const SizedBox(height: 12),
            ],

            // Phone Number
            _buildSignupField(
              index: 2,
              child: _buildFormTextField(
                controller: _phoneController,
                label: 'Numero di telefono (10 cifre)',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Inserisci il numero di telefono';
                  if (int.tryParse(val.trim()) == null) return 'Inserisci solo cifre';
                  if (RegExp(r'^\d{10}$').hasMatch(val.trim().replaceAll(RegExp(r'[\s.]'), '')) == false) {
                    return 'Il numero deve essere di 10 cifre';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),

            if (!_isLoginMode) ...[
              // Optional Email
              _buildSignupField(
                index: 3,
                child: _buildFormTextField(
                  controller: _emailController,
                  label: 'Email (Opzionale)',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) {
                    if (_isLoginMode) return null;
                    if (val != null && val.trim().isNotEmpty && !val.contains('@')) {
                      return 'Inserisci un\'email valida';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Password
            _buildSignupField(
              index: 4,
              child: _buildFormTextField(
                controller: _passwordController,
                label: _isLoginMode ? 'Password' : 'Password (min. 6 char)',
                icon: Icons.lock_rounded,
                obscureText: true,
                validator: (val) => val == null || val.length < 6 ? 'La password deve avere almeno 6 caratteri' : null,
              ),
            ),
            const SizedBox(height: 12),

            if (!_isLoginMode) ...[
              // Confirm Password
              _buildSignupField(
                index: 5,
                child: _buildFormTextField(
                  controller: _confirmPasswordController,
                  label: 'Conferma Password',
                  icon: Icons.lock_rounded,
                  obscureText: true,
                  validator: (val) {
                    if (_isLoginMode) return null;
                    if (val != _passwordController.text) {
                      return 'Le password non coincidono';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),

            // Signup / Login Button
            Builder(
              builder: (context) {
                return SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            // Capture button coordinates for circle expanding wipe
                            final box = context.findRenderObject() as RenderBox?;
                            final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                            final size = box?.size ?? Size.zero;
                            final center = Offset(position.dx + size.width / 2, position.dy + size.height / 2);
                            if (_isLoginMode) {
                              _submitLogin(center);
                            } else {
                              _submitSignup(center);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _themeColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : Text(_isLoginMode ? 'ACCEDI' : 'REGISTRATI', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoginMode = !_isLoginMode;
                  _signupFormKey.currentState?.reset();
                });
              },
              child: Text(
                _isLoginMode ? 'Non hai un account? Registrati' : 'Hai già un account? Accedi',
                style: TextStyle(
                  color: _themeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupField({required int index, required Widget child}) {
    return AnimatedBuilder(
      animation: _signupSequenceController,
      builder: (context, animChild) {
        final val = _signupFieldAnimations[index].value;
        return Opacity(
          opacity: val.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0.0, (1.0 - val) * 20),
            child: animChild,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildLanguageDropdown(bool isDark) {
    final languageOptions = MessageTranslationService.supportedLanguages();
    return DropdownButtonFormField<String>(
      value: _preferredLanguageCode,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      dropdownColor: isDark ? const Color(0xFF2E050A) : Colors.white,
      decoration: InputDecoration(
        labelText: 'Lingua preferita per i messaggi',
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        prefixIcon: Icon(Icons.language_rounded, color: isDark ? Colors.white70 : Colors.black54),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _themeColor, width: 2),
        ),
      ),
      items: languageOptions
          .map(
            (language) => DropdownMenuItem<String>(
              value: language.code,
              child: Text(language.label, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) {
          setState(() => _preferredLanguageCode = value);
        }
      },
    );
  }

  Widget _buildFormTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.7)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _themeColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        errorStyle: const TextStyle(color: Colors.white),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // --- Step 4: Profile Customization ---
  Widget _buildStep4ProfileCustom(bool isDark) {
    ImageProvider? avatarImage;
    if (_localPhotoPath != null) {
      avatarImage = FileImage(File(_localPhotoPath!));
    }

    return Form(
      key: _profileFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Personalizza Profilo',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Upload avatar with animated preview
          Center(
            child: Stack(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? const Icon(Icons.person, size: 55, color: Colors.white)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _themeColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                      onPressed: _pickImage,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Nickname
          TextFormField(
            controller: _nicknameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nickname',
              prefixIcon: const Icon(Icons.badge, color: Colors.white70),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _themeColor, width: 2),
              ),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Inserisci un nickname' : null,
          ),
          const SizedBox(height: 12),

          // Personal Status / Bio
          TextFormField(
            controller: _bioController,
            maxLength: 150,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Stato personale / Bio',
              prefixIcon: const Icon(Icons.article_rounded, color: Colors.white70),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _themeColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Row with Next and pulsing "Do it later" button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Pulsing "Fai dopo"
              _PulsingDoLaterButton(
                onPressed: () => _saveProfile(true),
              ),
              ElevatedButton(
                onPressed: _isLoading ? null : () => _saveProfile(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _themeColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      )
                    : const Text('SALVA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Step 5: Application Customization ---
  Widget _buildStep5AppCustom(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Personalizza Quice',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        // 3D Flip Card Effect: Theme select and live preview card
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.palette, size: 20),
                    const SizedBox(width: 8),
                    const Text('Anteprima tema e colori', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _themeColor),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Simulated mini mock preview bubble
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _themeColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Ciao! Ti piace questo tema?',
                        style: TextStyle(color: Colors.white, fontSize: 13 * _fontSizeFactor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Base theme selector
        const Text(
          'Base app iniziale',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PresetColorNode(
                color: const Color(0xFFFFFFFF),
                isSelected: !_isDarkMode,
                onTap: () => setState(() => _isDarkMode = false),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _PresetColorNode(
                color: const Color(0xFF050505),
                isSelected: _isDarkMode,
                onTap: () => setState(() => _isDarkMode = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Bianco', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('Nero', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(),

        // Vibration Switch
        SwitchListTile(
          title: const Text('Vibrazione Notifiche'),
          subtitle: const Text('Pattern a doppio impulso'),
          value: _vibrationEnabled,
          onChanged: (val) {
            setState(() {
              _vibrationEnabled = val;
            });
          },
          secondary: const Icon(Icons.vibration),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(),

        // Rich Color Board for Accent Color Selection
        const Text(
          'Colore Accento App',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        RichColorBoard(
          selectedColor: _themeColor,
          onColorSelected: (color) {
            setState(() {
              _themeColor = color;
            });
          },
        ),
        const SizedBox(height: 24),

        // Next
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _nextStepSlide,
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SALVA E CONTINUA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                SizedBox(width: 8),
                Icon(Icons.navigate_next, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 6: Interactive Guide / Tutorial ---
  Widget _buildStep6Tutorial(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Benvenuto su Quice!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Interactive tutorial slides PageView
        SizedBox(
          height: 240,
          child: PageView(
            controller: _tutorialPageController,
            onPageChanged: (idx) {
              setState(() {
                _tutorialSlideIndex = idx;
              });
            },
            children: [
              _buildTutorialSlide(
                icon: Icons.chat_rounded,
                title: 'Messaggistica Fulminea',
                description: 'Invia file, messaggi di testo e registrazioni vocali con latenze minime e crittografia end-to-end.',
              ),
              _buildTutorialSlide(
                icon: Icons.archive_outlined,
                title: 'Organizza con Archivio',
                description: 'Tieni in ordine la tua lista chat archiviando le conversazioni meno attive con un semplice swipe a sinistra.',
              ),
              _buildTutorialSlide(
                icon: Icons.lock_outline_rounded,
                title: 'Sicurezza Totale',
                description: 'Firma crittografica delle richieste API e verifica in due passaggi per proteggere l\'accesso alle tue chat.',
              ),
            ],
          ),
        ),

        // Indicator dots for slides
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final active = _tutorialSlideIndex == index;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? _themeColor : Colors.grey.withValues(alpha: 0.5),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // Skip / Next Finish buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _finishSetup,
              child: const Text('SALTA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                if (_tutorialSlideIndex < 2) {
                  _tutorialPageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                } else {
                  _finishSetup();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              child: Text(
                _tutorialSlideIndex == 2 ? 'INIZIA' : 'AVANTI',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGlassy3DIcon(IconData icon, Color accentColor, {double size = 90}) {
    final isDark = _isDarkMode;
    return Container(
      width: size,
      height: size,
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
            color: accentColor.withValues(alpha: isDark ? 0.3 : 0.2),
            blurRadius: 22,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.48,
          color: isDark ? Colors.white : accentColor,
        ),
      ),
    );
  }

  Widget _buildTutorialSlide({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildGlassy3DIcon(icon, _themeColor, size: 96),
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

// Sub-widgets

class _OnboardingFloatingCircle extends StatelessWidget {
  const _OnboardingFloatingCircle({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _AnimatedBubbleNode extends StatefulWidget {
  const _AnimatedBubbleNode({required this.delay, required this.color});
  final int delay;
  final Color color;

  @override
  State<_AnimatedBubbleNode> createState() => _AnimatedBubbleNodeState();
}

class _AnimatedBubbleNodeState extends State<_AnimatedBubbleNode> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _translateY;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _translateY = Tween<double>(begin: 10.0, end: -10.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOut,
      ),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _animController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _translateY,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0.0, _translateY.value),
          child: child,
        );
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}

class _PulsingDoLaterButton extends StatefulWidget {
  const _PulsingDoLaterButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_PulsingDoLaterButton> createState() => _PulsingDoLaterButtonState();
}

class _PulsingDoLaterButtonState extends State<_PulsingDoLaterButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseScale,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseScale.value,
          child: child,
        );
      },
      child: OutlinedButton(
        onPressed: widget.onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: const Text('FAI DOPO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
      ),
    );
  }
}

class _PresetColorNode extends StatelessWidget {
  const _PresetColorNode({required this.color, required this.isSelected, required this.onTap});
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: isSelected ? borderColor : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (color.computeLuminance() > 0.5 ? Colors.black : Colors.white).withValues(alpha: isSelected ? 0.35 : 0.12),
              blurRadius: isSelected ? 8 : 4,
              spreadRadius: isSelected ? 1 : 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.06),
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.24),
                ]
              : [
                  Colors.white.withValues(alpha: 0.76),
                  Colors.white.withValues(alpha: 0.34),
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.12),
                ],
          stops: const [0.0, 0.4, 0.78, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.1),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.03 : 0.22),
            blurRadius: 14,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.2),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.18),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Clippers for transitions

class CircleTransitionClipper extends CustomClipper<Path> {
  CircleTransitionClipper({required this.fraction, required this.center});
  final double fraction;
  final Offset center;

  @override
  Path getClip(Size size) {
    final path = Path();
    final maxRadius = size.width * 1.5;
    final radius = maxRadius * fraction;
    path.addOval(Rect.fromCircle(center: center, radius: radius));
    return path;
  }

  @override
  bool shouldReclip(covariant CircleTransitionClipper oldClipper) => oldClipper.fraction != fraction;
}

class StarTransitionClipper extends CustomClipper<Path> {
  StarTransitionClipper({required this.fraction});
  final double fraction;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (fraction == 0.0) return path;
    if (fraction >= 1.0) {
      path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      return path;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 1.5 * fraction;
    const points = 5;
    const angle = (2 * pi) / points;
    const halfAngle = angle / 2;

    path.moveTo(center.dx, center.dy - maxRadius);

    for (var i = 0; i < points; i++) {
      final currentAngle = i * angle - pi / 2;
      // Outer point
      final x1 = center.dx + maxRadius * cos(currentAngle);
      final y1 = center.dy + maxRadius * sin(currentAngle);

      // Inner point
      final x2 = center.dx + (maxRadius * 0.4) * cos(currentAngle + halfAngle);
      final y2 = center.dy + (maxRadius * 0.4) * sin(currentAngle + halfAngle);

      path.lineTo(x1, y1);
      path.lineTo(x2, y2);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant StarTransitionClipper oldClipper) => oldClipper.fraction != fraction;
}
