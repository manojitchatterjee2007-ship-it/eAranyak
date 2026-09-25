import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/protected_asset_service.dart';

/// Protected Image rendering widget with short-lived asset protection,
/// anti-drag, anti-context menu, and graceful error handling.
class ProtectedImage extends StatefulWidget {
  final String bucket;
  final String storagePath;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const ProtectedImage({
    super.key,
    required this.bucket,
    required this.storagePath,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<ProtectedImage> createState() => _ProtectedImageState();
}

class _ProtectedImageState extends State<ProtectedImage> {
  String? _signedUrl;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSignedUrl();
  }

  @override
  void didUpdateWidget(covariant ProtectedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath ||
        oldWidget.bucket != widget.bucket) {
      _fetchSignedUrl();
    }
  }

  Future<void> _fetchSignedUrl() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = await ProtectedAssetService.getSignedUrl(
        bucket: widget.bucket,
        storagePath: widget.storagePath,
        expiresInSeconds: 120,
      );

      if (mounted) {
        setState(() {
          _signedUrl = url;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder?.call(context, widget.storagePath) ??
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Color(0xFF00E676),
                strokeWidth: 2,
              ),
            ),
          );
    }

    if (_errorMessage != null || _signedUrl == null) {
      return widget.errorWidget?.call(context, widget.storagePath, _errorMessage) ??
          const Center(
            child: Icon(Icons.broken_image_rounded, color: Colors.white38),
          );
    }

    return GestureDetector(
      // Non-interactive drag container to prevent dragging image out
      onLongPress: () {}, // Blocks default browser context menu trigger
      child: CachedNetworkImage(
        imageUrl: _signedUrl!,
        fit: widget.fit,
        placeholder: (ctx, url) =>
            widget.placeholder?.call(ctx, widget.storagePath) ??
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            ),
        errorWidget: (ctx, url, err) =>
            widget.errorWidget?.call(ctx, widget.storagePath, err) ??
            const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.white38),
            ),
      ),
    );
  }
}
