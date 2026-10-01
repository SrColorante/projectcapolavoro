import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/chat_api.dart';
import '../api/auth_api.dart';
import '../models/chat_thread.dart';
import '../models/user_profile.dart';
import '../services/chat_service.dart';
import '../services/api_exception_handler.dart';
import '../services/app_preferences.dart';
import '../services/message_translation_service.dart';
import '../widgets/message_attachment_preview.dart';
import '../widgets/chat_background.dart';
import 'group_create_screen.dart';
import 'profile_screen.dart';
import '../widgets/rich_color_board.dart';
import 'onboarding_wizard.dart';
import '../widgets/user_profile_dialog.dart';
import 'mobile_chat_screen.dart';
import 'mobile_settings_screen.dart';
import 'privacy_settings_screen.dart';

class SelectedFile {
  final String path;
  final String name;
  final int size;
  final bool isImage;
  final bool isCode;
  SelectedFile({required this.path, required this.name, required this.size, required this.isImage, this.isCode = false});
}

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
  late final ChatService _chatService;
  late final TextEditingController _nicknameController;
  late final TextEditingController _newChatNameController;
  late final TextEditingController _newChatIdController;
  late final TextEditingController _messageController;
  late final List<LanguageOption> _languageOptions;

  Color _appThemeColor = const Color(0xFF1E1E1E);
  Color _appBackgroundColor = const Color(0xFFFFFFFF);
  String? _appBackgroundImagePath;
  Color _newChatBackgroundColor = const Color(0xFFFFFFFF);
  Color _newChatBubbleColor = const Color(0xFF1E1E1E);
  String? _selectedFilePath;
  String? _selectedFileName;
  int? _selectedFileSize;
  bool _selectedFileIsImage = false;
  String _preferredLanguageCode = AppPreferences.defaultLanguageCode;
  bool _isLoadingChats = false;
  bool _isLoadingMessages = false;
  bool _isSendingMessage = false;
  bool _isCreatingChat = false;
  bool _isSavingSettings = false;
  bool _isUploadingFile = false;
  Color _currentChatBgColor = const Color(0xFFFFFFFF);
  Color _currentChatBubbleColor = const Color(0xFF1E1E1E);
  String? _currentChatBgImagePath;
  bool _currentChatUseDefaultTheme = true;
  bool _notificationsVibrationEnabled = true;
  String? _notificationsRingtonePath;
  late UserProfile _currentProfile;
  Set<String> _archivedChatIds = <String>{};
  bool _showArchivedOnly = false;
  Timer? _silentPollTimer;
  bool _selectedFileIsCode = false;
  Timer? _typingDebounceTimer;
  String _lastSentTypingStatus = 'idle';
  Duration _pollInterval = const Duration(seconds: 8);
  Timer? _activityCooldownTimer;
  bool _isRecording = false;
  final Map<String, List<ChatMessage>> _sessionMessageCache = <String, List<ChatMessage>>{};
  bool _sendOnEnter = true;

  // Notifiers for reactive mobile screens
  final selectedChatNotifier = ValueNotifier<ChatThread?>(null);
  final isLoadingMessagesNotifier = ValueNotifier<bool>(false);
  final isSendingMessageNotifier = ValueNotifier<bool>(false);
  final isUploadingFileNotifier = ValueNotifier<bool>(false);
  final selectedFileNotifier = ValueNotifier<SelectedFile?>(null);

  final appThemeColorNotifier = ValueNotifier<Color>(const Color(0xFF1E1E1E));
  final appBackgroundColorNotifier = ValueNotifier<Color>(const Color(0xFFFFFFFF));
  final appBackgroundImageNotifier = ValueNotifier<String?>(null);
  final preferredLanguageCodeNotifier = ValueNotifier<String>(AppPreferences.defaultLanguageCode);
  final isSavingSettingsNotifier = ValueNotifier<bool>(false);
  final notificationsVibrationNotifier = ValueNotifier<bool>(true);
  final notificationsRingtoneNotifier = ValueNotifier<String?>(null);
  late final ValueNotifier<UserProfile> currentProfileNotifier;

  final currentChatBgColorNotifier = ValueNotifier<Color>(const Color(0xFFFFFFFF));
  final currentChatBubbleColorNotifier = ValueNotifier<Color>(const Color(0xFF1E1E1E));
  final currentChatBgImagePathNotifier = ValueNotifier<String?>(null);
  final currentChatUseDefaultThemeNotifier = ValueNotifier<bool>(true);
  final activeTypingUsersNotifier = ValueNotifier<List<dynamic>>([]);

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
      isLoadingMessagesNotifier.value = _isLoadingMessages;
      isSendingMessageNotifier.value = _isSendingMessage;
      isUploadingFileNotifier.value = _isUploadingFile;
      if (_selectedFilePath != null) {
        selectedFileNotifier.value = SelectedFile(
          path: _selectedFilePath!,
          name: _selectedFileName ?? 'file',
          size: _selectedFileSize ?? 0,
          isImage: _selectedFileIsImage,
          isCode: _selectedFileIsCode,
        );
      } else {
        selectedFileNotifier.value = null;
      }
      appThemeColorNotifier.value = _appThemeColor;
      appBackgroundColorNotifier.value = _appBackgroundColor;
      appBackgroundImageNotifier.value = _appBackgroundImagePath;
      preferredLanguageCodeNotifier.value = _preferredLanguageCode;
      isSavingSettingsNotifier.value = _isSavingSettings;
      notificationsVibrationNotifier.value = _notificationsVibrationEnabled;
      notificationsRingtoneNotifier.value = _notificationsRingtonePath;
      currentProfileNotifier.value = _currentProfile;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    currentProfileNotifier = ValueNotifier<UserProfile>(_currentProfile);
    _chatApi = widget.chatApi ?? ChatApi();
    _chatService = ChatService(
      wsUrl: _resolveWsUrl(),
      userId: _currentProfile.id,
      username: _currentProfile.nickname,
    );
    _chatService.addListener(_onChatServiceUpdate);
    _nicknameController = TextEditingController(text: _currentProfile.nickname);
    _newChatNameController = TextEditingController();
    _newChatIdController = TextEditingController();
    _messageController = TextEditingController();
    _languageOptions = MessageTranslationService.supportedLanguages();
    _applySavedPreferences();
    _loadChats();
    // keep HTTP polling as fallback; primary real-time handled by WebSocket ChatService
    _messageController.addListener(_onMessageTextChanged);
  }

  String _resolveWsUrl() {
    var base = AuthApi.baseUrl;
    if (base.startsWith('https://')) base = base.replaceFirst('https://', 'wss://');
    else if (base.startsWith('http://')) base = base.replaceFirst('http://', 'ws://');
    // default to port 8080 if not explicit
    if (!base.contains(':8080')) base = base.replaceAll(RegExp(r'(/index.php)?$'), '') + ':8080';
    return base;
  }

  void _onChatServiceUpdate() {
    if (selectedChat == null) return;
    if (_chatService.currentRoomId != selectedChat!.id) return;
    final msgs = _chatService.messages;
    if (msgs.isNotEmpty) {
      _sessionMessageCache[selectedChat!.id] = List<ChatMessage>.from(msgs);
      _replaceChat(selectedChat!, msgs);
    }
    // typing users
    final typingUsers = _chatService.typingUsers.values.map((t) => {'user_id': t.userId, 'status': t.status, 'nickname': t.username, 'nome': t.username}).toList();
    if (!_typingUsersMatch(activeTypingUsersNotifier.value, typingUsers)) {
      activeTypingUsersNotifier.value = typingUsers;
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageTextChanged);
    _typingDebounceTimer?.cancel();
    _silentPollTimer?.cancel();
    _chatService.removeListener(_onChatServiceUpdate);
    _chatService.dispose();
    _nicknameController.dispose();
    _newChatNameController.dispose();
    _newChatIdController.dispose();
    _messageController.dispose();
    
    selectedChatNotifier.dispose();
    isLoadingMessagesNotifier.dispose();
    isSendingMessageNotifier.dispose();
    isUploadingFileNotifier.dispose();
    selectedFileNotifier.dispose();
    appThemeColorNotifier.dispose();
    appBackgroundColorNotifier.dispose();
    preferredLanguageCodeNotifier.dispose();
    isSavingSettingsNotifier.dispose();
    notificationsVibrationNotifier.dispose();
    notificationsRingtoneNotifier.dispose();
    currentProfileNotifier.dispose();
    currentChatBgColorNotifier.dispose();
    currentChatBubbleColorNotifier.dispose();
    currentChatBgImagePathNotifier.dispose();
    currentChatUseDefaultThemeNotifier.dispose();
    activeTypingUsersNotifier.dispose();

    super.dispose();
  }

  void _onMessageTextChanged() {
    final chat = selectedChat;
    if (chat == null) return;

    final text = _messageController.text;
    final newStatus = text.isNotEmpty ? 'typing' : 'idle';

    if (newStatus != _lastSentTypingStatus) {
      _lastSentTypingStatus = newStatus;
      _chatApi.updateTypingStatus(
        userId: _currentProfile.id,
        chatId: chat.id,
        status: newStatus,
      );
    }

    if (newStatus == 'typing') {
      _bumpActivity();
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(seconds: 4), () {
        if (_lastSentTypingStatus == 'typing' && mounted) {
          _lastSentTypingStatus = 'idle';
          _chatApi.updateTypingStatus(
            userId: _currentProfile.id,
            chatId: chat.id,
            status: 'idle',
          );
        }
      });
    }
  }

  void _bumpActivity() {
    _pollInterval = const Duration(seconds: 2);
    _activityCooldownTimer?.cancel();
    _activityCooldownTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) {
        _pollInterval = const Duration(seconds: 8);
        _restartSilentPolling();
      }
    });
  }

  void _restartSilentPolling() {
    _silentPollTimer?.cancel();
    _startSilentPolling();
  }

  void _startSilentPolling() {
    _silentPollTimer = Timer(_pollInterval, () async {
      if (!mounted) return;
      try {
        final loadedChats = await _chatApi.fetchChats(userId: _currentProfile.id);
        if (!mounted) return;

        final hydratedChats = loadedChats.map(_hydrateChatFromSession).toList(growable: false);

        // Aggiorna la lista solo se è cambiata
        final currentIds = chats.map((c) => c.id).toSet();
        final newIds = hydratedChats.map((c) => c.id).toSet();

        bool isChanged = currentIds.length != newIds.length || !currentIds.containsAll(newIds);
        if (!isChanged) {
          // Check if any chat has new messages (by comparing message count or last message content)
          for (final newChat in hydratedChats) {
            final oldChat = chats.where((c) => c.id == newChat.id).toList();
            if (oldChat.isNotEmpty) {
              final oc = oldChat.first;
              if (oc.messages.length != newChat.messages.length ||
                  (oc.messages.isNotEmpty && newChat.messages.isNotEmpty &&
                   oc.messages.last.text != newChat.messages.last.text)) {
                isChanged = true;
                break;
              }
            }
          }
        }

        if (isChanged) {
          setState(() {
            // Preserva self-chat se presente
            final hasSelfChat = hydratedChats.any((c) => !c.isGroup && c.participantId == _currentProfile.id);
            final finalChats = List<ChatThread>.from(hydratedChats);
            if (!hasSelfChat) {
              final existingSelf = chats.where((c) => !c.isGroup && c.participantId == _currentProfile.id).toList();
              if (existingSelf.isNotEmpty) {
                finalChats.insert(0, existingSelf.first);
              }
            }
            chats = finalChats;

            // Se la chat selezionata ha nuovi messaggi, aggiorna anche la selezione
            if (selectedChat != null) {
              final updatedSelected = chats.where((c) => c.id == selectedChat!.id).toList();
              if (updatedSelected.isNotEmpty) {
                selectedChat = updatedSelected.first;
                selectedChatNotifier.value = selectedChat;
              }
            }
          });
        }

        // Aggiorna messaggi della chat selezionata
        final chat = selectedChat;
        if (chat != null) {
          final result = await _chatApi.fetchMessages(
            userId: _currentProfile.id,
            chatId: chat.id,
          );
          if (!mounted) return;

          if (result.typingUsers.isNotEmpty) {
            _bumpActivity();
          }

          if (!_typingUsersMatch(activeTypingUsersNotifier.value, result.typingUsers)) {
            activeTypingUsersNotifier.value = List<dynamic>.from(result.typingUsers);
          }

          _replaceChat(chat, result.messages);
        }
      } catch (_) {
        // Silenzioso: nessun errore mostrato all'utente
      }
      if (mounted) _startSilentPolling();
    });
  }

  ChatThread _hydrateChatFromSession(ChatThread chat) {
    final cachedMessages = _sessionMessageCache[chat.id];
    final mergedMessages = cachedMessages == null || cachedMessages.isEmpty
        ? chat.messages
        : _mergeMessageLists(cachedMessages, chat.messages);

    _sessionMessageCache[chat.id] = List<ChatMessage>.from(mergedMessages);
    return ChatThread(
      id: chat.id,
      title: chat.title,
      participantId: chat.participantId,
      messages: mergedMessages,
      isGroup: chat.isGroup,
      createdBy: chat.createdBy,
      avatarUrl: chat.avatarUrl,
      members: chat.members,
      backgroundColorValue: chat.backgroundColorValue,
      bubbleColorValue: chat.bubbleColorValue,
      backgroundImagePath: chat.backgroundImagePath,
      useDefaultTheme: chat.useDefaultTheme,
    );
  }

  List<ChatMessage> _mergeMessageLists(List<ChatMessage> currentMsgs, List<ChatMessage> remoteMessages) {
    if (currentMsgs.isEmpty && remoteMessages.isEmpty) {
      return currentMsgs;
    }

    if (remoteMessages.isEmpty) {
      return currentMsgs;
    }

    if (currentMsgs.isEmpty) {
      return remoteMessages;
    }

    if (remoteMessages.length <= currentMsgs.length) {
      final offset = currentMsgs.length - remoteMessages.length;
      var tailMatches = true;
      for (var i = 0; i < remoteMessages.length; i++) {
        if (_messageKey(currentMsgs[offset + i]) != _messageKey(remoteMessages[i])) {
          tailMatches = false;
          break;
        }
      }
      if (tailMatches) {
        var changed = false;
        final merged = List<ChatMessage>.from(currentMsgs);
        for (var i = 0; i < remoteMessages.length; i++) {
          final currentIndex = offset + i;
          final local = currentMsgs[currentIndex];
          final remote = remoteMessages[i];
          if (!_messagesMatch(local, remote)) {
            merged[currentIndex] = remote;
            changed = true;
          }
        }
        return changed ? merged : currentMsgs;
      }
    }

    final localMap = <String, ChatMessage>{};
    for (final message in currentMsgs) {
      localMap[_messageKey(message)] = message;
    }

    final remoteKeys = <String>{};
    final merged = <ChatMessage>[];
    var changed = false;

    for (final remote in remoteMessages) {
      final key = _messageKey(remote);
      remoteKeys.add(key);
      final local = localMap[key];
      if (local != null && _messagesMatch(local, remote)) {
        merged.add(local);
      } else {
        changed = true;
        merged.add(remote);
      }
    }

    for (final local in currentMsgs) {
      final key = _messageKey(local);
      if (!remoteKeys.contains(key)) {
        changed = true;
        merged.add(local);
      }
    }

    return changed ? merged : currentMsgs;
  }

  bool _messagesMatch(ChatMessage local, ChatMessage remote) {
    return local.id == remote.id &&
        local.text == remote.text &&
        local.senderId == remote.senderId &&
        local.canonicalText == remote.canonicalText &&
        local.fileAttachmentId == remote.fileAttachmentId &&
        local.fileName == remote.fileName &&
        local.mimeType == remote.mimeType &&
        local.sourceUrl == remote.sourceUrl &&
        local.previewType == remote.previewType &&
        local.previewPayload.toString() == remote.previewPayload.toString() &&
        local.status == remote.status &&
        local.timestamp?.toIso8601String() == remote.timestamp?.toIso8601String();
  }

  bool _typingUsersMatch(List<dynamic> currentTyping, List<dynamic> newTyping) {
    if (currentTyping.length != newTyping.length) {
      return false;
    }
    for (var i = 0; i < currentTyping.length; i++) {
      final a = currentTyping[i] is Map
          ? Map<String, dynamic>.from(currentTyping[i] as Map)
          : <String, dynamic>{};
      final b = newTyping[i] is Map
          ? Map<String, dynamic>.from(newTyping[i] as Map)
          : <String, dynamic>{};
      if (a['user_id']?.toString() != b['user_id']?.toString() ||
          a['status']?.toString() != b['status']?.toString() ||
          a['nickname']?.toString() != b['nickname']?.toString() ||
          a['nome']?.toString() != b['nome']?.toString()) {
        return false;
      }
    }
    return true;
  }

  void _openSettings() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileSettingsScreen(
            profileNotifier: currentProfileNotifier,
            nicknameController: _nicknameController,
            themeColorNotifier: appThemeColorNotifier,
            backgroundColorNotifier: appBackgroundColorNotifier,
            backgroundImageNotifier: appBackgroundImageNotifier,
            languageNotifier: preferredLanguageCodeNotifier,
            supportedLanguages: _languageOptions,
            presetColors: _presetColors,
            onThemeColorChanged: (color) {
              setState(() {
                _appThemeColor = color;
              });
            },
            onBackgroundColorChanged: (color) {
              setState(() {
                _appBackgroundColor = color;
              });
            },
            onPickBackgroundImage: _pickAppBackgroundImage,
            onClearBackgroundImage: _clearAppBackgroundImage,
            onBackgroundImageChanged: (path) {
              setState(() {
                _appBackgroundImagePath = path;
              });
            },
            onLanguageChanged: (languageCode) {
              setState(() {
                _preferredLanguageCode = languageCode;
              });
            },
            isSavingNotifier: isSavingSettingsNotifier,
            onSavePressed: _saveSettings,
            vibrationNotifier: notificationsVibrationNotifier,
            onVibrationToggled: _toggleVibration,
            ringtoneNotifier: notificationsRingtoneNotifier,
            onPickRingtone: _pickRingtone,
            onEditProfilePressed: _openEditProfileScreen,
            onLogoutPressed: _logout,
          ),
        ),
      );
    } else {
      setState(() {
        selectedChat = null;
        _rightPaneView = _RightPaneView.settings;
      });
    }
  }

  void _openNewChat() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF101012) : const Color(0xFFFFFFFF),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: NewChatPanel(
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
                onCreatePressed: () async {
                  await _createChat();
                  // `context` qui e' quello del bottom sheet, non dello State:
                  // va controllato lui, non il `mounted` esterno.
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          );
        },
      );
    } else {
      setState(() {
        selectedChat = null;
        _rightPaneView = _RightPaneView.newChat;
      });
    }
  }

  Future<void> _openCreateGroupScreen() async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    String? newGroupId;

    if (isMobile) {
      newGroupId = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF101012) : const Color(0xFFFFFFFF),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              child: GroupCreateScreen(
                currentUserId: _currentProfile.id,
                existingChats: chats,
              ),
            ),
          );
        },
      );
    } else {
      newGroupId = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => GroupCreateScreen(
            currentUserId: _currentProfile.id,
            existingChats: chats,
          ),
        ),
      );
    }

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
      await AppPreferences.instance.saveUserProfile(updatedProfile);
    }
  }

  Future<void> _loadChats() async {
    setState(() => _isLoadingChats = true);
    try {
      final loadedChats =
          await _chatApi.fetchChats(userId: _currentProfile.id);
      if (!mounted) return;

      final hydratedChats = loadedChats.map(_hydrateChatFromSession).toList(growable: false);

      final hasSelfChat = hydratedChats.any((c) => !c.isGroup && c.participantId == _currentProfile.id);
      final List<ChatThread> finalChats = List<ChatThread>.from(hydratedChats);

      if (!hasSelfChat) {
        try {
          final selfChatId = await _chatApi.createChat(
            userId: _currentProfile.id,
            targetUserId: _currentProfile.id,
          );
          final selfChat = ChatThread(
            id: selfChatId,
            title: 'Note personali (Tu)',
            participantId: _currentProfile.id,
            messages: <ChatMessage>[],
          );
          finalChats.insert(0, selfChat);
        } catch (_) {
          final localSelfId = ChatThread.generateTenDigitId();
          final selfChat = ChatThread(
            id: localSelfId,
            title: 'Note personali (Tu)',
            participantId: _currentProfile.id,
            messages: <ChatMessage>[],
          );
          finalChats.insert(0, selfChat);
        }
      }

      setState(() {
        chats = finalChats;
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
      final result = await _chatApi.fetchMessages(
        userId: _currentProfile.id,
        chatId: chat.id,
      );
      if (!mounted) return;
      if (!_typingUsersMatch(activeTypingUsersNotifier.value, result.typingUsers)) {
        activeTypingUsersNotifier.value = List<dynamic>.from(result.typingUsers);
      }
      _sessionMessageCache[chat.id] = List<ChatMessage>.from(result.messages);
      _replaceChat(chat, result.messages);
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

  String _messageKey(ChatMessage m) => m.id ?? '${m.senderId}_${m.text.hashCode}_${m.timestamp?.toIso8601String() ?? ''}';

  void _replaceChat(ChatThread chat, List<ChatMessage> remoteMessages) {
    final index = chats.indexWhere((element) => element.id == chat.id);
    if (index == -1) return;

    final currentMsgs = chats[index].messages;
    if (currentMsgs.isEmpty && remoteMessages.isEmpty) return;

    // Merge intelligente: preserva istanze locali per evitare ricaricamento media
    final localMap = <String, ChatMessage>{};
    for (final m in currentMsgs) {
      localMap[_messageKey(m)] = m;
    }

    bool changed = false;
    final merged = <ChatMessage>[];
    for (final remote in remoteMessages) {
      final key = _messageKey(remote);
      final local = localMap[key];
      if (local != null) {
        if (local.status != remote.status ||
            local.text != remote.text ||
            local.fileName != remote.fileName ||
            local.sourceUrl != remote.sourceUrl ||
            local.previewType != remote.previewType ||
            local.previewPayload.toString() != remote.previewPayload.toString()) {
          changed = true;
          merged.add(remote);
        } else {
          merged.add(local);
        }
      } else {
        changed = true;
        merged.add(remote);
      }
    }

    if (currentMsgs.length != remoteMessages.length) {
      changed = true;
    }

    if (!changed) return;

    final updatedChat = ChatThread(
      id: chat.id,
      title: chat.title,
      participantId: chat.participantId,
      messages: merged,
      isGroup: chat.isGroup,
      createdBy: chat.createdBy,
      avatarUrl: chat.avatarUrl,
      members: chat.members,
      backgroundColorValue: chat.backgroundColorValue,
      bubbleColorValue: chat.bubbleColorValue,
      backgroundImagePath: chat.backgroundImagePath,
      useDefaultTheme: chat.useDefaultTheme,
    );
    _sessionMessageCache[chat.id] = List<ChatMessage>.from(merged);
    setState(() {
      chats[index] = updatedChat;
      if (selectedChat?.id == updatedChat.id) {
        selectedChat = updatedChat;
        selectedChatNotifier.value = updatedChat;
      }
    });
  }

  Future<void> _selectChat(ChatThread chat) async {
    activeTypingUsersNotifier.value = [];
    _lastSentTypingStatus = 'idle';
    _messageController.clear();
    final sessionChat = _hydrateChatFromSession(chat);
    setState(() {
      selectedChat = sessionChat;
      selectedChatNotifier.value = sessionChat;
      _rightPaneView = _RightPaneView.chat;
    });
    await _loadChatCustomSettings(chat.id);

    // La navigazione avviene dopo un await: senza questo controllo si puo'
    // spingere una route su uno State gia' smontato.
    if (!mounted) return;

    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => MobileChatScreen(
            chat: sessionChat,
            selectedChatNotifier: selectedChatNotifier,
            isLoadingNotifier: isLoadingMessagesNotifier,
            isSendingNotifier: isSendingMessageNotifier,
            isUploadingNotifier: isUploadingFileNotifier,
            selectedFileNotifier: selectedFileNotifier,
            currentUserId: _currentProfile.id,
            messageController: _messageController,
            onSendPressed: _sendMessage,
            onAttachPressed: _pickFile,
            customBgColorNotifier: currentChatBgColorNotifier,
            customBubbleColorNotifier: currentChatBubbleColorNotifier,
            customBgImagePathNotifier: currentChatBgImagePathNotifier,
            customUseDefaultThemeNotifier: currentChatUseDefaultThemeNotifier,
            onCustomisePressed: () => _showCustomisationDialog(selectedChat!),
            onClearFilePressed: () {
              setState(() {
                _selectedFilePath = null;
                _selectedFileName = null;
                _selectedFileSize = null;
                _selectedFileIsImage = false;
                _selectedFileIsCode = false;
                selectedFileNotifier.value = null;
              });
            },
            activeTypingUsersNotifier: activeTypingUsersNotifier,
            onRecordingPressed: _toggleRecording,
            isRecording: _isRecording,
            sendOnEnter: _sendOnEnter,
            onToggleSendOnEnter: () => setState(() => _sendOnEnter = !_sendOnEnter),
          ),
        ),
      ).then((_) {
        setState(() {
          selectedChat = null;
          selectedChatNotifier.value = null;
        });
      });
    }

    // Connect websocket to this room for real-time updates
    try {
      _chatService.connectToRoom(chat.id);
    } catch (_) {}

    // initial load for the room, but avoid reloading after sends which causes UI jumps
    await _loadMessages(chat);
  }

  Future<void> _loadChatCustomSettings(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('chat_settings_$chatId');
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        final useDefault = data['useDefaultTheme'] ?? false;
        setState(() {
          _currentChatUseDefaultTheme = useDefault;
          currentChatUseDefaultThemeNotifier.value = useDefault;
          _currentChatBgImagePath = data['backgroundImagePath'];
          currentChatBgImagePathNotifier.value = data['backgroundImagePath'];
          if (useDefault) {
            _currentChatBgColor = Color(AppPreferences.instance.backgroundColorValue);
            currentChatBgColorNotifier.value = _currentChatBgColor;
            _currentChatBubbleColor = Color(AppPreferences.instance.themeColorValue);
            currentChatBubbleColorNotifier.value = _currentChatBubbleColor;
          } else {
            _currentChatBgColor = Color(data['backgroundColor'] ?? AppPreferences.instance.backgroundColorValue);
            currentChatBgColorNotifier.value = _currentChatBgColor;
            _currentChatBubbleColor = Color(data['bubbleColor'] ?? AppPreferences.instance.themeColorValue);
            currentChatBubbleColorNotifier.value = _currentChatBubbleColor;
          }
        });
        return;
      } catch (_) {}
    }
    // Default to app settings
    setState(() {
      _currentChatBgColor = Color(AppPreferences.instance.backgroundColorValue);
      currentChatBgColorNotifier.value = _currentChatBgColor;
      _currentChatBubbleColor = Color(AppPreferences.instance.themeColorValue);
      currentChatBubbleColorNotifier.value = _currentChatBubbleColor;
      _currentChatBgImagePath = null;
      currentChatBgImagePathNotifier.value = null;
      _currentChatUseDefaultTheme = true;
      currentChatUseDefaultThemeNotifier.value = true;
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
      'backgroundColor': bgColor.toARGB32(),
      'bubbleColor': bubbleColor.toARGB32(),
      'backgroundImagePath': bgImagePath,
      'useDefaultTheme': useDefault,
    };
    await prefs.setString('chat_settings_$chatId', jsonEncode(data));
    setState(() {
      _currentChatBgColor = bgColor;
      currentChatBgColorNotifier.value = bgColor;
      _currentChatBubbleColor = bubbleColor;
      currentChatBubbleColorNotifier.value = bubbleColor;
      _currentChatBgImagePath = bgImagePath;
      currentChatBgImagePathNotifier.value = bgImagePath;
      _currentChatUseDefaultTheme = useDefault;
      currentChatUseDefaultThemeNotifier.value = useDefault;
    });
  }

  Future<void> _createChat() async {
    final name = _newChatNameController.text.trim();
    final participantId = _newChatIdController.text.trim().replaceAll(' ', '');

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
        backgroundColorValue: _newChatBackgroundColor.toARGB32(),
        bubbleColorValue: _newChatBubbleColor.toARGB32(),
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
    final archivedList = prefs.getStringList('archived_chats_${_currentProfile.id}') ?? [];
    setState(() {
      _appThemeColor = Color(AppPreferences.instance.themeColorValue);
      _appBackgroundColor = Color(AppPreferences.instance.backgroundColorValue);
      _appBackgroundImagePath = AppPreferences.instance.backgroundImagePath;
      appBackgroundImageNotifier.value = _appBackgroundImagePath;
      _preferredLanguageCode = AppPreferences.instance.preferredLanguageCode;
      _notificationsVibrationEnabled = prefs.getBool('notifications_vibration_enabled') ?? true;
      _notificationsRingtonePath = prefs.getString('notifications_ringtone_path');
      _archivedChatIds = archivedList.toSet();
    });
  }

  Future<void> _toggleArchiveChat(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_archivedChatIds.contains(chatId)) {
        _archivedChatIds.remove(chatId);
      } else {
        _archivedChatIds.add(chatId);
        if (selectedChat?.id == chatId) {
          selectedChat = null;
          _rightPaneView = _RightPaneView.settings;
        }
      }
    });
    await prefs.setStringList('archived_chats_${_currentProfile.id}', _archivedChatIds.toList());
    _showSnackBar(_archivedChatIds.contains(chatId) ? 'Chat archiviata' : 'Chat ripristinata');
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

  Future<void> _pickAppBackgroundImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _appBackgroundImagePath = result.files.single.path!;
        });
        _showSnackBar('Immagine di sfondo app impostata con successo!');
      }
    } catch (_) {
      _showSnackBar('Impossibile selezionare l\'immagine di sfondo.');
    }
  }

  void _clearAppBackgroundImage() {
    setState(() {
      _appBackgroundImagePath = null;
      appBackgroundImageNotifier.value = null;
    });
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
        themeColorValue: _appThemeColor.toARGB32(),
        backgroundColorValue: _appBackgroundColor.toARGB32(),
        backgroundImagePath: _appBackgroundImagePath,
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

  Future<void> _logout() async {
    await AppPreferences.instance.clearSession();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const OnboardingWizardScreen(),
        ),
      );
    }
  }

  void _toggleRecording() {
    final chat = selectedChat;
    if (chat == null) return;
    setState(() => _isRecording = !_isRecording);
    _chatApi.updateTypingStatus(
      userId: _currentProfile.id,
      chatId: chat.id,
      status: _isRecording ? 'recording' : 'idle',
    );
    if (_isRecording) {
      _bumpActivity();
    }
  }

  Future<void> _sendMessage() async {
    final chat = selectedChat;
    final text = _messageController.text.trim();
    if (chat == null || (text.isEmpty && _selectedFilePath == null)) {
      return;
    }

    _bumpActivity();
    setState(() => _isSendingMessage = true);
    try {
      String? attachmentId;
      String messageText = text;

      if (_selectedFilePath != null) {
        final path = _selectedFilePath!;
        final size = _selectedFileSize ?? 0;
        final fileName = _selectedFileName ?? 'file';

        if (_selectedFileIsCode) {
          try {
            final content = await File(path).readAsString();
            final ext = fileName.split('.').last.toLowerCase();
            messageText = '```$ext:$fileName\n$content\n```';
            _selectedFilePath = null;
            _selectedFileName = null;
            _selectedFileSize = null;
            _selectedFileIsImage = false;
            _selectedFileIsCode = false;
          } catch (_) {
            // Fallback se fallisce la lettura come stringa
          }
        }

        if (_selectedFilePath != null) {
          String? adminPassword;
          bool overrideLimit = false;

          // Limit check (50 MB = 52428800 bytes)
          if (size > 52428800) {
            final password = await _showBypassDialog();
            if (password == null) {
              _showSnackBar('Upload annullato: file superiore a 50MB.');
              setState(() => _isSendingMessage = false);
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

          attachmentId = attachmentData['id']?.toString();
          if (attachmentId == null) {
            throw Exception('Errore nel ricevere ID allegato dal server.');
          }

          if (messageText.isEmpty) {
            messageText = 'Allegato: $fileName';
          }
        }
      }

      // If websocket isn't connected for this room, optimistically append the message locally
      if (!(_chatService.connected && _chatService.currentRoomId == chat.id)) {
        final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
        final optimistic = ChatMessage(id: tempId, text: messageText, senderId: _currentProfile.id, status: 'sending', timestamp: DateTime.now());
        setState(() {
          chat.messages.add(optimistic);
          _sessionMessageCache[chat.id] = List<ChatMessage>.from(chat.messages);
          selectedChat = chat;
          selectedChatNotifier.value = chat;
        });
      }

      await _chatApi.sendMessage(
        userId: _currentProfile.id,
        receiverId: chat.participantId,
        text: messageText,
        chatId: chat.id,
        fileAttachmentId: attachmentId,
        isGroup: chat.isGroup,
      );

      // if websocket connected for this room, send through it as well for low-latency
      if (_chatService.connected && _chatService.currentRoomId == chat.id) {
        await _chatService.sendMessage(messageText);
      }

      _messageController.clear();
      setState(() {
        _selectedFilePath = null;
        _selectedFileName = null;
        _selectedFileSize = null;
        _selectedFileIsImage = false;
        _selectedFileIsCode = false;
        _isUploadingFile = false;
      });

      // avoid reloading the entire chat which causes the UI to jump
      _bumpActivity();
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
        setState(() {
          _isSendingMessage = false;
          _isUploadingFile = false;
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final chat = selectedChat;
    if (chat == null) return;

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.single.path == null) return;

      final path = result.files.single.path!;
      final file = File(path);
      final size = await file.length();
      final fileName = path.split('/').last.split('\\').last;
      final extension = fileName.split('.').last.toLowerCase();
      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension);
      
      final codeExtensions = {'php', 'dart', 'js', 'ts', 'py', 'java', 'cpp', 'c', 'h', 'html', 'css', 'json', 'yaml', 'xml', 'sql', 'sh', 'bat', 'swift', 'kt', 'rs', 'go', 'txt', 'md'};
      final isCode = codeExtensions.contains(extension);

      setState(() {
        _selectedFilePath = path;
        _selectedFileName = fileName;
        _selectedFileSize = size;
        _selectedFileIsImage = isImage;
        _selectedFileIsCode = isCode;
      });
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, error);
      }
    }
  }


  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'ogg':
        return Icons.audiotrack_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.videocam_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive_rounded;
      default:
        return Icons.insert_drive_file_rounded;
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
                        tempBgColor = Color(AppPreferences.instance.backgroundColorValue);
                        tempBubbleColor = Color(AppPreferences.instance.themeColorValue);
                        tempBgImagePath = null;
                        imageController.clear();
                      }
                    });
                  },
                ),
                if (!tempUseDefault) ...[
                  const Divider(),
                  const Text('Colore sfondo chat', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  RichColorBoard(
                    selectedColor: tempBgColor,
                    onColorSelected: (color) => setDialogState(() => tempBgColor = color),
                  ),
                  const SizedBox(height: 16),
                  const Text('Colore bolle messaggi', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  RichColorBoard(
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
                if (context.mounted) {
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
      return NewChatPanel(
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
      return ChatPanel(
        key: ValueKey(selectedChat!.id),
        chat: selectedChat!,
        currentUserId: _currentProfile.id,
        isLoading: _isLoadingMessages,
        isSending: _isSendingMessage,
        isUploading: _isUploadingFile,
        messageController: _messageController,
        onSendPressed: _sendMessage,
        onAttachPressed: _pickFile,
        customBgColor: _currentChatBgColor,
        customBubbleColor: _currentChatBubbleColor,
        customBgImagePath: _currentChatBgImagePath,
        customUseDefaultTheme: _currentChatUseDefaultTheme,
        onCustomisePressed: () => _showCustomisationDialog(selectedChat!),
        selectedFileName: _selectedFileName,
        selectedFilePath: _selectedFilePath,
        selectedFileIsImage: _selectedFileIsImage,
        onClearFilePressed: () {
          setState(() {
            _selectedFilePath = null;
            _selectedFileName = null;
            _selectedFileSize = null;
            _selectedFileIsImage = false;
            _selectedFileIsCode = false;
          });
        },
        activeTypingUsersNotifier: activeTypingUsersNotifier,
        onRecordingPressed: _toggleRecording,
        isRecording: _isRecording,
        sendOnEnter: _sendOnEnter,
        onToggleSendOnEnter: () => setState(() => _sendOnEnter = !_sendOnEnter),
      );
    }
    return SettingsPanel(
      profile: _currentProfile,
      nicknameController: _nicknameController,
      selectedThemeColor: _appThemeColor,
      selectedBackgroundColor: _appBackgroundColor,
      selectedBackgroundImagePath: _appBackgroundImagePath,
      selectedLanguageCode: _preferredLanguageCode,
      supportedLanguages: _languageOptions,
      presetColors: _presetColors,
      onThemeColorChanged: (color) {
        setState(() => _appThemeColor = color);
      },
      onBackgroundColorChanged: (color) {
        setState(() => _appBackgroundColor = color);
      },
      onPickBackgroundImage: _pickAppBackgroundImage,
      onClearBackgroundImage: _clearAppBackgroundImage,
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
      onLogoutPressed: _logout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = Platform.isAndroid || Platform.isIOS;

    Widget bodyContent = Row(
      children: [
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.015 : 0.2),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.25),
                  width: 1.2,
                ),
              ),
            ),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                // Il fondo traslucido di questo pannello coprirebbe l'effetto
                // di pressione delle voci: `_ListSurface` inserisce il
                // `Material` che serve alle `ListTile` per dipingerlo.
                child: _ListSurface(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Row(
                        children: [
                          if (_showArchivedOnly)
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded),
                              onPressed: () => setState(() => _showArchivedOnly = false),
                            ),
                          Expanded(
                            child: Text(
                              _showArchivedOnly ? 'Chat archiviate' : 'Le tue chat',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!_showArchivedOnly) ...[
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
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.3)),
                    Expanded(
                      child: _isLoadingChats
                          ? const Center(child: CircularProgressIndicator())
                          : () {
                              final filteredChats = chats.where((c) => _archivedChatIds.contains(c.id) == _showArchivedOnly).toList();
                              final showArchiveTile = !_showArchivedOnly && _archivedChatIds.isNotEmpty;

                              if (filteredChats.isEmpty && !showArchiveTile) {
                                return const _NoChatsPlaceholder();
                              }

                              return ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                itemCount: filteredChats.length + (showArchiveTile ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (showArchiveTile && index == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      child: ListTile(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        tileColor: Colors.white.withValues(alpha: isDark ? 0.03 : 0.12),
                                        leading: CircleAvatar(
                                          backgroundColor: _appThemeColor.withValues(alpha: 0.2),
                                          child: Icon(Icons.archive, color: _appThemeColor),
                                        ),
                                        title: const Text(
                                          'Chat archiviate',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _appThemeColor,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${_archivedChatIds.length}',
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        onTap: () => setState(() => _showArchivedOnly = true),
                                      ),
                                    );
                                  }

                                  final chatIndex = showArchiveTile ? index - 1 : index;
                                  final chat = filteredChats[chatIndex];
                                  final isSelected = selectedChat == chat;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Dismissible(
                                        key: Key('chat_dismiss_${chat.id}'),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          color: _appThemeColor.withValues(alpha: 0.8),
                                          alignment: Alignment.centerRight,
                                          padding: const EdgeInsets.only(right: 24),
                                          child: Icon(
                                            _showArchivedOnly ? Icons.unarchive_rounded : Icons.archive_rounded,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                        onDismissed: (_) {
                                          _toggleArchiveChat(chat.id);
                                        },
                                        child: Semantics(
                                          label: isSelected
                                              ? 'Chat ${chat.title}, selezionata'
                                              : 'Chat ${chat.title}',
                                          child: ListTile(
                                            selected: isSelected,
                                            selectedTileColor: Colors.white.withValues(alpha: isDark ? 0.12 : 0.45),
                                            tileColor: isSelected ? null : Colors.white.withValues(alpha: isDark ? 0.025 : 0.12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                              side: BorderSide(
                                                color: isSelected
                                                    ? _appThemeColor.withValues(alpha: 0.4)
                                                    : Colors.white.withValues(alpha: isDark ? 0.04 : 0.18),
                                                width: 1,
                                              ),
                                            ),
                                            leading: CircleAvatar(
                                              backgroundColor: _appThemeColor,
                                              child: const Icon(
                                                Icons.chat_bubble,
                                                color: Colors.white,
                                              ),
                                            ),
                                            title: Text(
                                              chat.title,
                                              style: TextStyle(
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                            subtitle: Text(
                                              chat.messages.isNotEmpty 
                                                  ? chat.messages.last.text 
                                                  : 'Numero: ${chat.participantId}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isDark ? Colors.white70 : Colors.black54,
                                                fontStyle: chat.messages.isNotEmpty ? FontStyle.italic : FontStyle.normal,
                                              ),
                                            ),
                                            onTap: () => _selectChat(chat),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }(),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: _buildRightPane(),
        ),
      ],
    );

    final outerDecor = isMobile
        ? null
        : BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 12),
              ),
            ],
          );

    return Scaffold(
      body: Container(
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
        child: isMobile
            ? bodyContent
            : Padding(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  decoration: outerDecor,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: bodyContent,
                  ),
                ),
              ),
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

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
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
    this.selectedFileName,
    this.selectedFilePath,
    this.selectedFileIsImage = false,
    required this.onClearFilePressed,
    required this.activeTypingUsersNotifier,
    required this.onRecordingPressed,
    required this.isRecording,
    this.sendOnEnter = true,
    required this.onToggleSendOnEnter,
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
  final String? selectedFileName;
  final String? selectedFilePath;
  final bool selectedFileIsImage;
  final VoidCallback onClearFilePressed;
  final ValueNotifier<List<dynamic>> activeTypingUsersNotifier;
  final VoidCallback onRecordingPressed;
  final bool isRecording;
  final bool sendOnEnter;
  final VoidCallback onToggleSendOnEnter;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: false));
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chat.id != oldWidget.chat.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: false));
    } else if (widget.chat.messages.length > oldWidget.chat.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final wasNearBottom = _scrollController.position.maxScrollExtent - _scrollController.position.pixels < 200;
        if (wasNearBottom) {
          _scrollToBottom(animated: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({required bool animated}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(target);
    }
  }

  Widget _buildStatusTicks(String status, Color bubbleColor, bool isDark) {
    switch (status) {
      case 'read':
        final tickColor = bubbleColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
        return Icon(Icons.done_all_rounded, size: 14, color: tickColor);
      case 'delivered':
        return const Icon(Icons.done_all_rounded, size: 14, color: Colors.grey);
      case 'sent':
      default:
        return const Icon(Icons.done_rounded, size: 14, color: Colors.grey);
    }
  }

  String _formatTime(DateTime? ts) {
    if (ts == null) return '';
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _getSenderName(String senderId) {
    for (final member in widget.chat.members) {
      if (member is Map) {
        final id = member['IDutente']?.toString();
        if (id == senderId) {
          final nick = member['nickname']?.toString();
          if (nick != null && nick.isNotEmpty) return nick;
          final name = member['nome']?.toString();
          if (name != null && name.isNotEmpty) return name;
        }
      }
    }
    return 'Utente $senderId';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedBubbleColor = widget.customUseDefaultTheme
        ? Color(widget.chat.bubbleColorValue)
        : widget.customBubbleColor;

    return ChatBackground(
      backgroundColor: widget.customBgColor,
      backgroundImagePath: widget.customBgImagePath,
      useDefaultTheme: widget.customUseDefaultTheme,
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.025 : 0.25),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.28),
                  width: 1.2,
                ),
              ),
            ),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black87),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: () {
                        if (!widget.chat.isGroup) {
                          showDialog<void>(
                            context: context,
                            builder: (context) => UserProfileDialog(userId: widget.chat.participantId),
                          );
                        }
                      },
                      child: MouseRegion(
                        cursor: widget.chat.isGroup ? SystemMouseCursors.basic : SystemMouseCursors.click,
                        child: CircleAvatar(
                          backgroundColor: resolvedBubbleColor,
                          child: Text(
                            widget.chat.isGroup
                                ? (widget.chat.title.isNotEmpty ? widget.chat.title[0].toUpperCase() : 'G')
                                : (widget.chat.title.length > 5
                                    ? widget.chat.title.substring(5, 6).toUpperCase()
                                    : 'U'),
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
                            widget.chat.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          ValueListenableBuilder<List<dynamic>>(
                            valueListenable: widget.activeTypingUsersNotifier,
                            builder: (context, typingList, _) {
                              if (typingList.isNotEmpty) {
                                final names = typingList.map((t) {
                                  final nickname = t['nickname']?.toString();
                                  final name = t['nome']?.toString();
                                  return (nickname != null && nickname.isNotEmpty) ? nickname : (name ?? 'Utente');
                                }).join(', ');
                                final anyRecording = typingList.any((t) => t['status']?.toString() == 'recording');
                                final label = anyRecording ? '$names sta registrando...' : '$names sta scrivendo...';
                                return Row(
                                  children: [
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: anyRecording
                                          ? Icon(Icons.mic, size: 10, color: Colors.redAccent)
                                          : const CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                                            ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: anyRecording ? Colors.redAccent : Colors.green,
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return Text(
                                widget.chat.isGroup
                                    ? '${widget.chat.members.length} partecipanti'
                                    : 'Numero: ${widget.chat.participantId}',
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Personalizza sfondo e colori',
                      icon: Icon(Icons.palette_rounded, color: isDark ? Colors.white : Colors.black87),
                      onPressed: widget.onCustomisePressed,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.isLoading || widget.isUploading) const LinearProgressIndicator(minHeight: 2),
          // ── Message list ──
          Expanded(
            child: widget.chat.messages.isEmpty
                ? const Center(
                    child: Text(
                      'inizia la chat ora :)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.chat.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.chat.messages[index];
                      final isSent = message.isSentBy(widget.currentUserId);

                      final isImageOrVideo = message.previewType == 'image' ||
                          message.previewType == 'video' ||
                          (message.fileName != null &&
                              (message.fileName!.toLowerCase().endsWith('.png') ||
                                  message.fileName!.toLowerCase().endsWith('.jpg') ||
                                  message.fileName!.toLowerCase().endsWith('.jpeg') ||
                                  message.fileName!.toLowerCase().endsWith('.webp') ||
                                  message.fileName!.toLowerCase().endsWith('.gif') ||
                                  message.fileName!.toLowerCase().endsWith('.mp4') ||
                                  message.fileName!.toLowerCase().endsWith('.mov') ||
                                  message.fileName!.toLowerCase().endsWith('.avi') ||
                                  message.fileName!.toLowerCase().endsWith('.mkv')));
                      final showText = !(isImageOrVideo &&
                          (message.text == 'Allegato: ${message.fileName}' ||
                              message.text.startsWith('Allegato:')));

                      return Align(
                        key: ValueKey(message.id ??
                            'msg_${message.senderId}_${message.text.hashCode}_$index'),
                        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.65,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: isSent
                              ? BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      resolvedBubbleColor.withValues(alpha: 0.85),
                                      resolvedBubbleColor,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                    bottomRight: Radius.zero,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: resolvedBubbleColor.withValues(alpha: 0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                )
                              : BoxDecoration(
                                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.65),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                    bottomLeft: Radius.zero,
                                    bottomRight: Radius.circular(16),
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.35),
                                    width: 1,
                                  ),
                                ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              if (widget.chat.isGroup && !isSent) ...[
                                GestureDetector(
                                  onTap: () {
                                    showDialog<void>(
                                      context: context,
                                      builder: (context) =>
                                          UserProfileDialog(userId: message.senderId),
                                    );
                                  },
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Text(
                                      _getSenderName(message.senderId),
                                      style: TextStyle(
                                        color: isDark ? Colors.white60 : Colors.black54,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
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
                                const SizedBox(height: 4),
                              ],
                              if (showText)
                                RichMessageBubbleContent(
                                  text: message.text,
                                  isSent: isSent,
                                  isDark: isDark,
                                ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (isSent) ...[
                                      Text(
                                        _formatTime(message.timestamp),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _buildStatusTicks(message.status, resolvedBubbleColor, isDark),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // ── Input bar ──
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Seleziona file da allegare',
                    icon: Icon(
                      Icons.attach_file_rounded,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: widget.isUploading ? null : widget.onAttachPressed,
                  ),
                  IconButton(
                    tooltip: widget.sendOnEnter ? 'Invio invia messaggio' : 'Invio inserisce newline',
                    icon: Icon(
                      widget.sendOnEnter ? Icons.keyboard_return : Icons.wrap_text,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: widget.onToggleSendOnEnter,
                  ),
                  IconButton(
                    tooltip: widget.isRecording ? 'Ferma registrazione' : 'Registra audio',
                    icon: Icon(
                      widget.isRecording ? Icons.stop : Icons.mic,
                      color: widget.isRecording ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black54),
                    ),
                    onPressed: widget.onRecordingPressed,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.55),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.35),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.selectedFileName != null && !widget.selectedFileIsImage) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.attach_file_rounded,
                                    size: 14,
                                    color: isDark ? Colors.white70 : Colors.black54,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      widget.selectedFileName!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: widget.onClearFilePressed,
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: isDark ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (widget.selectedFileName != null && widget.selectedFileIsImage) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 2),
                              child: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      File(widget.selectedFilePath!),
                                      height: 60,
                                      width: 60,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: widget.onClearFilePressed,
                                    child: Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (widget.sendOnEnter)
                            Shortcuts(
                              shortcuts: const <ShortcutActivator, Intent>{
                                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                              },
                              child: Actions(
                                actions: <Type, Action<Intent>>{
                                  ActivateIntent: CallbackAction<ActivateIntent>(
                                    onInvoke: (intent) {
                                      widget.onSendPressed();
                                      return null;
                                    },
                                  ),
                                },
                                child: TextField(
                                  controller: widget.messageController,
                                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  maxLines: 5,
                                  minLines: 1,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  decoration: InputDecoration(
                                    hintText: widget.selectedFileName != null
                                        ? 'Aggiungi una didascalia...'
                                        : 'Scrivi un messaggio...',
                                    hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onSubmitted: (_) {
                                    if (widget.sendOnEnter) widget.onSendPressed();
                                  },
                                ),
                              ),
                            )
                          else
                            TextField(
                              controller: widget.messageController,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              maxLines: 5,
                              minLines: 1,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: widget.selectedFileName != null
                                    ? 'Aggiungi una didascalia...'
                                    : 'Scrivi un messaggio...',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onSubmitted: (_) {},
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: resolvedBubbleColor,
                    onPressed: widget.onSendPressed,
                    child: widget.isUploading || widget.isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
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

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    required this.profile,
    required this.nicknameController,
    required this.selectedThemeColor,
    required this.selectedBackgroundColor,
    required this.selectedBackgroundImagePath,
    required this.selectedLanguageCode,
    required this.supportedLanguages,
    required this.presetColors,
    required this.onThemeColorChanged,
    required this.onBackgroundColorChanged,
    required this.onPickBackgroundImage,
    required this.onClearBackgroundImage,
    required this.onLanguageChanged,
    required this.isSaving,
    required this.onSavePressed,
    required this.vibrationEnabled,
    required this.onVibrationToggled,
    required this.ringtonePath,
    required this.onPickRingtone,
    required this.onEditProfilePressed,
    required this.onLogoutPressed,
  });

  final UserProfile profile;
  final TextEditingController nicknameController;
  final Color selectedThemeColor;
  final Color selectedBackgroundColor;
  final String? selectedBackgroundImagePath;
  final String selectedLanguageCode;
  final List<LanguageOption> supportedLanguages;
  final List<Color> presetColors;
  final ValueChanged<Color> onThemeColorChanged;
  final ValueChanged<Color> onBackgroundColorChanged;
  final VoidCallback onPickBackgroundImage;
  final VoidCallback onClearBackgroundImage;
  final ValueChanged<String> onLanguageChanged;
  final bool isSaving;
  final Future<void> Function() onSavePressed;
  final bool vibrationEnabled;
  final ValueChanged<bool> onVibrationToggled;
  final String? ringtonePath;
  final VoidCallback onPickRingtone;
  final VoidCallback onEditProfilePressed;
  final VoidCallback onLogoutPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          _GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.phone_rounded),
              title: const Text('Il tuo numero di telefono'),
              subtitle: Text(
                profile.id,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          _GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_rounded),
              title: const Text('Privacy e dati'),
              subtitle: const Text(
                'Esporta i tuoi dati, gestisci i consensi, '
                'limita il trattamento o elimina l\'account',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivacySettingsScreen(),
                ),
              ),
            ),
          ),
          _GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.person_rounded),
              title: const Text('Modifica profilo'),
              subtitle: const Text('Foto, bio, audio bio'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onEditProfilePressed,
            ),
          ),
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Colore principale app',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Personalizza i dettagli e gli accenti visivi dell\'app',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
                ),
                const SizedBox(height: 12),
                RichColorBoard(
                  selectedColor: selectedThemeColor,
                  onColorSelected: onThemeColorChanged,
                ),
              ],
            ),
          ),
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Personalizzazione Sfondo App',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Imposta un colore solido personalizzato o una foto di sfondo sotto lo strato Crystal',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Bianco Classico'),
                        selected: selectedBackgroundColor.toARGB32() == 0xFFFFFFFF,
                        onSelected: (_) => onBackgroundColorChanged(const Color(0xFFFFFFFF)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Nero Assoluto'),
                        selected: selectedBackgroundColor.toARGB32() == 0xFF050505,
                        onSelected: (_) => onBackgroundColorChanged(const Color(0xFF050505)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sfondo personalizzato a tinta unita:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                RichColorBoard(
                  selectedColor: selectedBackgroundColor,
                  onColorSelected: onBackgroundColorChanged,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Immagine di sfondo:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPickBackgroundImage,
                        icon: const Icon(Icons.image_rounded),
                        label: const Text('Scegli immagine'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: selectedBackgroundImagePath == null ? null : onClearBackgroundImage,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Rimuovi'),
                      ),
                    ),
                  ],
                ),
                if (selectedBackgroundImagePath != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Sfondo attivo: ${selectedBackgroundImagePath!.split('/').last.split('\\').last}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                  ),
                ],
              ],
            ),
          ),
          _GlassCard(
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
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  dropdownColor: isDark ? const Color(0xFF1E0308) : Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Lingua preferita',
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                    prefixIcon: Icon(Icons.language, color: isDark ? Colors.white70 : Colors.black54),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: isDark ? 0.03 : 0.45),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: selectedThemeColor, width: 1.5),
                    ),
                  ),
                  items: supportedLanguages
                      .map(
                        (language) => DropdownMenuItem<String>(
                          value: language.code,
                          child: Text(language.label,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) onLanguageChanged(value);
                  },
                ),
              ],
            ),
          ),
          _GlassCard(
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.vibration_rounded),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Vibrazione notifiche')),
                    Switch(
                      value: vibrationEnabled,
                      onChanged: onVibrationToggled,
                    ),
                  ],
                ),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note_rounded),
                  title: const Text('Suoneria notifiche'),
                  subtitle: Text(ringtoneName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(onPressed: onPickRingtone, child: const Text('Cambia')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
                  : const Icon(Icons.save_rounded),
              label: const Text('Salva impostazioni'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
              onPressed: onLogoutPressed,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Disconnetti account'),
            ),
          ),
        ],
      ),
    );
  }
}

