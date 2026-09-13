import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MagazineCoverImage extends StatefulWidget {
  final String magazineId;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const MagazineCoverImage({
    super.key,
    required this.magazineId,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<MagazineCoverImage> createState() => _MagazineCoverImageState();
}

class _MagazineCoverImageState extends State<MagazineCoverImage> {
  String? _signedUrl;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant MagazineCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.magazineId != widget.magazineId) {
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
    try {
      final url = await Supabase.instance.client.storage
          .from('magazine_pages')
          .createSignedUrl('${widget.magazineId}/page_1.jpg', 3600);
      if (mounted) setState(() => _signedUrl = url);
    } catch (_) {
      // No public-URL fallback: the magazine_pages bucket is private
      // (Phase 7D-3) and covers must only ever be accessed via short-lived
      // signed URLs. On failure the widget shows its error placeholder.
      if (mounted) setState(() => _signedUrl = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_signedUrl == null) {
      child = Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF1E2E23),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF00E676),
            ),
          ),
        ),
      );
    } else {
      child = CachedNetworkImage(
        imageUrl: _signedUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (c, u) => Container(
          width: widget.width,
          height: widget.height,
          color: const Color(0xFF1E2E23),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF00E676),
              ),
            ),
          ),
        ),
        errorWidget: (c, u, e) => Container(
          width: widget.width,
          height: widget.height,
          color: const Color(0xFF1E2E23),
          child: const Icon(Icons.menu_book_rounded, color: Color(0xFF00E676), size: 26),
        ),
      );
    }

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: child,
      );
    }
    return child;
  }
}
