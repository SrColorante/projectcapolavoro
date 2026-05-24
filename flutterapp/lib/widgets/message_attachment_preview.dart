import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;

import '../api/auth_api.dart';

class MessageAttachmentPreview extends StatelessWidget {
  const MessageAttachmentPreview({
    super.key,
    required this.previewType,
    required this.fileName,
    required this.mimeType,
    required this.sourceUrl,
    this.previewPayload,
  });

  final String previewType;
  final String fileName;
  final String mimeType;
  final String sourceUrl;
  final Map<String, dynamic>? previewPayload;

  static String resolveUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = AuthApi.baseUrl; // e.g. "http://localhost/webService"
    var cleanPath = path;
    if (base.endsWith('/webService') && path.startsWith('/webService/')) {
      cleanPath = path.substring('/webService'.length);
    }
    // ensure base doesn't end with slash and cleanPath starts with slash
    final finalBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final finalPath = cleanPath.startsWith('/') ? cleanPath : '/$cleanPath';
    return '$finalBase$finalPath';
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.parse(resolveUrl(url));
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire il file esternamente.')),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante l\'apertura del file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveUrl(sourceUrl);

    switch (previewType.toLowerCase()) {
      case 'image':
      case 'gif':
        return _buildImagePreview(context, resolvedUrl);
      case 'audio':
        return _AudioAttachmentPlayer(url: resolvedUrl, title: fileName);
      case 'video':
        return _VideoAttachmentPreview(url: resolvedUrl, title: fileName);
      case 'pdf':
      case 'document':
        return _buildDocumentPreview(context, resolvedUrl);
      case 'link':
        return _buildLinkPreview(context, resolvedUrl);
      default:
        // Try guessing from MIME or name if code type
        if (mimeType.startsWith('text/') ||
            fileName.endsWith('.dart') ||
            fileName.endsWith('.js') ||
            fileName.endsWith('.py') ||
            fileName.endsWith('.json') ||
            fileName.endsWith('.html') ||
            fileName.endsWith('.css') ||
            fileName.endsWith('.cpp')) {
          return _buildCodePreview(context, resolvedUrl);
        }
        return _buildGenericPreview(context, resolvedUrl);
    }
  }

  Widget _buildImagePreview(BuildContext context, String resolvedUrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () {
            // Lightbox dialog view
            showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    InteractiveViewer(
                      child: CachedNetworkImage(
                        imageUrl: resolvedUrl,
                        placeholder: (context, url) => Shimmer.fromColors(
                          baseColor: Colors.black26,
                          highlightColor: Colors.black12,
                          child: Container(color: Colors.black),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white, size: 48),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: Hero(
            tag: resolvedUrl,
            child: CachedNetworkImage(
              imageUrl: resolvedUrl,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  height: 200,
                  color: Colors.white,
                ),
              ),
              errorWidget: (context, url, error) => Container(
                height: 100,
                color: Colors.grey[200],
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Immagine non disponibile', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentPreview(BuildContext context, String resolvedUrl) {
    final isPdf = mimeType == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
          color: isPdf ? Colors.red[800] : Colors.blue[800],
          size: 36,
        ),
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          isPdf ? 'Documento PDF' : 'Documento di testo',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () => _openExternal(context, sourceUrl),
        ),
        onTap: () => _openExternal(context, sourceUrl),
      ),
    );
  }

  Widget _buildCodePreview(BuildContext context, String resolvedUrl) {
    return FutureBuilder<String>(
      future: _fetchFileContent(resolvedUrl),
      builder: (context, snapshot) {
        final codeText = snapshot.data ?? 'Caricamento codice...';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.code_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: codeText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Codice copiato negli appunti!')),
                        );
                      },
                      child: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      codeText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFFD4D4D4),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _fetchFileContent(String url) async {
    try {
      final client = http.Client();
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return response.body;
      }
      return 'Errore caricamento codice (${response.statusCode})';
    } catch (_) {
      return 'Connessione assente, impossibile mostrare il codice.';
    }
  }

  Widget _buildLinkPreview(BuildContext context, String resolvedUrl) {
    final host = previewPayload?['host']?.toString() ?? Uri.parse(resolvedUrl).host;
    final title = previewPayload?['title']?.toString() ?? fileName;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openExternal(context, resolvedUrl),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.link_rounded, color: Color(0xFFDC143C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      host,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                resolvedUrl,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenericPreview(BuildContext context, String resolvedUrl) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file_rounded, color: Colors.blueGrey, size: 36),
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          mimeType,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download_rounded),
          onPressed: () => _openExternal(context, sourceUrl),
        ),
        onTap: () => _openExternal(context, sourceUrl),
      ),
    );
  }
}

class _AudioAttachmentPlayer extends StatefulWidget {
  const _AudioAttachmentPlayer({required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<_AudioAttachmentPlayer> createState() => _AudioAttachmentPlayerState();
}

class _AudioAttachmentPlayerState extends State<_AudioAttachmentPlayer> {
  late final AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() {
          _duration = d;
        });
      }
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _position = p;
        });
      }
    });
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(UrlSource(widget.url));
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile riprodurre la descrizione audio.')),
      );
    }
  }

  String _formatDuration(Duration d) {
    final seconds = d.inSeconds % 60;
    final minutes = d.inMinutes;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                color: const Color(0xFFDC143C),
                size: 40,
              ),
              onPressed: _togglePlayback,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                            activeTrackColor: const Color(0xFFDC143C),
                            inactiveTrackColor: Colors.black12,
                            thumbColor: const Color(0xFFDC143C),
                          ),
                          child: Slider(
                            value: _position.inMilliseconds.toDouble(),
                            max: _duration.inMilliseconds.toDouble() > 0
                                ? _duration.inMilliseconds.toDouble()
                                : 100.0,
                            onChanged: (value) async {
                              await _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoAttachmentPreview extends StatefulWidget {
  const _VideoAttachmentPreview({required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<_VideoAttachmentPreview> createState() => _VideoAttachmentPreviewState();
}

class _VideoAttachmentPreviewState extends State<_VideoAttachmentPreview> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _playVideoFullscreen() {
    if (_controller == null) return;
    
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return _FullscreenVideoPlayerDialog(controller: _controller!);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isInitialized)
              AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Color(0xFFDC143C)),
              ),
            
            // Video title tag
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.title,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            // Play overlay button
            GestureDetector(
              onTap: _playVideoFullscreen,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenVideoPlayerDialog extends StatefulWidget {
  const _FullscreenVideoPlayerDialog({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_FullscreenVideoPlayerDialog> createState() => _FullscreenVideoPlayerDialogState();
}

class _FullscreenVideoPlayerDialogState extends State<_FullscreenVideoPlayerDialog> {
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.controller.value.isPlaying;
    widget.controller.addListener(_videoListener);
  }

  void _videoListener() {
    if (mounted) {
      setState(() {
        _isPlaying = widget.controller.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    widget.controller.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: widget.controller.value.aspectRatio,
            child: VideoPlayer(widget.controller),
          ),
          Positioned(
            top: 24,
            right: 24,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                if (_isPlaying) {
                  widget.controller.pause();
                } else {
                  widget.controller.play();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: VideoProgressIndicator(
              widget.controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Color(0xFFDC143C),
                bufferedColor: Colors.white30,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
