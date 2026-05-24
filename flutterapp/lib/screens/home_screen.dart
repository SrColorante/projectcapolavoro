import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/chat_api.dart';
import '../models/chat_thread.dart';
import '../models/user_profile.dart';
import '../services/api_exception_handler.dart';
import '../services/app_preferences.dart';
import '../services/message_translation_service.dart';
import '../widgets/message_attachment_preview.dart';
import '../widgets/chat_background.dart';
import 'group_create_screen.dart';
import 'profile_screen.dart';
import '../widgets/user_profile_dialog.dart';

enum _RightPaneView { settings, chat, newChat }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile, this.chatApi});

  final UserProfile profile;
  final ChatApi? chatApi;

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

  List<ChatThread> chats = <ChatThread>[];
  ChatThread? selectedChat;
  _RightPaneView _rightPaneView = _RightPaneView.settings;

  late final ChatApi _chatApi;
  late final TextEditingController _nicknameController;
  late final TextEditingController _newChatNameController;
  late final TextEditingController _newChatIdController;
  late final TextEditingController _messageController;
  late final List<LanguageOption> _languageOptions;

  Color _appThemeColor = const Color(0xFFDC143C);
  Color _newChatBackgroundColor = const Color(0xFFFFEEF1);
  Color _newChatBubbleColor = const Color(0xFFDC143C);
  String _preferredLanguageCode = AppPreferences.defaultLanguageCode;
  bool _isLoadingChats = false;
  bool _isLoadingMessages = false;
  bool _isSendingMessage = false;
  bool _isCreatingChat = false;
  bool _isSavingSettings = false;
  bool _isUploadingFile = false;
  Color _currentChatBgColor = const Color(0xFFFFEEF1);
  Color _currentChatBubbleColor = const Color(0xFFDC143C);
  String? _currentChatBgImagePath;
  bool _currentChatUseDefaultTheme = true;
  bool _notificationsVibrationEnabled = true;
  String? _notificationsRingtonePath;
  late UserProfile _currentProfile;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _chatApi = widget.chatApi ?? ChatApi();
    _nicknameController = TextEditingController(text: _currentProfile.nickname);
    _newChatNameController = TextEditingController();
    _newChatIdController = TextEditingController();
    _messageController = TextEditingController();
    _languageOptions = MessageTranslationService.supportedLanguages();
    _applySavedPreferences();
    _loadChats();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _newChatNameController.dispose();
    _newChatIdController.dispose();
    _messageController.dispose();
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

  Future<void> _openCreateGroupScreen() async {
    final newGroupId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => GroupCreateScreen(currentUserId: _currentProfile.id),
      ),
    );

    if (newGroupId != null && mounted) {
      await _loadChats();
      final matches = chats.where((c) => c.id == newGroupId).toList();
      if (matches.isNotEmpty) {
        await _selectChat(matches.first);
      }
    }
  }

  Future<void> _openEditProfileScreen() async {
    final updatedProfile = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute<UserProfile>(
        builder: (_) => ProfileScreen(profile: _currentProfile),
      ),
    );

    if (updatedProfile != null && mounted) {
      setState(() {
        _currentProfile = updatedProfile;
        _nicknameController.text = updatedProfile.nickname;
      });
    }
  }

  Future<void> _loadChats() async {
    setState(() => _isLoadingChats = true);
    try {
      final loadedChats =
          await _chatApi.fetchChats(userId: _currentProfile.id);
      if (!mounted) return;
      setState(() {
        chats = loadedChats;
        if (selectedChat != null) {
          final matches =
              chats.where((chat) => chat.id == selectedChat!.id).toList();
          selectedChat = matches.isEmpty ? null : matches.first;
        }
      });
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(
          context,
          error,
          onRetry: _loadChats,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingChats = false);
      }
    }
  }

  Future<void> _loadMessages(ChatThread chat) async {
    setState(() => _isLoadingMessages = true);
    try {
      final messages = await _chatApi.fetchMessages(
        userId: _currentProfile.id,
        chatId: chat.id,
      );
      if (!mounted) return;
      _replaceChat(chat, messages);
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(
          context,
          error,
          onRetry: () => _loadMessages(chat),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMessages = false);
      }
    }
  }

  void _replaceChat(ChatThread chat, List<ChatMessage> messages) {
    final index = chats.indexWhere((element) => element.id == chat.id);
    if (index == -1) {
      return;
    }
    final updatedChat = ChatThread(
      id: chat.id,
      title: chat.title,
      participantId: chat.participantId,
      messages: messages,
      backgroundColorValue: chat.backgroundColorValue,
      bubbleColorValue: chat.bubbleColorValue,
    );
    setState(() {
      chats[index] = updatedChat;
      if (selectedChat?.id == updatedChat.id) {
        selectedChat = updatedChat;
      }
    });
  }

  Future<void> _selectChat(ChatThread chat) async {
    setState(() {
      selectedChat = chat;
      _rightPaneView = _RightPaneView.chat;
    });
    await _loadChatCustomSettings(chat.id);
    await _loadMessages(chat);
  }

  Future<void> _loadChatCustomSettings(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('chat_settings_$chatId');
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        setState(() {
          _currentChatBgColor = Color(data['backgroundColor'] ?? 0xFFFFEEF1);
          _currentChatBubbleColor = Color(data['bubbleColor'] ?? 0xFFDC143C);
          _currentChatBgImagePath = data['backgroundImagePath'];
          _currentChatUseDefaultTheme = data['useDefaultTheme'] ?? false;
        });
        return;
      } catch (_) {}
    }
    // Default to app settings
    setState(() {
      _currentChatBgColor = const Color(0xFFFFEEF1);
      _currentChatBubbleColor = Color(AppPreferences.instance.themeColorValue);
      _currentChatBgImagePath = null;
      _currentChatUseDefaultTheme = true;
    });
  }

  Future<void> _saveChatCustomSettings(
    String chatId, {
    required Color bgColor,
    required Color bubbleColor,
    required String? bgImagePath,
    required bool useDefault,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {
      'backgroundColor': bgColor.value,
      'bubbleColor': bubbleColor.value,
      'backgroundImagePath': bgImagePath,
      'useDefaultTheme': useDefault,
    };
    await prefs.setString('chat_settings_$chatId', jsonEncode(data));
    setState(() {
      _currentChatBgColor = bgColor;
      _currentChatBubbleColor = bubbleColor;
      _currentChatBgImagePath = bgImagePath;
      _currentChatUseDefaultTheme = useDefault;
    });
  }

  Future<void> _createChat() async {
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

    if (participantId == _currentProfile.id) {
      _showSnackBar('Non puoi creare una chat con il tuo stesso ID');
      return;
    }

    final existingChat =
        chats.where((chat) => chat.participantId == participantId).toList();
    if (existingChat.isNotEmpty) {
      await _selectChat(existingChat.first);
      _showSnackBar('Esiste già una chat con questo ID utente');
      return;
    }

    setState(() => _isCreatingChat = true);
    try {
      final chatId = await _chatApi.createChat(
        userId: _currentProfile.id,
        targetUserId: participantId,
      );
      final newChat = ChatThread(
        id: chatId,
        title: name,
        participantId: participantId,
        backgroundColorValue: _newChatBackgroundColor.value,
        bubbleColorValue: _newChatBubbleColor.value,
        messages: <ChatMessage>[],
      );

      setState(() {
        chats.insert(0, newChat);
        selectedChat = newChat;
        _rightPaneView = _RightPaneView.chat;
        _newChatNameController.clear();
        _newChatIdController.clear();
      });
      await _loadMessages(newChat);
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(
          context,
          error,
          onRetry: _createChat,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingChat = false);
      }
    }
  }

  Future<void> _applySavedPreferences() async {
    await AppPreferences.instance.load();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _appThemeColor = Color(AppPreferences.instance.themeColorValue);
      _preferredLanguageCode = AppPreferences.instance.preferredLanguageCode;
      _notificationsVibrationEnabled = prefs.getBool('notifications_vibration_enabled') ?? true;
      _notificationsRingtonePath = prefs.getString('notifications_ringtone_path');
    });
  }

  Future<void> _toggleVibration(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_vibration_enabled', val);
    setState(() {
      _notificationsVibrationEnabled = val;
    });
  }

  Future<void> _pickRingtone() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('notifications_ringtone_path', path);
        setState(() {
          _notificationsRingtonePath = path;
        });
        _showSnackBar('Suoneria personalizzata impostata con successo!');
      }
    } catch (_) {
      _showSnackBar('Impossibile selezionare la suoneria.');
    }
  }

  Future<void> _saveSettings() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      _showSnackBar('Il nickname non può essere vuoto');
      return;
    }
    setState(() => _isSavingSettings = true);
    try {
      await AppPreferences.instance.saveSettings(
        themeColorValue: _appThemeColor.value,
        preferredLanguageCode: _preferredLanguageCode,
      );
      final chat = selectedChat;
      if (chat != null) {
        await _loadMessages(chat);
      }
      _showSnackBar('Impostazioni salvate su questo dispositivo');
    } finally {
      if (mounted) {
        setState(() => _isSavingSettings = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final chat = selectedChat;
    final text = _messageController.text.trim();
    if (chat == null || text.isEmpty) {
      return;
    }

    setState(() => _isSendingMessage = true);
    try {
      await _chatApi.sendMessage(
        userId: _currentProfile.id,
        receiverId: chat.participantId,
        text: text,
        chatId: chat.id,
      );
      final updatedMessages = List<ChatMessage>.from(chat.messages)
        ..add(ChatMessage(text: text, senderId: _currentProfile.id));
      _replaceChat(chat, updatedMessages);
      _messageController.clear();
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(
          context,
          error,
          onRetry: _sendMessage,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingMessage = false);
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    final chat = selectedChat;
    if (chat == null) return;

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.single.path == null) return;

      final path = result.files.single.path!;
      final file = File(path);
      final size = await file.length();

      String? adminPassword;
      bool overrideLimit = false;

      // Limit check (50 MB = 52428800 bytes)
      if (size > 52428800) {
        final password = await _showBypassDialog();
        if (password == null) {
          _showSnackBar('Upload annullato: file superiore a 50MB.');
          return;
        }
        adminPassword = password;
        overrideLimit = true;
      }

      setState(() => _isUploadingFile = true);

      // Upload file real binary
      final attachmentData = await _chatApi.uploadFile(
        userId: _currentProfile.id,
        filePath: path,
        adminPassword: adminPassword,
        overrideLimit: overrideLimit,
      );

      final attachmentId = attachmentData['id']?.toString();
      if (attachmentId == null) {
        throw Exception('Errore nel ricevere ID allegato dal server.');
      }

      // Send message with file attachment linked
      await _chatApi.sendMessage(
        userId: _currentProfile.id,
        receiverId: chat.participantId,
        text: 'Allegato: ${attachmentData['file_name']}',
        chatId: chat.id,
        fileAttachmentId: attachmentId,
      );

      // Reload
      await _loadMessages(chat);
      _showSnackBar('File inviato con successo!');
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingFile = false);
      }
    }
  }

  Future<String?> _showBypassDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Bypass Limite 50MB'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Il file selezionato supera il limite di 50MB.\nInserisci la password di amministrazione per forzare l\'upload:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password bypass admin',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('ANNULLA'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('INVIA'),
          ),
        ],
      ),
    );
  }

  void _showCustomisationDialog(ChatThread chat) {
    Color tempBgColor = _currentChatBgColor;
    Color tempBubbleColor = _currentChatBubbleColor;
    String? tempBgImagePath = _currentChatBgImagePath;
    bool tempUseDefault = _currentChatUseDefaultTheme;

    final imageController = TextEditingController(text: tempBgImagePath);

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Personalizza questa Chat'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Usa tema predefinito'),
                  value: tempUseDefault,
                  onChanged: (val) {
                    setDialogState(() {
                      tempUseDefault = val;
                      if (val) {
                        tempBgColor = const Color(0xFFFFEEF1);
                        tempBubbleColor = Color(AppPreferences.instance.themeColorValue);
                        tempBgImagePath = null;
                        imageController.clear();
                      }
                    });
                  },
                ),
                if (!tempUseDefault) ...[
                  const Divider(),
                  const Text('Colore sfondo', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _ColorPalette(
                    colors: _presetColors,
                    selectedColor: tempBgColor,
                    onColorSelected: (color) => setDialogState(() => tempBgColor = color),
                  ),
                  const SizedBox(height: 16),
                  const Text('Colore messaggi', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _ColorPalette(
                    colors: _presetColors,
                    selectedColor: tempBubbleColor,
                    onColorSelected: (color) => setDialogState(() => tempBubbleColor = color),
                  ),
                  const SizedBox(height: 16),
                  const Text('Immagine di sfondo (URL o asset)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: imageController,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/image.jpg o assets/bg.jpg',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => tempBgImagePath = val,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ANNULLA'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _saveChatCustomSettings(
                  chat.id,
                  bgColor: tempBgColor,
                  bubbleColor: tempBubbleColor,
                  bgImagePath: tempBgImagePath,
                  useDefault: tempUseDefault,
                );
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('SALVA'),
            ),
          ],
        ),
      ),
    );
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
        isCreating: _isCreatingChat,
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
      return _ChatPanel(
        chat: selectedChat!,
        currentUserId: _currentProfile.id,
        isLoading: _isLoadingMessages,
        isSending: _isSendingMessage,
        isUploading: _isUploadingFile,
        messageController: _messageController,
        onSendPressed: _sendMessage,
        onAttachPressed: _pickAndSendFile,
        customBgColor: _currentChatBgColor,
        customBubbleColor: _currentChatBubbleColor,
        customBgImagePath: _currentChatBgImagePath,
        customUseDefaultTheme: _currentChatUseDefaultTheme,
        onCustomisePressed: () => _showCustomisationDialog(selectedChat!),
      );
    }
    return _SettingsPanel(
      profile: _currentProfile,
      nicknameController: _nicknameController,
      selectedThemeColor: _appThemeColor,
      selectedLanguageCode: _preferredLanguageCode,
      supportedLanguages: _languageOptions,
      presetColors: _presetColors,
      onThemeColorChanged: (color) {
        setState(() => _appThemeColor = color);
      },
      onLanguageChanged: (languageCode) {
        setState(() => _preferredLanguageCode = languageCode);
      },
      isSaving: _isSavingSettings,
      onSavePressed: _saveSettings,
      vibrationEnabled: _notificationsVibrationEnabled,
      onVibrationToggled: _toggleVibration,
      ringtonePath: _notificationsRingtonePath,
      onPickRingtone: _pickRingtone,
      onEditProfilePressed: _openEditProfileScreen,
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
                          tooltip: 'Nuovo gruppo',
                          onPressed: _openCreateGroupScreen,
                          icon: const Icon(Icons.group_add_outlined),
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
                    child: _isLoadingChats
                        ? const Center(child: CircularProgressIndicator())
                        : chats.isEmpty
                            ? const _NoChatsPlaceholder()
                            : ListView.separated(
                                itemCount: chats.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
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
  const _ChatPanel({
    required this.chat,
    required this.currentUserId,
    required this.isLoading,
    required this.isSending,
    required this.isUploading,
    required this.messageController,
    required this.onSendPressed,
    required this.onAttachPressed,
    required this.customBgColor,
    required this.customBubbleColor,
    required this.customBgImagePath,
    required this.customUseDefaultTheme,
    required this.onCustomisePressed,
  });

  final ChatThread chat;
  final String currentUserId;
  final bool isLoading;
  final bool isSending;
  final bool isUploading;
  final TextEditingController messageController;
  final VoidCallback onSendPressed;
  final VoidCallback onAttachPressed;
  final Color customBgColor;
  final Color customBubbleColor;
  final String? customBgImagePath;
  final bool customUseDefaultTheme;
  final VoidCallback onCustomisePressed;

  String _getSenderName(String senderId) {
    for (final member in chat.members) {
      if (member is Map) {
        final id = member['IDutente']?.toString();
        if (id == senderId) {
          final nick = member['nickname']?.toString();
          if (nick != null && nick.isNotEmpty) {
            return nick;
          }
          final name = member['nome']?.toString();
          if (name != null && name.isNotEmpty) {
            return name;
          }
        }
      }
    }
    return 'Utente $senderId';
  }

  @override
  Widget build(BuildContext context) {
    final resolvedBubbleColor = customUseDefaultTheme 
        ? Color(chat.bubbleColorValue) 
        : customBubbleColor;

    return ChatBackground(
      backgroundColor: customBgColor,
      backgroundImagePath: customBgImagePath,
      useDefaultTheme: customUseDefaultTheme,
      child: Column(
        children: [
          // Sleek visual top header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              border: const Border(bottom: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (!chat.isGroup) {
                      showDialog<void>(
                        context: context,
                        builder: (context) => UserProfileDialog(userId: chat.participantId),
                      );
                    }
                  },
                  child: MouseRegion(
                    cursor: chat.isGroup ? SystemMouseCursors.basic : SystemMouseCursors.click,
                    child: CircleAvatar(
                      backgroundColor: resolvedBubbleColor,
                      child: Text(
                        chat.isGroup 
                            ? (chat.title.isNotEmpty ? chat.title[0].toUpperCase() : 'G')
                            : (chat.title.length > 5 ? chat.title.substring(5, 6).toUpperCase() : 'U'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        chat.isGroup ? '${chat.members.length} partecipanti' : 'ID: ${chat.participantId}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Personalizza sfondo e colori',
                  icon: const Icon(Icons.palette_rounded, color: Colors.black87),
                  onPressed: onCustomisePressed,
                ),
              ],
            ),
          ),
          if (isLoading || isUploading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
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
                            color: resolvedBubbleColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (chat.isGroup && !isSent) ...[
                                GestureDetector(
                                  onTap: () {
                                    showDialog<void>(
                                      context: context,
                                      builder: (context) => UserProfileDialog(userId: message.senderId),
                                    );
                                  },
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Text(
                                      _getSenderName(message.senderId),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline, // adds premium clickability hint
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              if (message.hasAttachment) ...[
                                MessageAttachmentPreview(
                                  previewType: message.previewType ?? 'file',
                                  fileName: message.fileName ?? 'allegato',
                                  mimeType: message.mimeType ?? 'application/octet-stream',
                                  sourceUrl: message.sourceUrl ?? '',
                                  previewPayload: message.previewPayload,
                                ),
                                const SizedBox(height: 6),
                              ],
                              Text(
                                message.text,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Seleziona file da allegare',
                    icon: const Icon(Icons.attach_file),
                    onPressed: isUploading ? null : onAttachPressed,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSendPressed(),
                      decoration: const InputDecoration(
                        hintText: 'Scrivi un messaggio...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Invia messaggio',
                    onPressed: isSending ? null : onSendPressed,
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.profile,
    required this.nicknameController,
    required this.selectedThemeColor,
    required this.selectedLanguageCode,
    required this.supportedLanguages,
    required this.presetColors,
    required this.onThemeColorChanged,
    required this.onLanguageChanged,
    required this.isSaving,
    required this.onSavePressed,
    required this.vibrationEnabled,
    required this.onVibrationToggled,
    required this.ringtonePath,
    required this.onPickRingtone,
    required this.onEditProfilePressed,
  });

  final UserProfile profile;
  final TextEditingController nicknameController;
  final Color selectedThemeColor;
  final String selectedLanguageCode;
  final List<LanguageOption> supportedLanguages;
  final List<Color> presetColors;
  final ValueChanged<Color> onThemeColorChanged;
  final ValueChanged<String> onLanguageChanged;
  final bool isSaving;
  final Future<void> Function() onSavePressed;
  
  final bool vibrationEnabled;
  final ValueChanged<bool> onVibrationToggled;
  final String? ringtonePath;
  final VoidCallback onPickRingtone;
  final VoidCallback onEditProfilePressed;

  @override
  Widget build(BuildContext context) {
    final ringtoneName = ringtonePath != null 
        ? ringtonePath!.split('/').last.split('\\').last 
        : 'Suoneria di sistema predefinita';

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
                    'Lingua dei messaggi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedLanguageCode,
                    decoration: const InputDecoration(
                      labelText: 'Lingua preferita',
                      prefixIcon: Icon(Icons.language),
                    ),
                    items: supportedLanguages
                        .map(
                          (language) => DropdownMenuItem<String>(
                            value: language.code,
                            child: Text(language.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        onLanguageChanged(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    MessageTranslationService.supportsRuntimeTranslationOnCurrentPlatform
                        ? 'I messaggi vengono tradotti sul dispositivo prima dell\'invio e dopo la ricezione.'
                        : 'La traduzione automatica on-device è disponibile su Android/iOS. Su questa piattaforma i messaggi restano in inglese se la traduzione non è disponibile.',
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onEditProfilePressed,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Completa profilo (Foto, Bio, Audio Bio)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // NEW Notification and Alerts Customization Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notifiche & Avvisi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Attiva Vibrazione'),
                    subtitle: const Text('Pattern a doppio impulso all\'arrivo dei messaggi'),
                    value: vibrationEnabled,
                    onChanged: onVibrationToggled,
                    secondary: const Icon(Icons.vibration),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.audiotrack_rounded),
                    title: const Text('Suoneria personalizzata'),
                    subtitle: Text(
                      ringtoneName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: ElevatedButton(
                      onPressed: onPickRingtone,
                      child: const Text('Scegli'),
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
              onPressed: isSaving ? null : onSavePressed,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
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
    required this.isCreating,
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
  final bool isCreating;
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
              onPressed: isCreating ? null : onCreatePressed,
              icon: isCreating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(isCreating ? 'Creazione...' : 'Crea chat'),
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
