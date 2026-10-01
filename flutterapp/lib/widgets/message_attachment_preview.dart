import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/auth_api.dart';
import '../services/app_preferences.dart';

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

  static const Map<String, String> ngrokHeaders = {
    'ngrok-skip-browser-warning': 'true',
    'User-Agent': 'QuiceApp/1.0.0',
  };

  static String resolveUrl(String path) {
    if (path.isEmpty) return '';
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

    final uploadsMatch = RegExp(r'/uploads/(.+)$').firstMatch(cleanPath);
    if (uploadsMatch != null) {
      final fileName = uploadsMatch.group(1)!;
      final finalBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      return '$finalBase/index.php?route=serve_file&file=${Uri.encodeQueryComponent(fileName)}';
    }

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
        // Il context e' stato passato come parametro: si controlla lui, non
        // il `mounted` dello State che contiene il metodo.
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile scaricare o aprire il file esternamente.')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante l\'apertura del file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveUrl(sourceUrl);

    var effectiveType = previewType.toLowerCase();
    if (effectiveType == 'file' || effectiveType == '') {
      final nameLower = fileName.toLowerCase();
      if (nameLower.endsWith('.png') ||
          nameLower.endsWith('.jpg') ||
          nameLower.endsWith('.jpeg') ||
          nameLower.endsWith('.webp') ||
          nameLower.endsWith('.heic') ||
          nameLower.endsWith('.gif') ||
          nameLower.endsWith('.bmp')) {
        effectiveType = 'image';
      } else if (nameLower.endsWith('.mp3') ||
                 nameLower.endsWith('.m4a') ||
                 nameLower.endsWith('.wav') ||
                 nameLower.endsWith('.ogg') ||
                 nameLower.endsWith('.aac')) {
        effectiveType = 'audio';
      } else if (nameLower.endsWith('.pdf')) {
        effectiveType = 'pdf';
      }
    }

    switch (effectiveType) {
      case 'image':
      case 'gif':
        return _buildImagePreview(context, resolvedUrl);
      case 'audio':
        final hasMetadata = previewPayload != null &&
            (previewPayload!['artist'] != null ||
                previewPayload!['album_art'] != null ||
                previewPayload!['has_metadata'] == true ||
                previewPayload!['song_name'] != null);
        
        final cleanName = fileName.replaceAll(RegExp(r'\.(mp3|m4a|wav|ogg|aac)$', caseSensitive: false), '');
        final autoParsed = cleanName.contains('-');
        
        if (hasMetadata || autoParsed) {
          var artist = previewPayload?['artist']?.toString();
          var songTitle = previewPayload?['title']?.toString() ?? previewPayload?['song_name']?.toString();
          var albumArt = previewPayload?['album_art']?.toString() ?? previewPayload?['album_art_url']?.toString();

          if (artist == null && songTitle == null) {
            final parts = cleanName.split('-');
            artist = parts[0].trim();
            songTitle = parts.sublist(1).join('-').trim();
          }

          return _AudioMetadataCanvasPlayer(
            url: resolvedUrl,
            songTitle: songTitle ?? fileName,
            artist: artist ?? 'Artista Sconosciuto',
            albumArtUrl: albumArt != null ? resolveUrl(albumArt) : null,
          );
        }
        
        return _AudioAttachmentPlayer(url: resolvedUrl, title: fileName);
      case 'video':
        return _VideoAttachmentPreview(url: resolvedUrl, title: fileName);
      case 'pdf':
      case 'document':
        return _buildDocumentPreview(context, resolvedUrl);
      case 'link':
        return _buildLinkPreview(context, resolvedUrl);
      default:
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
                        httpHeaders: ngrokHeaders,
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
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              child: CachedNetworkImage(
                imageUrl: resolvedUrl,
                httpHeaders: ngrokHeaders,
                fit: BoxFit.contain,
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: 180,
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
      ),
    );
  }

  Widget _buildDocumentPreview(BuildContext context, String resolvedUrl) {
    final ext = fileName.split('.').last.toLowerCase();
    final isPdf = ext == 'pdf';
    final isWord = ['doc', 'docx'].contains(ext);
    final isExcel = ['xls', 'xlsx'].contains(ext);

    Color headerBg = const Color(0xFF2D2D2D);
    String docTypeLabel = 'ALLEGATO DOCUMENTO';
    IconData docIcon = Icons.description_rounded;
    Color iconColor = Colors.blueGrey;

    if (isPdf) {
      headerBg = const Color(0xFF8B0000);
      docTypeLabel = 'ALLEGATO PDF';
      docIcon = Icons.picture_as_pdf_rounded;
      iconColor = const Color(0xFFDC143C);
    } else if (isWord) {
      headerBg = const Color(0xFF0F3D7A);
      docTypeLabel = 'ALLEGATO WORD';
      docIcon = Icons.description_rounded;
      iconColor = Colors.blue;
    } else if (isExcel) {
      headerBg = const Color(0xFF0E5C2F);
      docTypeLabel = 'ALLEGATO FOGLIO DI CALCOLO';
      docIcon = Icons.table_chart_rounded;
      iconColor = Colors.green;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Text(
              docTypeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(docIcon, color: iconColor, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Estensione: ${ext.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                  icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                  onPressed: () => _openExternal(context, sourceUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodePreview(BuildContext context, String resolvedUrl) {
    return FutureBuilder<String>(
      future: _fetchFileContent(resolvedUrl),
      builder: (context, snapshot) {
        final codeText = snapshot.data ?? 'Caricamento codice...';
        return IdeCodeHighlightCanvas(
          code: codeText,
          fileName: fileName,
        );
      },
    );
  }

  Future<String> _fetchFileContent(String url) async {
    try {
      final client = http.Client();
      final response = await client.get(Uri.parse(url), headers: ngrokHeaders).timeout(const Duration(seconds: 4));
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
    return _buildDocumentPreview(context, resolvedUrl);
  }
}

class SpinningBorderWrapper extends StatefulWidget {
  const SpinningBorderWrapper({
    super.key,
    required this.child,
    required this.isPlaying,
    required this.themeColor,
  });

  final Widget child;
  final bool isPlaying;
  final Color themeColor;

  @override
  State<SpinningBorderWrapper> createState() => _SpinningBorderWrapperState();
}

class _SpinningBorderWrapperState extends State<SpinningBorderWrapper> with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(SpinningBorderWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        final angle = _rotationController.value * 2 * 3.141592653589793;
        return Container(
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: widget.isPlaying
                ? SweepGradient(
                    center: Alignment.center,
                    transform: GradientRotation(angle),
                    colors: [
                      widget.themeColor.withValues(alpha: 0.0),
                      widget.themeColor,
                      widget.themeColor.withValues(alpha: 0.0),
                      widget.themeColor,
                      widget.themeColor.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                  )
                : null,
            color: widget.isPlaying ? null : Colors.transparent,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF101012)
                  : const Color(0xFFF8F9FA),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _AudioMetadataCanvasPlayer extends StatefulWidget {
  const _AudioMetadataCanvasPlayer({
    required this.url,
    required this.songTitle,
    required this.artist,
    this.albumArtUrl,
  });

  final String url;
  final String songTitle;
  final String artist;
  final String? albumArtUrl;

  @override
  State<_AudioMetadataCanvasPlayer> createState() => _AudioMetadataCanvasPlayerState();
}

class _AudioMetadataCanvasPlayerState extends State<_AudioMetadataCanvasPlayer> {
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
      // Senza questo controllo, chiudere il widget durante la riproduzione
      // provoca l'uso di un context smontato.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile riprodurre la traccia audio.')),
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
    final themeColor = Color(AppPreferences.instance.themeColorValue);

    return SpinningBorderWrapper(
      isPlaying: _isPlaying,
      themeColor: themeColor,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.albumArtUrl != null && widget.albumArtUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: widget.albumArtUrl!,
                  httpHeaders: MessageAttachmentPreview.ngrokHeaders,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.black26,
                    highlightColor: Colors.black12,
                    child: Container(color: Colors.black),
                  ),
                  errorWidget: (context, url, error) => _buildPlaceholder(themeColor),
                )
              else
                _buildPlaceholder(themeColor),

              Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: _togglePlayback,
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.songTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                _formatDuration(_position),
                                style: const TextStyle(fontSize: 9, color: Colors.white54),
                              ),
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: _duration.inMilliseconds > 0
                                          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                          : 0.0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: themeColor,
                                          borderRadius: BorderRadius.circular(1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                _formatDuration(_duration),
                                style: const TextStyle(fontSize: 9, color: Colors.white54),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(Color themeColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            themeColor,
            themeColor.withValues(alpha: 0.4),
            isDark ? const Color(0xFF101012) : const Color(0xFFF8F9FA),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Opacity(
          opacity: 0.18,
          child: Icon(Icons.music_note_rounded, size: 80, color: Colors.white),
        ),
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
      if (!mounted) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Color(AppPreferences.instance.themeColorValue);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                color: themeColor,
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
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
                            activeTrackColor: themeColor,
                            inactiveTrackColor: Colors.black12,
                            thumbColor: themeColor,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: _isInitialized ? _controller!.value.aspectRatio : 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isInitialized)
                VideoPlayer(_controller!)
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFFDC143C)),
                ),
              
              if (_isInitialized && !_controller!.value.isPlaying)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _controller!.play();
                    });
                  },
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

              if (_isInitialized && _controller!.value.isPlaying)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _controller!.pause();
                      });
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),

              if (_isInitialized && _controller!.value.isPlaying)
                Positioned(
                  bottom: 6,
                  left: 6,
                  right: 6,
                  child: VideoProgressIndicator(
                    _controller!,
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
        ),
      ),
    );
  }
}