class NewChatPanel extends StatelessWidget {
  const NewChatPanel({
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Il pulsante di conferma sta in un'area fissa in basso, non in coda al
    // contenuto scorrevole.
    //
    // Prima era l'ultimo elemento di una colonna lunga: con i due selettori di
    // colore e l'anteprima, l'azione primaria finiva a oltre mille pixel dal
    // bordo superiore, quindi su un telefono l'utente doveva scorrere tutta la
    // pagina per trovare "Crea chat" — o peggio, non lo vedeva affatto.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
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
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              // Il limite segue l'identificativo del server: esattamente 10
              // cifre. Accettarne di più avrebbe permesso di avviare una chat
              // che il backend avrebbe poi rifiutato.
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              labelText: 'Numero di telefono (10 cifre)',
              prefixIcon: Icon(Icons.phone_rounded),
              hintText: '3391234567',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Il tuo numero: $currentUserId',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Colore sfondo chat',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          RichColorBoard(
            selectedColor: selectedBackgroundColor,
            onColorSelected: onBackgroundColorChanged,
          ),
          const SizedBox(height: 16),
          const Text(
            'Colore bolle messaggi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          RichColorBoard(
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
          const SizedBox(height: 8),
        ],
              ),
            ),
          ),
        // Barra d'azione fissa: l'azione primaria resta raggiungibile a
        // qualunque dimensione di schermo, senza dover scorrere tutta la
        // pagina.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.22),
              ),
            ),
          ),
          child: SizedBox(
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
              label: Text(isCreating ? 'Creazione in corso...' : 'Crea chat'),
            ),
          ),
        ),
      ],
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

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outerRadius = BorderRadius.circular(24);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.22),
                ]
              : [
                  Colors.white.withValues(alpha: 0.72),
                  Colors.white.withValues(alpha: 0.32),
                  Colors.black.withValues(alpha: 0.06),
                  Colors.black.withValues(alpha: 0.12),
                ],
          stops: const [0.0, 0.38, 0.78, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.03 : 0.18),
            blurRadius: 14,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.2),
        child: ClipRRect(
          borderRadius: outerRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColoredBox(
              color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.16),
              // Vedi `_ListSurface` nella parte sinistra: il `Material`
              // trasparente serve a dare ai `ListTile` una superficie su cui
              // dipingere l'effetto di pressione. Il gradiente qui sopra coprirebbe
              // quell'effetto, rendendolo invisibile.
              child: _ListSurface(
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(20),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Superficie trasparente che fornisce un `Material` ai `ListTile` discendenti.
///
/// Un `ListTile` dipinge il proprio effetto di pressione sul `Material` piu'
/// vicino. Quando e' racchiuso in un `Container` decorato — come i pannelli con
/// sfondo traslucido di questa app — quel `Material` si trova *al di sopra* del
/// contenitore, quindi l'effetto viene dipinto sotto lo sfondo e non si vede.
/// Il framework segnala l'incoerenza durante i test.
///
/// Questo widget non disegna nulla: si limita a creare il `Material` mancante
/// nel punto giusto della gerarchia.
class _ListSurface extends StatelessWidget {
  const _ListSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: child,
    );
  }
}

class RichMessageBubbleContent extends StatelessWidget {
  const RichMessageBubbleContent({
    super.key,
    required this.text,
    required this.isSent,
    required this.isDark,
  });
  final String text;
  final bool isSent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (!text.contains('```')) {
      return Text(
        text,
        style: TextStyle(
          color: isSent ? Colors.white : (isDark ? Colors.white : Colors.black87),
        ),
      );
    }

    final parts = text.split('```');
    final List<Widget> children = [];

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i % 2 == 1) {
        // Code block segment!
        var code = part;
        var lang = 'code';
        final lines = part.split('\n');
        if (lines.isNotEmpty && lines.first.trim().isNotEmpty && lines.first.trim().length < 15 && !lines.first.contains(' ')) {
          lang = lines.first.trim();
          code = lines.skip(1).join('\n');
        }
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: IdeCodeHighlightCanvas(
              code: code.trim(),
              fileName: 'snippet.$lang',
            ),
          ),
        );
      } else {
        // Standard text segment
        if (part.trim().isNotEmpty) {
          children.add(
            Text(
              part,
              style: TextStyle(
                color: isSent ? Colors.white : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
