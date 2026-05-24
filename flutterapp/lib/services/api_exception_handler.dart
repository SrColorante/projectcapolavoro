import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ApiExceptionHandler {
  static void handleError(BuildContext context, Object error, {VoidCallback? onRetry}) {
    final message = _extractErrorMessage(error);
    showSnackBarError(context, message, onRetry: onRetry);
    showTopBannerError(context, message);
  }

  static String _extractErrorMessage(Object error) {
    if (error is Exception) {
      final str = error.toString();
      if (str.startsWith('Exception: ')) {
        return str.substring(11);
      }
      return str;
    }
    return error.toString();
  }

  static void showSnackBarError(BuildContext context, String message, {VoidCallback? onRetry}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[900],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: onRetry != null
            ? SnackBarAction(
                label: 'RIPROVA',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  static void showTopBannerError(BuildContext context, String message) {
    if (!context.mounted) return;
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => _TopBanner(message: message),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  static Widget buildShimmerPlaceholder({
    required double width,
    required double height,
    double borderRadius = 8.0,
  }) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class _TopBanner extends StatefulWidget {
  const _TopBanner({required this.message});
  final String message;

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.redAccent[700],
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
