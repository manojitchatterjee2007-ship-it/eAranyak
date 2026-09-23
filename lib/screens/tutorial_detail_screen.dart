import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tutorial.dart';
import '../services/sound_service.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/nature_background.dart';
import '../widgets/scientific_text.dart';

class TutorialDetailScreen extends StatelessWidget {
  final Tutorial tutorial;

  const TutorialDetailScreen({super.key, required this.tutorial});

  String? _resolveResourceUrl() {
    if (tutorial.resourceUrl != null && tutorial.resourceUrl!.trim().isNotEmpty) {
      return tutorial.resourceUrl!.trim();
    }
    if (tutorial.storagePath != null && tutorial.storagePath!.trim().isNotEmpty) {
      return Supabase.instance.client.storage
          .from('tutorials')
          .getPublicUrl(tutorial.storagePath!.trim());
    }
    return null;
  }

  Future<void> _launchResource(BuildContext context) async {
    SoundService.playButtonSound();
    final url = _resolveResourceUrl();
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('রিসোর্স লিঙ্ক উপলব্ধ নেই (Resource link not available)')),
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
            const SnackBar(content: Text('রিসোর্স লিঙ্কে যেতে সমস্যা হয়েছে')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening resource: $e')),
        );
      }
    }
  }

  void _shareTutorial() {
    SoundService.playButtonSound();
    final url = _resolveResourceUrl() ?? '';
    final text = '📚 eAranyak Tutorial & Guide\n'
        '${tutorial.title}\n\n'
        '${tutorial.snippet ?? tutorial.description ?? ''}\n\n'
        'Read & Learn in eAranyak App! $url';
    Share.share(text, subject: tutorial.title);
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  String _difficultyBengali(String diff) {
    switch (diff.toLowerCase()) {
      case 'intermediate':
        return 'মধ্যম (Intermediate)';
      case 'advanced':
        return 'উন্নত (Advanced)';
      case 'beginner':
      default:
        return 'প্রাথমিক (Beginner)';
    }
  }

  Widget _buildContentBlocks() {
    if (tutorial.contentBlocks.isEmpty) {
      if (tutorial.description == null ||
          tutorial.description!.trim().isEmpty) {
        return const SizedBox.shrink();
      }

      return ScientificText(
        tutorial.description!,
        selectable: true,
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 16,
          height: 1.8,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < tutorial.contentBlocks.length; i++)
          _buildContentBlock(tutorial.contentBlocks[i], i),
      ],
    );
  }

  Widget _buildContentBlock(Map<String, dynamic> block, int index) {
    final type = (block['type'] ?? '').toString().toLowerCase().trim();

    switch (type) {
      case 'heading':
      case 'subheading':
        final text = (block['text'] ?? block['content'] ?? '').toString().trim();
        if (text.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(
            top: index == 0 ? 0 : 20,
            bottom: 8,
          ),
          child: ScientificText(
            text,
            selectable: true,
            style: const TextStyle(
              color: Color(0xFF81C784),
              fontSize: 18,
              height: 1.4,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 'image':
        final url = (block['url'] ??
                block['imageUrl'] ??
                block['src'] ??
                block['image_url'] ??
                '')
            .toString()
            .trim();
        if (url.isEmpty) return const SizedBox.shrink();

        final caption = (block['caption'] ?? '').toString().trim();
        final credit = (block['credit'] ?? block['imageCredit'] ?? '')
            .toString()
            .trim();

        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF142419),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF00E676),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      constraints: const BoxConstraints(minHeight: 100),
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white38,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 7),
                ScientificText(
                  caption,
                  selectable: true,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (credit.isNotEmpty) ...[
                const SizedBox(height: 3),
                ScientificText(
                  'ছবি: $credit',
                  selectable: true,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );

      case 'list':
        final rawItems = block['items'];
        final items = rawItems is List
            ? rawItems
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : <String>[];

        if (items.isEmpty) {
          final text = (block['text'] ?? block['content'] ?? '').toString().trim();
          if (text.isEmpty) return const SizedBox.shrink();
          return _buildParagraph(text);
        }

        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: 9),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: Color(0xFF81C784),
                        ),
                      ),
                      Expanded(
                        child: ScientificText(
                          item,
                          selectable: true,
                          style: const TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontSize: 16,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case 'paragraph':
      case 'text':
      case 'body':
      default:
        final value = (block['text'] ?? block['content'] ?? '').toString().trim();
        if (value.isEmpty) return const SizedBox.shrink();
        return _buildParagraph(value);
    }
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: ScientificText(
        text,
        selectable: true,
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 16,
          height: 1.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resUrl = _resolveResourceUrl();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withOpacity(0.9),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'টিউটোরিয়াল নির্দেশিকা / Tutorial',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF00E676)),
            tooltip: 'শেয়ার করুন / Share',
            onPressed: _shareTutorial,
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
                  // Hero Thumbnail Banner - UPDATED TO FULL VISIBILITY
                  Container(
                    width: double.infinity,
                    height: 280, // Increased height to give the image more room
                    decoration: BoxDecoration(
                      color: const Color(0xFF142419),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E676).withOpacity(0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E676).withOpacity(0.15),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: tutorial.thumbnailUrl != null && tutorial.thumbnailUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: tutorial.thumbnailUrl!,
                              fit: BoxFit.contain, // Changed from cover to contain to prevent cropping
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(color: Color(0xFF00E676)),
                              ),
                              errorWidget: (_, __, ___) => Image.asset(
                                'assets/images/tutorials.png',
                                fit: BoxFit.contain,
                              ),
                            )
                          : Image.asset(
                              'assets/images/tutorials.png',
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Badges Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (tutorial.isFeatured)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD54F).withOpacity(0.2),
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
                      if (tutorial.category != null && tutorial.category!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: Text(
                            tutorial.category!,
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _difficultyBengali(tutorial.difficulty),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (tutorial.durationMinutes != null && tutorial.durationMinutes! > 0)
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
                              const Icon(Icons.access_time_rounded, size: 13, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                '${tutorial.durationMinutes} মিনিট',
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
                    tutorial.title,
                    selectable: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Source acknowledgement — shown immediately below the title.
                  if (tutorial.sourceName != null &&
                      tutorial.sourceName!.trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142419),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF81C784).withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.menu_book_rounded,
                              color: Color(0xFF81C784),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'সূত্র / Source: ',
                                    style: TextStyle(
                                      color: Color(0xFF81C784),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text: tutorial.sourceName!.trim(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Date
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: Color(0xFF81C784), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'প্রকাশ: ${_formatDate(tutorial.publishedAt ?? tutorial.createdAt)}',
                        style: const TextStyle(
                          color: Color(0xFF81C784),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Excerpt Box
                  if (tutorial.snippet != null && tutorial.snippet!.trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142419),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
                      ),
                      child: ScientificText(
                        tutorial.snippet!,
                        selectable: true,
                        style: const TextStyle(
                          color: Color(0xFF81C784),
                          fontSize: 15,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Main Tutorial Article Body
                  if (tutorial.contentBlocks.isNotEmpty ||
                      (tutorial.description != null &&
                          tutorial.description!.trim().isNotEmpty)) ...[
                    _buildContentBlocks(),
                    const SizedBox(height: 28),
                  ],

                  // External / Attached Resource Action Card
                  if (resUrl != null && resUrl.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18221B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                tutorial.resourceType == 'pdf'
                                    ? Icons.picture_as_pdf_rounded
                                    : (tutorial.resourceType == 'video'
                                        ? Icons.play_circle_fill_rounded
                                        : Icons.open_in_new_rounded),
                                color: const Color(0xFF00E676),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                tutorial.resourceType == 'pdf'
                                    ? 'সংযুক্ত PDF ডকুমেন্ট'
                                    : (tutorial.resourceType == 'video'
                                        ? 'সংযুক্ত ভিডিও টিউটোরিয়াল'
                                        : 'সহায়ক ওয়েব রিসোর্স / সূত্র'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          KeyboardPressEffect(
                            onTap: () => _launchResource(context),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      tutorial.resourceType == 'pdf'
                                          ? Icons.download_rounded
                                          : Icons.launch_rounded,
                                      color: Colors.black,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      tutorial.resourceType == 'pdf'
                                          ? 'PDF ডাউনলোড / দেখুন'
                                          : 'রিসোর্স লিঙ্ক খুলুন (Open Resource)',
                                      style: const TextStyle(
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
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}