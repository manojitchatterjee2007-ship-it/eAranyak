import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/config.dart';

class FreeBookPreviewScreen extends StatefulWidget {
  final String title;
  final List<String> pageUrls;

  const FreeBookPreviewScreen({
    super.key,
    required this.title,
    required this.pageUrls,
  });

  @override
  State<FreeBookPreviewScreen> createState() => _FreeBookPreviewScreenState();
}

class _FreeBookPreviewScreenState extends State<FreeBookPreviewScreen> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _resolveUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('/storage/v1/')) {
      return '$supabaseUrl$trimmed';
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final validUrls = widget.pageUrls
        .map((u) => _resolveUrl(u))
        .where((u) => u.isNotEmpty)
        .toList();

    if (validUrls.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1410),
        appBar: AppBar(
          backgroundColor: const Color(0xFF142419),
          foregroundColor: Colors.white,
          title: Text(
            '${widget.title} (Preview)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.menu_book, size: 64, color: Colors.white38),
                SizedBox(height: 16),
                Text(
                  'এই বইটির কোনো প্রাকদর্শন পৃষ্ঠা উপলব্ধ নেই।\n(No preview pages available for this book.)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF142419),
        foregroundColor: Colors.white,
        title: Text(
          '${widget.title} (Preview)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
            ),
            child: Text(
              'Page ${_currentIndex + 1} of ${validUrls.length}',
              style: const TextStyle(
                color: Color(0xFF00E676),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (BuildContext context, int index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(validUrls[index]),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.contained * 3.0,
                heroAttributes: PhotoViewHeroAttributes(tag: 'book_preview_$index'),
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image, size: 54, color: Colors.white38),
                        const SizedBox(height: 12),
                        Text(
                          'পৃষ্ঠাটি লোড করা সম্ভব হয়নি / Failed to load page ${index + 1}',
                          style: const TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            itemCount: validUrls.length,
            loadingBuilder: (context, event) {
              return Center(
                child: SizedBox(
                  width: 32.0,
                  height: 32.0,
                  child: CircularProgressIndicator(
                    color: const Color(0xFF00E676),
                    value: event == null || event.expectedTotalBytes == null
                        ? null
                        : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                  ),
                ),
              );
            },
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            pageController: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          if (validUrls.length > 1)
            Positioned(
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF142419).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(validUrls.length, (idx) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentIndex == idx ? 12 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _currentIndex == idx ? const Color(0xFF00E676) : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class WhatsAppLogo extends StatelessWidget {
  final double size;

  const WhatsAppLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/whatsapp.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class PaperTexturePainter extends CustomPainter {
  final int seed;

  const PaperTexturePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 1.0;

    for (int i = 0; i < 20; i++) {
      final y = (i * 17 + seed) % size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
