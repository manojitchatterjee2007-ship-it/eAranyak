import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FreeBookPreviewScreen extends StatelessWidget {
  final String title;
  final List<String> pageUrls;

  const FreeBookPreviewScreen(
      {super.key, required this.title, required this.pageUrls});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text('$title (Preview)'),
      ),
      body: PageView.builder(
        itemCount: pageUrls.length,
        itemBuilder: (context, index) {
          return PhotoView(
            imageProvider: CachedNetworkImageProvider(pageUrls[index]),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.contained * 2.5,
            initialScale: PhotoViewComputedScale.contained,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          );
        },
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
