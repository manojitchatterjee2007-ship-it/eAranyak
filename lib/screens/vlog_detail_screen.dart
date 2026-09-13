import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/vlog.dart';
import '../services/sound_service.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/nature_background.dart';
import '../widgets/scientific_text.dart';

class VlogDetailScreen extends StatelessWidget {
  final Vlog vlog;

  const VlogDetailScreen({super.key, required this.vlog});

  String? _resolveVideoUrl() {
    if (vlog.videoUrl != null && vlog.videoUrl!.trim().isNotEmpty) {
      return vlog.videoUrl!.trim();
    }
    if (vlog.storagePath != null && vlog.storagePath!.trim().isNotEmpty) {
      return Supabase.instance.client.storage
          .from('vlogs')
          .getPublicUrl(vlog.storagePath!.trim());
    }
    return null;
  }

  Future<void> _launchVideo(BuildContext context) async {
    SoundService.playButtonSound();
    final url = _resolveVideoUrl();
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ভিডিও ফাইল উপলব্ধ নেই (Video file not available)')),
      );
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ভিডিও লিঙ্কে যেতে সমস্যা হয়েছে')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening video: $e')),
        );
      }
    }
  }

  void _shareVlog() {
    SoundService.playButtonSound();
    final videoUrl = _resolveVideoUrl() ?? '';
    final text = '▶️ eAranyak Nature Vlog\n'
        '${vlog.title}\n\n'
        '${vlog.snippet ?? vlog.description ?? ''}\n\n'
        'Watch in eAranyak App! $videoUrl';
    Share.share(text, subject: vlog.title);
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'প্রকৃতির দর্পণ / Nature Vlog',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF00E676)),
            tooltip: 'শেয়ার করুন / Share',
            onPressed: _shareVlog,
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: Opacity(
              opacity: 0.3,
              child: NatureBackgroundSwitcher(),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Video Hero Card with Thumbnail & Play Button
                  Container(
                    width: double.infinity,
                    height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF142419),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E676).withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (vlog.thumbnailUrl != null && vlog.thumbnailUrl!.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: vlog.thumbnailUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(color: Color(0xFF00E676)),
                              ),
                              errorWidget: (_, __, ___) => Image.asset(
                                'assets/images/nature_log.png',
                                fit: BoxFit.contain,
                              ),
                            )
                          else
                            Image.asset(
                              'assets/images/nature_log.png',
                              fit: BoxFit.contain,
                            ),

                          // Dark gradient overlay
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.3),
                                  Colors.black.withValues(alpha: 0.7),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),

                          // Play Button Overlay
                          Center(
                            child: KeyboardPressEffect(
                              onTap: () => _launchVideo(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E676).withValues(alpha: 0.5),
                                      blurRadius: 16,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
                                    SizedBox(width: 8),
                                    Text(
                                      'ভিডিও প্লে করুন (Watch Video)',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Badges (Featured, Category, Duration)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (vlog.isFeatured)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFD54F)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD54F)),
                              SizedBox(width: 4),
                              Text(
                                'বিশেষ / Featured',
                                style: TextStyle(
                                  color: Color(0xFFFFD54F),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (vlog.category != null && vlog.category!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: Text(
                            vlog.category!,
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (vlog.durationSeconds != null && vlog.durationSeconds! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 13, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                vlog.formattedDuration,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Title
                  ScientificText(
                    vlog.title,
                    selectable: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Publication Date
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: Color(0xFF81C784), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'প্রকাশ: ${_formatDate(vlog.publishedAt ?? vlog.createdAt)}',
                        style: const TextStyle(
                          color: Color(0xFF81C784),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Description / Snippet
                  if ((vlog.description != null && vlog.description!.trim().isNotEmpty) ||
                      (vlog.snippet != null && vlog.snippet!.trim().isNotEmpty)) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142419),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_rounded, size: 16, color: Color(0xFF00E676)),
                          SizedBox(width: 6),
                          Text(
                            'ভিডিওর বিবরণ (Description)',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18221B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ScientificText(
                        (vlog.description?.isNotEmpty == true
                            ? vlog.description!
                            : vlog.snippet!),
                        selectable: true,
                        style: const TextStyle(
                          color: Color(0xE6FFFFFF),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
