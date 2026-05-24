import 'package:flutter/material.dart';
import '../models/chat_thread.dart';
import 'home_screen.dart';

class MobileChatScreen extends StatelessWidget {
  const MobileChatScreen({
    super.key,
    required this.chat,
    required this.selectedChatNotifier,
    required this.isLoadingNotifier,
    required this.isSendingNotifier,
    required this.isUploadingNotifier,
    required this.selectedFileNotifier,
    required this.currentUserId,
    required this.messageController,
    required this.onSendPressed,
    required this.onAttachPressed,
    required this.customBgColorNotifier,
    required this.customBubbleColorNotifier,
    required this.customBgImagePathNotifier,
    required this.customUseDefaultThemeNotifier,
    required this.onCustomisePressed,
    required this.onClearFilePressed,
    required this.activeTypingUsersNotifier,
    required this.onRecordingPressed,
    required this.isRecording,
    required this.sendOnEnter,
    required this.onToggleSendOnEnter,
  });

  final ChatThread chat;
  final ValueNotifier<ChatThread?> selectedChatNotifier;
  final ValueNotifier<bool> isLoadingNotifier;
  final ValueNotifier<bool> isSendingNotifier;
  final ValueNotifier<bool> isUploadingNotifier;
  final ValueNotifier<SelectedFile?> selectedFileNotifier;
  final String currentUserId;
  final TextEditingController messageController;
  final VoidCallback onSendPressed;
  final VoidCallback onAttachPressed;
  final ValueNotifier<Color> customBgColorNotifier;
  final ValueNotifier<Color> customBubbleColorNotifier;
  final ValueNotifier<String?> customBgImagePathNotifier;
  final ValueNotifier<bool> customUseDefaultThemeNotifier;
  final VoidCallback onCustomisePressed;
  final VoidCallback onClearFilePressed;
  final ValueNotifier<List<dynamic>> activeTypingUsersNotifier;
  final VoidCallback onRecordingPressed;
  final bool isRecording;
  final bool sendOnEnter;
  final VoidCallback onToggleSendOnEnter;

  @override
  Widget build(BuildContext context) {
    final mergedListenable = Listenable.merge([
      selectedChatNotifier,
      isLoadingNotifier,
      isSendingNotifier,
      isUploadingNotifier,
      selectedFileNotifier,
      customBgColorNotifier,
      customBubbleColorNotifier,
      customBgImagePathNotifier,
      customUseDefaultThemeNotifier,
      activeTypingUsersNotifier,
    ]);

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: mergedListenable,
          builder: (context, _) {
            final activeChat = selectedChatNotifier.value ?? chat;
            final file = selectedFileNotifier.value;
            return ChatPanel(
              chat: activeChat,
              currentUserId: currentUserId,
              isLoading: isLoadingNotifier.value,
              isSending: isSendingNotifier.value,
              isUploading: isUploadingNotifier.value,
              messageController: messageController,
              onSendPressed: onSendPressed,
              onAttachPressed: onAttachPressed,
              customBgColor: customBgColorNotifier.value,
              customBubbleColor: customBubbleColorNotifier.value,
              customBgImagePath: customBgImagePathNotifier.value,
              customUseDefaultTheme: customUseDefaultThemeNotifier.value,
              onCustomisePressed: onCustomisePressed,
              selectedFileName: file?.name,
              selectedFilePath: file?.path,
              selectedFileIsImage: file?.isImage ?? false,
              onClearFilePressed: onClearFilePressed,
              activeTypingUsersNotifier: activeTypingUsersNotifier,
              onRecordingPressed: onRecordingPressed,
              isRecording: isRecording,
              sendOnEnter: sendOnEnter,
              onToggleSendOnEnter: onToggleSendOnEnter,
            );
          },
        ),
      ),
    );
  }
}
