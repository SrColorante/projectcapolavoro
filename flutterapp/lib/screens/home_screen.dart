import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_thread.dart';
import '../models/user_profile.dart';

enum _RightPaneView { settings, chat, newChat }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _presetColors = <Color>[
    Color(0xFFDC143C),
    Color(0xFF8B0000),
    Color(0xFF1E88E5),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFFF8F00),
    Color(0xFF37474F),
    Color(0xFF455A64),
    Color(0xFF00897B),
    Color(0xFFFFEEF1),
    Color(0xFFF3E5F5),
  ];

  late final List<ChatThread> chats;
  ChatThread? selectedChat;
  _RightPaneView _rightPaneView = _RightPaneView.settings;

  late final TextEditingController _nicknameController;
  late final TextEditingController _newChatNameController;
  late final TextEditingController _newChatIdController;

  Color _appThemeColor = const Color(0xFFDC143C);
  Color _newChatBackgroundColor = const Color(0xFFFFEEF1);
  Color _newChatBubbleColor = const Color(0xFFDC143C);

  @override
  void initState() {
    super.initState();
    chats = <ChatThread>[
      ChatThread(
        id: ChatThread.generateTenDigitId(),
        title: 'Team Crimson',
        participantId: '1234567891',
        backgroundColorValue: const Color(0xFFFFEEF1).value,
        bubbleColorValue: const Color(0xFFDC143C).value,
        messages: <ChatMessage>[
          const ChatMessage(
            text: 'Benvenuto in Crimson Chat!',
            senderId: '1234567891',
          ),
          ChatMessage(
            text: 'Grazie! Ho appena fatto login.',
            senderId: widget.profile.id,
          ),
        ],
      ),
      ChatThread(
        id: ChatThread.generateTenDigitId(),
        title: 'Supporto',
        participantId: '1234567892',
        messages: const <ChatMessage>[],
      ),
    ];
    _nicknameController = TextEditingController(text: widget.profile.nickname);
    _newChatNameController = TextEditingController();
    _newChatIdController = TextEditingController();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _newChatNameController.dispose();
    _newChatIdController.dispose();
    super.dispose();
  }

  void _openSettings() {
    setState(() {
      selectedChat = null;
      _rightPaneView = _RightPaneView.settings;
    });
  }

  void _openNewChat() {
    setState(() {
      selectedChat = null;
      _rightPaneView = _RightPaneView.newChat;
    });
  }

  void _selectChat(ChatThread chat) {
    setState(() {
      selectedChat = chat;
      _rightPaneView = _RightPaneView.chat;
    });
  }

  void _createChat() {
    final name = _newChatNameController.text.trim();
    final participantId = _newChatIdController.text.trim();

    if (name.isEmpty) {
      _showSnackBar('Inserisci il nome utente');
      return;
    }

    if (!UserProfile.isValidTenDigitId(participantId)) {
      _showSnackBar('L\'ID utente deve essere numerico e di 10 cifre');
      return;
    }

    if (participantId == widget.profile.id) {
      _showSnackBar('Non puoi creare una chat con il tuo stesso ID');
      return;
    }

    final alreadyExists = chats.any((chat) => chat.participantId == participantId);
    if (alreadyExists) {
      _showSnackBar('Esiste già una chat con questo ID utente');
      return;
    }

    final newChat = ChatThread(
      id: ChatThread.generateTenDigitId(),
      title: name,
      participantId: participantId,
      backgroundColorValue: _newChatBackgroundColor.value,
      bubbleColorValue: _newChatBubbleColor.value,
      messages: <ChatMessage>[
        ChatMessage(text: 'Ciao, sono $name 👋', senderId: participantId),
        ChatMessage(
          text: 'Benvenuto! Questa è la tua nuova chat.',
          senderId: widget.profile.id,
        ),
      ],
    );

    setState(() {
      chats.insert(0, newChat);
      selectedChat = newChat;
      _rightPaneView = _RightPaneView.chat;
      _newChatNameController.clear();
      _newChatIdController.clear();
    });
  }

  void _saveSettings() {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      _showSnackBar('Il nickname non può essere vuoto');
      return;
    }
    _showSnackBar('Impostazioni salvate');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildRightPane() {
    if (_rightPaneView == _RightPaneView.newChat) {
      return _NewChatPanel(
        currentUserId: widget.profile.id,
        nameController: _newChatNameController,
        idController: _newChatIdController,
        selectedBackgroundColor: _newChatBackgroundColor,
        selectedBubbleColor: _newChatBubbleColor,
        presetColors: _presetColors,
        onBackgroundColorChanged: (color) {
          setState(() => _newChatBackgroundColor = color);
        },
        onBubbleColorChanged: (color) {
          setState(() => _newChatBubbleColor = color);
        },
        onCreatePressed: _createChat,
      );
    }
    if (_rightPaneView == _RightPaneView.chat && selectedChat != null) {
      return _ChatPanel(chat: selectedChat!, currentUserId: widget.profile.id);
    }
    return _SettingsPanel(
      profile: widget.profile,
      nicknameController: _nicknameController,
      selectedThemeColor: _appThemeColor,
      presetColors: _presetColors,
      onThemeColorChanged: (color) {
        setState(() => _appThemeColor = color);
      },
      onSavePressed: _saveSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFFFDE9EC),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Le tue chat',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Impostazioni',
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings),
                        ),
                        IconButton(
                          tooltip: 'Nuova chat',
                          onPressed: _openNewChat,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
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
                                  leading: CircleAvatar(
                                    backgroundColor: _appThemeColor,
                                    child: const Icon(
                                      Icons.chat_bubble,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(chat.title),
                                  subtitle: Text('ID: ${chat.participantId}'),
                                  onTap: () => _selectChat(chat),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: _buildRightPane(),
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
          const Icon(
            Icons.sentiment_dissatisfied,
            size: 60,
            color: Color(0xFF8B0000),
          ),
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

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.chat, required this.currentUserId});

  final ChatThread chat;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(chat.backgroundColorValue),
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
                final message = chat.messages[index];
                final isSent = message.isSentBy(currentUserId);
                return Align(
                  alignment:
                      isSent ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.45,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(chat.bubbleColorValue),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message.text,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.profile,
    required this.nicknameController,
    required this.selectedThemeColor,
    required this.presetColors,
    required this.onThemeColorChanged,
    required this.onSavePressed,
  });

  final UserProfile profile;
  final TextEditingController nicknameController;
  final Color selectedThemeColor;
  final List<Color> presetColors;
  final ValueChanged<Color> onThemeColorChanged;
  final VoidCallback onSavePressed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Impostazioni',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('Il tuo ID utente'),
              subtitle: Text(
                profile.id,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profilo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nicknameController,
                    decoration: const InputDecoration(
                      labelText: 'Nickname',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Colore principale app',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: selectedThemeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('#${selectedThemeColor.value.toRadixString(16).toUpperCase()}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ColorPalette(
                    colors: presetColors,
                    selectedColor: selectedThemeColor,
                    onColorSelected: onThemeColorChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onSavePressed,
              icon: const Icon(Icons.save),
              label: const Text('Salva impostazioni'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatPanel extends StatelessWidget {
  const _NewChatPanel({
    required this.currentUserId,
    required this.nameController,
    required this.idController,
    required this.selectedBackgroundColor,
    required this.selectedBubbleColor,
    required this.presetColors,
    required this.onBackgroundColorChanged,
    required this.onBubbleColorChanged,
    required this.onCreatePressed,
  });

  final String currentUserId;
  final TextEditingController nameController;
  final TextEditingController idController;
  final Color selectedBackgroundColor;
  final Color selectedBubbleColor;
  final List<Color> presetColors;
  final ValueChanged<Color> onBackgroundColorChanged;
  final ValueChanged<Color> onBubbleColorChanged;
  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nuova chat',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nome utente',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: idController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              labelText: 'ID utente (10 cifre)',
              prefixIcon: Icon(Icons.numbers),
              hintText: '1234567890',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Il tuo ID: $currentUserId',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Colore sfondo chat',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _ColorPalette(
            colors: presetColors,
            selectedColor: selectedBackgroundColor,
            onColorSelected: onBackgroundColorChanged,
          ),
          const SizedBox(height: 16),
          const Text(
            'Colore messaggi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _ColorPalette(
            colors: presetColors,
            selectedColor: selectedBubbleColor,
            onColorSelected: onBubbleColorChanged,
          ),
          const SizedBox(height: 20),
          const Text(
            'Live Preview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selectedBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PreviewMessageBubble(
                  text: 'Ciao! Come stai?',
                  isSent: false,
                  bubbleColor: selectedBubbleColor,
                ),
                const SizedBox(height: 8),
                _PreviewMessageBubble(
                  text: 'Tutto bene, grazie!',
                  isSent: true,
                  bubbleColor: selectedBubbleColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCreatePressed,
              icon: const Icon(Icons.save),
              label: const Text('Crea chat'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMessageBubble extends StatelessWidget {
  const _PreviewMessageBubble({
    required this.text,
    required this.isSent,
    required this.bubbleColor,
  });

  final String text;
  final bool isSent;
  final Color bubbleColor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({
    required this.colors,
    required this.selectedColor,
    required this.onColorSelected,
  });

  final List<Color> colors;
  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        final isSelected = color.value == selectedColor.value;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onColorSelected(color),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? Colors.black : Colors.black26,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        );
      }).toList(growable: false),
    );
  }
}
