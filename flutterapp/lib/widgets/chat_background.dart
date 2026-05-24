import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatBackground extends StatelessWidget {
  const ChatBackground({
    super.key,
    required this.backgroundColor,
    this.backgroundImagePath,
    required this.useDefaultTheme,
    required this.child,
  });

  final Color backgroundColor;
  final String? backgroundImagePath;
  final bool useDefaultTheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    DecorationImage? image;
    
    if (backgroundImagePath != null && backgroundImagePath!.trim().isNotEmpty) {
      final path = backgroundImagePath!.trim();
      if (path.startsWith('http://') || path.startsWith('https://')) {
        image = DecorationImage(
          image: CachedNetworkImageProvider(path),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.15),
            BlendMode.dstATop,
          ),
        );
      } else if (path.startsWith('assets/')) {
        image = DecorationImage(
          image: AssetImage(path),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.15),
            BlendMode.dstATop,
          ),
        );
      } else {
        final file = File(path);
        if (file.existsSync()) {
          image = DecorationImage(
            image: FileImage(file),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.15),
              BlendMode.dstATop,
            ),
          );
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: useDefaultTheme ? const Color(0xFFFFF5F6) : backgroundColor,
        image: image,
      ),
      child: child,
    );
  }
}