class IdeCodeHighlightCanvas extends StatelessWidget {
  const IdeCodeHighlightCanvas({super.key, required this.code, required this.fileName});
  final String code;
  final String fileName;

  Future<void> _saveCodeToFile(BuildContext context) async {
    try {
      Directory? downloadsDir;
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        downloadsDir = await getDownloadsDirectory();
      } else if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        downloadsDir = await getTemporaryDirectory();
      }

      final file = File('${downloadsDir.path}/$fileName');
      await file.writeAsString(code);

      // Il context arriva come parametro del metodo, non dallo State: e'
      // lui va controllato.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File salvato in: ${file.path}'),
          action: SnackBarAction(
            label: 'Apri',
            onPressed: () async {
              final uri = Uri.file(file.path);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nel salvare il file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF252526),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFED6A5E))),
                    const SizedBox(width: 4),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF5BF4F))),
                    const SizedBox(width: 4),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF62C654))),
                  ],
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.code_rounded, color: Color(0xFF4EC9B0), size: 12),
                      const SizedBox(width: 6),
                      Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Codice copiato negli appunti!')),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Row(
                        children: [
                          Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.6), size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Copy',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _saveCodeToFile(context),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded, color: Colors.white.withValues(alpha: 0.6), size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Salva',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(lines.length, (index) {
                          return Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          );
                        }),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: lines.length * 16.0,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: SelectableText.rich(
                        TextSpan(
                          children: _highlightSyntax(code, fileName),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.33,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _highlightSyntax(String source, String fileName) {
    final regExp = RegExp(
      r'(?<comment>\/\/.*|#.*|\/\*[\s\S]*?\*\/)|'
      r'(?<string>"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27)|'
      r'(?<number>\b\d+\b)|'
      r'(?<keyword>\b(?:class|void|final|const|return|if|else|for|while|switch|case|break|continue|import|export|from|as|package|extends|implements|with|var|dynamic|async|await|yield|null|true|false|this|super|new|def|lambda|in|is|not|and|or|try|except|finally|raise|function|let|require|module|exports|interface|public|private|protected|static|override)\b)|'
      r'(?<type>\b(?:int|double|num|bool|String|List|Map|Set|Future|Stream|UserProfile|ChatThread|ChatMessage|Widget|BuildContext|StatefulWidget|StatelessWidget|State|Object)\b)|'
      r'(?<function>\b[a-zA-Z_]\w*\s*(?=\())|'
      r'(?<ident>\b[a-zA-Z_]\w*\b)',
    );

    final List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    regExp.allMatches(source).forEach((match) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: source.substring(lastMatchEnd, match.start),
          style: const TextStyle(color: Color(0xFFD4D4D4)),
        ));
      }

      if (match.namedGroup('comment') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Color(0xFF6A9955)),
        ));
      } else if (match.namedGroup('string') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Color(0xFFCE9178)),
        ));
      } else if (match.namedGroup('number') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Color(0xFFB5CEA8)),
        ));
      } else if (match.namedGroup('keyword') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Color(0xFF569CD6), fontWeight: FontWeight.bold),
        ));
      } else if (match.namedGroup('type') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Color(0xFF4EC9B0)),
        ));
      } else if (match.namedGroup('function') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Color(0xFFDCDCAA)),
        ));
      } else {
        spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Color(0xFF9CDCFE)),
        ));
      }

      lastMatchEnd = match.end;
    });

    if (lastMatchEnd < source.length) {
      spans.add(TextSpan(
        text: source.substring(lastMatchEnd),
        style: const TextStyle(color: Color(0xFFD4D4D4)),
      ));
    }

    return spans;
  }
}
