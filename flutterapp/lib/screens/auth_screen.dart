import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../services/message_translation_service.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool isLoading = false;
  String _preferredLanguageCode = 'en';
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => isLoading = true);
    try {
      final profile = isLogin
          ? await AuthApi.login(
              email: emailController.text,
              password: passwordController.text,
            )
          : await AuthApi.register(
              name: nameController.text,
              email: emailController.text,
              password: passwordController.text,
              preferredLanguageCode: _preferredLanguageCode,
            );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(profile: profile),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() => isLoading = true);
    try {
      final profile = await AuthApi.guestLogin(
        name: nameController.text.trim().isEmpty ? 'Ospite' : nameController.text.trim(),
        preferredLanguageCode: _preferredLanguageCode,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(profile: profile),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(
                          value: true,
                          label: Semantics(
                            label: 'Modalità accesso',
                            child: const Text('Accesso'),
                          ),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Semantics(
                            label: 'Modalità registrazione',
                            child: const Text('Registrazione'),
                          ),
                        ),
                      ],
                      selected: {isLogin},
                      onSelectionChanged: (selection) {
                        setState(() => isLogin = selection.first);
                      },
                    ),
                    const SizedBox(height: 20),
                    if (!isLogin)
                      TextField(
                        controller: nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nome',
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                    if (!isLogin) const SizedBox(height: 12),
                    if (!isLogin)
                      DropdownButtonFormField<String>(
                        value: _preferredLanguageCode,
                        decoration: const InputDecoration(
                          labelText: 'Lingua app',
                          prefixIcon: Icon(Icons.language),
                        ),
                        items: MessageTranslationService.supportedLanguages()
                            .map(
                              (language) => DropdownMenuItem<String>(
                                value: language.code,
                                child: Text(language.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _preferredLanguageCode = value);
                          }
                        },
                      ),
                    if (!isLogin) const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!isLoading) {
                          _submit();
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        child: isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(isLogin ? 'Accedi' : 'Registrati'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!isLogin)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isLoading ? null : _continueAsGuest,
                          icon: const Icon(Icons.person_outline),
                          label: const Text('Continua come ospite'),
                        ),
                      ),
                    if (!isLogin) const SizedBox(height: 10),
                    Semantics(
                      label:
                          'Informazione: le chiamate API sono collegate al web service.',
                      child: const Text(
                        'Le chiamate API sono collegate al web service.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
