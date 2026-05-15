import 'package:flutter/material.dart';

import '../models/chat_thread.dart';
import '../models/user_profile.dart';

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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sentiment_dissatisfied,
              size: 60, color: Color(0xFF8B0000)),
          const SizedBox(height: 8),
          Semantics(
            label: 'emoji stato vuoto',
            child: const ExcludeSemantics(
              child: Text('🪰', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
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
