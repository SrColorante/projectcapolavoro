import 'package:flutter/material.dart';

void main() {
  runApp(const CrimsonChatApp());
}

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

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFDC143C), Color(0xFF8B0000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white,
              child: Icon(Icons.forum, color: Color(0xFFDC143C), size: 42),
            ),
            SizedBox(height: 16),
            Text(
              'Crimson Chat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool isLoading = false;
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
                            child: Text('Accesso'),
                          ),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Semantics(
                            label: 'Modalità registrazione',
                            child: Text('Registrazione'),
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
                    const Semantics(
                      label:
                          'Informazione: le chiamate API sono placeholder verso un web service.',
                      child: Text(
                        'Le chiamate API sono placeholder verso un web service.',
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final chats = <ChatThread>[
    const ChatThread(
      title: 'Team Crimson',
      messages: [
        'Benvenuto in Crimson Chat!',
        'Questa è una chat di esempio.',
      ],
    ),
    const ChatThread(title: 'Supporto', messages: []),
  ];

  ChatThread? selectedChat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFFFDE9EC),
              child: chats.isEmpty
                  ? const _NoChatsPlaceholder()
                  : ListView.separated(
                      itemCount: chats.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        final isSelected = selectedChat == chat;
                        return Semantics(
                          label: isSelected
                              ? 'Chat ${chat.title}, selezionata'
                              : 'Chat ${chat.title}',
                          child: ListTile(
                            selected: isSelected,
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFDC143C),
                              child:
                                  Icon(Icons.chat_bubble, color: Colors.white),
                            ),
                            title: Text(chat.title),
                            onTap: () => setState(() => selectedChat = chat),
                          ),
                        );
                      },
                    ),
            ),
          ),
          Expanded(
            flex: 5,
            child: selectedChat == null
                ? _ProfilePanel(profile: widget.profile)
                : _ChatPanel(chat: selectedChat!),
          ),
        ],
      ),
    );
  }
}

class _NoChatsPlaceholder extends StatelessWidget {
  const _NoChatsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sentiment_dissatisfied, size: 60, color: Color(0xFF8B0000)),
          SizedBox(height: 8),
          Semantics(
            label: 'emoji stato vuoto',
            child: ExcludeSemantics(
              child: Text('🪰', style: TextStyle(fontSize: 24)),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'niente da mostrare qui',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profilo corrente',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 36,
            backgroundColor: const Color(0xFFDC143C).withOpacity(0.2),
            child: const Icon(Icons.person, size: 36, color: Color(0xFF8B0000)),
          ),
          const SizedBox(height: 16),
          Text('Nome: ${profile.name}'),
          const SizedBox(height: 8),
          Text('Email: ${profile.email}'),
        ],
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.chat});

  final ChatThread chat;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFEEF1),
      child: chat.messages.isEmpty
          ? const Center(
              child: Text(
                'inizia la chat ora :)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: chat.messages.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC143C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    chat.messages[index],
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              },
            ),
    );
  }
}

class AuthApi {
  static const String _defaultUserName = 'Nuovo utente';

  static Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return UserProfile(name: 'Utente', email: email);
  }

  static Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return UserProfile(
      name: name.isEmpty ? _defaultUserName : name,
      email: email,
    );
  }
}

class UserProfile {
  const UserProfile({required this.name, required this.email});

  final String name;
  final String email;
}

class ChatThread {
  const ChatThread({required this.title, required this.messages});

  final String title;
  final List<String> messages;
}
