import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../api/auth_api.dart';
import '../api/chat_api.dart';
import '../models/user_profile.dart';
import '../services/api_exception_handler.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;
  late final TextEditingController _bioController;

  final _chatApi = ChatApi();
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();

  bool _isLoading = false;
  String? _localPhotoPath;
  String? _localAudioPath;
  double? _audioDurationSeconds;

  // Recording State
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Recorded Audio Playing State
  bool _isAudioPlaying = false;
  StreamSubscription? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.profile.nickname);
    _bioController = TextEditingController(text: widget.profile.profileBio ?? '');

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    _audioRecorder.dispose();
    _playerStateSub?.cancel();
    _audioPlayer.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image != null) {
        setState(() {
          _localPhotoPath = image.path;
        });
      }
    } catch (_) {
      ApiExceptionHandler.showSnackBarError(context, 'Impossibile selezionare la foto.');
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/bio_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
          _localAudioPath = null;
          _audioDurationSeconds = null;
        });

        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

        _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          setState(() {
            _recordingSeconds = timer.tick;
          });
          // Limit to exactly 5.0 seconds (50 ticks of 100ms)
          if (timer.tick >= 50) {
            timer.cancel();
            await _stopRecording();
            ApiExceptionHandler.showSnackBarError(context, 'Registrazione interrotta: limite massimo di 5 secondi raggiunto.');
          }
        });
      }
    } catch (e) {
      setState(() => _isRecording = false);
      ApiExceptionHandler.showSnackBarError(context, 'Errore durante l\'avvio della registrazione.');
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        setState(() {
          _localAudioPath = path;
          _audioDurationSeconds = _recordingSeconds / 10.0;
          _isRecording = false;
        });
      }
    } catch (_) {
      setState(() => _isRecording = false);
      ApiExceptionHandler.showSnackBarError(context, 'Errore durante l\'interruzione della registrazione.');
    }
  }

  Future<void> _playVoiceBio() async {
    if (_localAudioPath != null) {
      if (_isAudioPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(DeviceFileSource(_localAudioPath!));
      }
    } else if (widget.profile.profileAudioUrl != null) {
      final resolvedAudioUrl = _resolveUrl(widget.profile.profileAudioUrl!);
      if (_isAudioPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(UrlSource(resolvedAudioUrl));
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

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      String? photoUrl = widget.profile.profilePhotoUrl;
      String? audioUrl = widget.profile.profileAudioUrl;
      double? audioDuration = _audioDurationSeconds ?? widget.profile.profileAudioDurationSeconds;

      // 1. Upload new profile photo if changed
      if (_localPhotoPath != null) {
        final attachmentData = await _chatApi.uploadFile(
          userId: widget.profile.id,
          filePath: _localPhotoPath!,
        );
        photoUrl = attachmentData['source_url']?.toString();
      }

      // 2. Upload new audio bio if recorded
      if (_localAudioPath != null) {
        final attachmentData = await _chatApi.uploadFile(
          userId: widget.profile.id,
          filePath: _localAudioPath!,
        );
        audioUrl = attachmentData['source_url']?.toString();
      }

      // 3. Patch settings
      final updatedProfile = await AuthApi.updateProfile(
        userId: widget.profile.id,
        nickname: _nicknameController.text.trim(),
        preferredLanguageCode: widget.profile.preferredLanguageCode,
        profileBio: _bioController.text.trim(),
        profilePhotoUrl: photoUrl,
        profileAudioUrl: audioUrl,
        profileAudioDurationSeconds: audioDuration,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profilo salvato correttamente!')),
        );
        Navigator.of(context).pop(updatedProfile); // Return updated profile on success
      }
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatarImage;
    if (_localPhotoPath != null) {
      avatarImage = FileImage(File(_localPhotoPath!));
    } else if (widget.profile.profilePhotoUrl != null) {
      avatarImage = NetworkImage(_resolveUrl(widget.profile.profilePhotoUrl!));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifica Profilo'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Photo Picker Circle Avatar
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 65,
                              backgroundColor: Colors.grey[350],
                              backgroundImage: avatarImage,
                              child: avatarImage == null
                                  ? const Icon(Icons.person, size: 70, color: Colors.white)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 4,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDC143C),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                                  onPressed: _pickImage,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Nickname field
                      TextFormField(
                        controller: _nicknameController,
                        decoration: const InputDecoration(
                          labelText: 'Nickname',
                          prefixIcon: Icon(Icons.badge_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Nickname non può essere vuoto' : null,
                      ),
                      const SizedBox(height: 20),
                      
                      // Bio field
                      TextFormField(
                        controller: _bioController,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Biografia',
                          prefixIcon: Icon(Icons.article_rounded),
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Voice Bio Recording Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Biografia Vocale (Max 5 sec)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (_isRecording) ...[
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const _RecordingIndicatorPulse(),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Registrazione in corso... ${(_recordingSeconds / 10.0).toStringAsFixed(1)}s',
                                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton.filled(
                                    style: IconButton.styleFrom(backgroundColor: Colors.black),
                                    icon: const Icon(Icons.stop, color: Colors.white),
                                    onPressed: _stopRecording,
                                  ),
                                ] else ...[
                                  Expanded(
                                    child: _localAudioPath != null
                                        ? const Text(
                                            'Nuovo messaggio vocale registrato',
                                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                          )
                                        : (widget.profile.profileAudioUrl != null
                                            ? const Text('Messaggio vocale presente')
                                            : const Text('Nessuna biografia vocale salvata')),
                                  ),
                                  IconButton.filled(
                                    style: IconButton.styleFrom(backgroundColor: const Color(0xFFDC143C)),
                                    icon: const Icon(Icons.mic, color: Colors.white),
                                    onPressed: _startRecording,
                                  ),
                                ],
                                
                                // Preview Player Button
                                if (!_isRecording && (_localAudioPath != null || widget.profile.profileAudioUrl != null)) ...[
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    style: IconButton.styleFrom(backgroundColor: Colors.blue[800]),
                                    icon: Icon(_isAudioPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                    onPressed: _playVoiceBio,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // SAVE BUTTON
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC143C),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text('SALVA PROFILO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    );
  }
}

class _RecordingIndicatorPulse extends StatefulWidget {
  const _RecordingIndicatorPulse();

  @override
  State<_RecordingIndicatorPulse> createState() => _RecordingIndicatorPulseState();
}

class _RecordingIndicatorPulseState extends State<_RecordingIndicatorPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_pulseController),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
