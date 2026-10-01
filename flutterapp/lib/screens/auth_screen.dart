import 'dart:ui';
import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../services/api_exception_handler.dart';
import '../services/message_translation_service.dart';
import 'home_screen.dart';
import '../services/app_preferences.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool isLogin = true;
  bool isLoading = false;
  String _preferredLanguageCode = 'en';
  final formKey = GlobalKey<FormState>();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    
    setState(() => isLoading = true);
    try {
      final phone = phoneController.text.trim().replaceAll(' ', '');
      final password = passwordController.text.trim();
      final session = isLogin
          ? await AuthApi.instance.login(phone: phone, password: password)
          : await AuthApi.instance.register(
              name: nameController.text.trim(),
              phone: phone,
              email: emailController.text.trim().isEmpty
                  ? null
                  : emailController.text.trim(),
              password: password,
              preferredLanguageCode: _preferredLanguageCode,
            );

      // Nessuna password viene conservata: la sessione e' gia' stata
      // stabilita dal server e vive nell'archivio sicuro del dispositivo.
      await AppPreferences.instance.saveUserSession(phone, session.profile);
      final profile = session.profile;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(profile: profile),
        ),
      );
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, error, onRetry: _submit);
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();
    final themeColor = Color(AppPreferences.instance.themeColorValue);

    return Scaffold(
      body: Stack(
        children: [
          // Elegant neutral Crystal UI dynamic gradient background
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
          
          if (canPop)
            Positioned(
              top: 24,
              left: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ),
          
          // Subtle decorative floating circles for glassmorphism contrast
          Positioned(
            top: size.height * 0.15,
            left: size.width * 0.15,
            child: _FloatingCircle(
              size: 150,
              color: Color(AppPreferences.instance.themeColorValue).withValues(alpha: 0.25),
            ),
          ),
          Positioned(
            bottom: size.height * 0.15,
            right: size.width * 0.15,
            child: _FloatingCircle(
              size: 220,
              color: Color(AppPreferences.instance.themeColorValue).withValues(alpha: 0.18),
            ),
          ),

          // Central scrollable card
          Center(
            child: FadeTransition(
              opacity: _fadeController,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.35),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Form(
                            key: formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Floating Animated Hero Logo
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(seconds: 1),
                                  curve: Curves.elasticOut,
                                  builder: (context, value, child) {
                                    return Transform.scale(
                                      scale: value,
                                      child: child,
                                    );
                                  },
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
                                ),
                                const SizedBox(height: 24),
                                
                                // Sliding switcher segmented control
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _TabButton(
                                          title: 'Accedi',
                                          isSelected: isLogin,
                                          onTap: () => setState(() => isLogin = true),
                                        ),
                                      ),
                                      Expanded(
                                        child: _TabButton(
                                          title: 'Registrati',
                                          isSelected: !isLogin,
                                          onTap: () => setState(() => isLogin = false),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 28),

                                // Animated fields switcher
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0.0, 0.1),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: KeyedSubtree(
                                    key: ValueKey<bool>(isLogin),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        if (!isLogin) ...[
                                          _buildTextField(
                                            controller: nameController,
                                            label: 'Nome completo',
                                            icon: Icons.person_rounded,
                                            validator: (val) => val == null || val.trim().isEmpty ? 'Inserisci il tuo nome' : null,
                                          ),
                                          const SizedBox(height: 16),
                                          _buildLanguageDropdown(),
                                          const SizedBox(height: 16),
                                        ],
                                        _buildTextField(
                                          controller: phoneController,
                                          label: 'Numero di telefono',
                                          icon: Icons.phone_rounded,
                                          keyboardType: TextInputType.phone,
                                          validator: (val) {
                                            if (val == null || val.trim().isEmpty) return 'Inserisci il numero di telefono';
                                            if (int.tryParse(val.trim()) == null) return 'Inserisci solo cifre numeriche';
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        if (!isLogin) ...[
                                          _buildTextField(
                                            controller: emailController,
                                            label: 'Indirizzo Email (Opzionale)',
                                            icon: Icons.email_rounded,
                                            keyboardType: TextInputType.emailAddress,
                                            validator: (val) {
                                              if (val != null && val.trim().isNotEmpty && !val.contains('@')) {
                                                return 'Inserisci un\'email valida';
                                              }
                                              return null;
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                        _buildTextField(
                                          controller: passwordController,
                                          label: 'Password',
                                          icon: Icons.lock_rounded,
                                          obscureText: true,
                                          textInputAction: TextInputAction.done,
                                          onFieldSubmitted: (_) => _submit(),
                                          validator: (val) => val == null || val.length < 6 ? 'La password deve avere almeno 6 caratteri' : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),

                                // ELEVATED MAIN SUBMIT BUTTON
                                 SizedBox(
                                   width: double.infinity,
                                   height: 52,
                                   child: ElevatedButton(
                                     onPressed: isLoading ? null : _submit,
                                     style: ElevatedButton.styleFrom(
                                       foregroundColor: themeColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                                       backgroundColor: themeColor,
                                       elevation: 4,
                                       shape: RoundedRectangleBorder(
                                         borderRadius: BorderRadius.circular(16),
                                       ),
                                       shadowColor: themeColor.withValues(alpha: 0.3),
                                     ),
                                     child: isLoading
                                         ? SizedBox(
                                             height: 24,
                                             width: 24,
                                             child: CircularProgressIndicator(
                                               strokeWidth: 2.5,
                                               valueColor: AlwaysStoppedAnimation<Color>(
                                                 themeColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                                               ),
                                             ),
                                           )
                                         : Text(
                                             isLogin ? 'ACCEDI' : 'REGISTRATI',
                                             style: const TextStyle(
                                               fontSize: 16,
                                               fontWeight: FontWeight.bold,
                                               letterSpacing: 0.8,
                                             ),
                                           ),
                                   ),
                                 ),

                                // Semantic information note
                                const Text(
                                  'Connesso in modo sicuro al Web Service',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.8)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white, width: 2),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  Widget _buildLanguageDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonFormField<String>(
      value: _preferredLanguageCode,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      dropdownColor: isDark ? const Color(0xFF161618) : Colors.white,
      decoration: InputDecoration(
        labelText: 'Lingua app preferita',
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        prefixIcon: Icon(Icons.language_rounded, color: Colors.white.withValues(alpha: 0.8)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      items: MessageTranslationService.supportedLanguages()
          .map(
            (language) => DropdownMenuItem<String>(
              value: language.code,
              child: Text(
                language.label,
                style: const TextStyle(color: Colors.white),
              ),
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
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _FloatingCircle extends StatelessWidget {
  const _FloatingCircle({required this.size, required this.color});
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
