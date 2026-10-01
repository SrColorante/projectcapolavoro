import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/user_profile.dart';
import 'user_profile_dialog.dart';
import '../services/app_preferences.dart';

class ContactPreviewBubble extends StatefulWidget {
  const ContactPreviewBubble({
    super.key,
    required this.userId,
    required this.isSent,
    required this.fallbackText,
  });

  final String userId;
  final bool isSent;
  final String fallbackText;

  @override
  State<ContactPreviewBubble> createState() => _ContactPreviewBubbleState();
}

class _ContactPreviewBubbleState extends State<ContactPreviewBubble> {
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isNotFound = false;

  @override
  void initState() {
    super.initState();
    _fetchContact();
  }

  Future<void> _fetchContact() async {
    try {
      // Profilo pubblico di un altro utente: il backend restituisce solo i
      // dati minimi (nome, nickname, foto). Email, stato della 2FA e
      // informazioni di cancellazione di terzi non sono esposti, perche' non
      // servono a mostrare un contatto e sono dati identificativi.
      final profiles = await AuthApi.instance.fetchPublicProfiles([widget.userId]);
      if (!mounted) return;
      if (profiles.isEmpty) {
        setState(() {
          _isNotFound = true;
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _profile = profiles.first;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isNotFound = true;
          _isLoading = false;
        });
      }
    }
  }

  /// Compone l'URL di un file caricato.
  ///
  /// I file non sono piu' serviti come risorse statiche: `uploads/` e' bloccata
  /// e l'unica via e' `serve_file.php`, che verifica la sessione. Serve pero'
  /// il token, che qui non puo' essere allegato: l'immagine resta quindi
  /// riservata ai flussi che usano `ApiClient`.
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Color(AppPreferences.instance.themeColorValue);

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(12),
        width: 220,
        decoration: BoxDecoration(
          color: widget.isSent 
              ? Colors.white.withOpacity(0.1) 
              : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: themeColor),
            ),
            const SizedBox(width: 12),
            const Text(
              'Rilevamento contatto...',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    if (_isNotFound || _profile == null) {
      // Fallback: render as generic text message if the 10-digit number is not a registered user
      return Text(
        widget.fallbackText,
        style: TextStyle(
          color: widget.isSent ? Colors.white : (isDark ? Colors.white : Colors.black87),
        ),
      );
    }

    final profile = _profile!;
    final avatarUrl = profile.profilePhotoUrl != null ? _resolveUrl(profile.profilePhotoUrl!) : null;

    final cardBgColor = widget.isSent
        ? Colors.white.withOpacity(0.12)
        : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04));

    final textColor = widget.isSent 
        ? Colors.white 
        : (isDark ? Colors.white : Colors.black87);

    final subTextColor = widget.isSent 
        ? Colors.white70 
        : (isDark ? Colors.white60 : Colors.black54);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => UserProfileDialog.showProfile(context, profile.id),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isSent 
                ? Colors.white24 
                : (isDark ? Colors.white12 : Colors.black12),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isDark ? Colors.white10 : Colors.grey[300],
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, size: 22, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tel: ${profile.id}',
                        style: TextStyle(
                          fontSize: 11,
                          color: subTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_box_rounded, 
                      size: 14, 
                      color: widget.isSent ? Colors.white70 : themeColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Vedi Profilo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded, 
                  size: 10, 
                  color: subTextColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
