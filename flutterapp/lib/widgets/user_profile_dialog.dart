import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../api/auth_api.dart';
import '../models/user_profile.dart';

class UserProfileDialog extends StatefulWidget {
  const UserProfileDialog({super.key, required this.userId});
  final String userId;

  @override
  State<UserProfileDialog> createState() => _UserProfileDialogState();
}

class _UserProfileDialogState extends State<UserProfileDialog> {
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
      final loadedProfile = await AuthApi.fetchUserProfile(widget.userId);
      if (mounted) {
        setState(() {
          _profile = loadedProfile;
          _isLoading = false;
        });
      }
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
    final base = AuthApi.baseUrl;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile riprodurre la biografia audio.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      content: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFDC143C)),
              ),
            )
          : _errorMessage != null
              ? SizedBox(
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
                )
              : _buildProfileContent(),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CHIUDI', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC143C))),
        ),
      ],
    );
  }

  Widget _buildProfileContent() {
    final profile = _profile!;
    final avatarUrl = profile.profilePhotoUrl != null ? _resolveUrl(profile.profilePhotoUrl!) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Profile Photo
        CircleAvatar(
          radius: 50,
          backgroundColor: Colors.grey[300],
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
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isPlayingAudio ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: const Color(0xFFDC143C),
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
      ],
    );
  }
}
