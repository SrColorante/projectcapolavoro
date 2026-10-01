import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../api/auth_api.dart';
import '../models/user_profile.dart';
import '../services/app_preferences.dart';

class UserProfileDialog extends StatelessWidget {
  const UserProfileDialog({super.key, required this.userId});
  final String userId;

  static void showProfile(BuildContext context, String userId) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF101012) : const Color(0xFFF6F6F9),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: UserProfileDetailContent(
                  userId: userId,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          );
        },
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (_) => UserProfileDialog(userId: userId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Color(AppPreferences.instance.themeColorValue);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      content: SingleChildScrollView(
        child: UserProfileDetailContent(userId: userId),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CHIUDI', style: TextStyle(fontWeight: FontWeight.bold, color: themeColor)),
        ),
      ],
    );
  }
}

class UserProfileDetailContent extends StatefulWidget {
  const UserProfileDetailContent({super.key, required this.userId, this.onClose});
  final String userId;
  final VoidCallback? onClose;

  @override
  State<UserProfileDetailContent> createState() => _UserProfileDetailContentState();
}

class _UserProfileDetailContentState extends State<UserProfileDetailContent> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  // Audio Player State
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;
  StreamSubscription? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _loadProfile();

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      // Il profilo di un altro utente e' pubblico ma ridotto ai dati minimi.
      final profiles = await AuthApi.instance.fetchPublicProfiles([widget.userId]);
      if (!mounted) return;
      if (profiles.isEmpty) {
        setState(() {
          _errorMessage = 'Utente non trovato';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _profile = profiles.first;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  String _resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    var base = AuthApi.baseUrl;
    if (base.endsWith('/index.php')) {
      base = base.substring(0, base.length - '/index.php'.length);
    } else if (base.endsWith('/index')) {
      base = base.substring(0, base.length - '/index'.length);
    }
    var cleanPath = path;
    if (base.endsWith('/webService') && path.startsWith('/webService/')) {
      cleanPath = path.substring('/webService'.length);
    }
    final finalBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final finalPath = cleanPath.startsWith('/') ? cleanPath : '/$cleanPath';
    return '$finalBase$finalPath';
  }

  Future<void> _toggleAudio() async {
    final audioUrl = _profile?.profileAudioUrl;
    if (audioUrl == null) return;

    try {
      if (_isPlayingAudio) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(UrlSource(_resolveUrl(audioUrl)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile riprodurre la biografia audio.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Color(AppPreferences.instance.themeColorValue);
    if (_isLoading) {
      return SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: themeColor),
        ),
      );
    }
    if (_errorMessage != null) {
      return SizedBox(
        height: 180,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    final profile = _profile!;
    final avatarUrl = profile.profilePhotoUrl != null ? _resolveUrl(profile.profilePhotoUrl!) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Profile Photo
        CircleAvatar(
          radius: 50,
          backgroundColor: isDark ? Colors.white10 : Colors.grey[300],
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? const Icon(Icons.person, size: 55, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 16),

        // Nickname
        Text(
          profile.nickname,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        const SizedBox(height: 4),

        // User ID
        Text(
          'ID: ${profile.id}',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const Divider(height: 32),

        // Written Bio
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Biografia:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Text(
                profile.profileBio ?? 'Nessuna biografia inserita.',
                style: const TextStyle(fontSize: 14, height: 1.3),
              ),
            ],
          ),
        ),

        // Voice Bio Player
        if (profile.profileAudioUrl != null) ...[
          const Divider(height: 32),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isPlayingAudio ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: themeColor,
                    size: 32,
                  ),
                  onPressed: _toggleAudio,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Biografia Vocale',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        profile.profileAudioDurationSeconds != null
                            ? '${profile.profileAudioDurationSeconds!.toStringAsFixed(1)} secondi'
                            : 'Presente',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        if (widget.onClose != null) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: themeColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: widget.onClose,
              child: const Text('CHIUDI', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ],
    );
  }
}
