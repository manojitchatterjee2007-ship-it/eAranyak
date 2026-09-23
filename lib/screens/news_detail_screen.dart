import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/analytics_service.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/scientific_text.dart';
import 'home_screen.dart';

class NewsDetailScreen extends StatefulWidget {
  final Map<String, dynamic> newsItem;
  const NewsDetailScreen({super.key, required this.newsItem});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _translateOnOpenIfNeeded();
    AnalyticsService().logEvent(
      contentType: 'news',
      contentId: (widget.newsItem['id'] ?? widget.newsItem['article_id'] ?? '').toString(),
      eventType: 'open',
    );
  }

  Future<void> _translateOnOpenIfNeeded() async {
    final item = widget.newsItem;
    NewsEditorialService.applyBengaliEditorial(item);

    final needsWork = !NewsEditorialService.hasUsableBengaliContent(item);
    if (!needsWork || _translating) return;

    _translating = true;
    final changed =
        await NewsEditorialService.ensureBengaliEdition(item, force: false);
    _translating = false;
    if (changed && mounted) setState(() {});
  }

  Future<void> _launchSourceUrl(BuildContext context) async {
    final urlStr = widget.newsItem['source_url']?.toString();
    if (urlStr == null || urlStr.isEmpty) {
      return;
    }

    final uri = Uri.parse(urlStr);
    try {
      final launched =
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw 'Could not launch $urlStr';
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not open external link / উৎস লিঙ্ক খোলা সম্ভব হয়নি')),
        );
      }
    }
  }

  Future<void> _shareArticle() async {
    final newsItem = widget.newsItem;
    final articleId = newsItem['article_id']?.toString();
    final safeTitle = NewsEditorialService.safeHeadline(
        newsItem['title']?.toString() ?? '');
    final title = safeTitle.isNotEmpty ? safeTitle : 'Wildlife Update';
    final imageUrl = newsItem['image_url']?.toString();

    if (articleId == null || articleId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Unable to generate article link / লিঙ্কটি তৈরি করা সম্ভব হয়নি।'),
          ),
        );
      }
      return;
    }

    final shareUrl = '$shareBaseUrl/social/article/$articleId';
    final shareText = '$title\n\n'
        'Read this article on eআরণ্যক:\n'
        '$shareUrl';

    final bool isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (isDesktop) {
      await Clipboard.setData(ClipboardData(text: shareText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Share text copied — paste it in any app! / শেয়ার করার লেখাটি কপি হয়েছে — যেকোনো অ্যাপে পেস্ট করুন!'),
          ),
        );
      }
      return;
    }

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: shareUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Link copied to clipboard! / লিঙ্কটি কপি করা হয়েছে।')),
        );
      }
    }

    try {
      final bool isMobile = defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      if (isMobile && !kIsWeb && imageUrl != null && imageUrl.isNotEmpty) {
        final uri = Uri.parse(imageUrl);
        final response = await http.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final bytes = response.bodyBytes;
          final mimeType = response.headers['content-type'] ?? 'image/jpeg';
          
          await Share.shareXFiles(
            [
              XFile.fromData(
                bytes,
                mimeType: mimeType,
                name: 'article.jpg',
              )
            ],
            text: shareText,
            subject: 'eআরণ্যক Wildlife',
          );
          return;
        }
      }
    } catch (_) {}

    try {
      await Share.share(shareText, subject: 'eAranyak Wildlife');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final newsItem = widget.newsItem;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(newsItem['source']?.toString() ?? 'Wildlife Report',
                style: const TextStyle(fontSize: 16)),
            const Text('(বন্যপ্রাণ বার্তা)',
                style: TextStyle(fontSize: 10, color: Color(0xFF81C784))),
          ],
        ),
        backgroundColor: Colors.black87,
        actions: [
          if (newsItem['source_url'] != null)
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded,
                  color: Color(0xFF00E676)),
              tooltip: 'Open in browser / ব্রাউজারে পড়ুন',
              onPressed: () {
                SoundService.playButtonSound();
                _launchSourceUrl(context);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'news_image_${newsItem['title']}',
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 200,
                  maxHeight: 350, 
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF142419),
                ),
                child: NewsImageWidget(
                  item: newsItem,
                  fit: BoxFit.contain, 
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      newsItem['source']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ScientificText(
                    NewsEditorialService.safeHeadline(
                        newsItem['title']?.toString() ?? ''),
                    selectable: true,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  if (_translating) ...[
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF00E676)),
                        ),
                        SizedBox(width: 8),
                        Text('বাংলা সংস্করণ প্রস্তুত হচ্ছে…',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(newsItem['date_str']?.toString() ?? '',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                      const Spacer(),
                      if (newsItem['is_not_found'] != true)
                        KeyboardPressEffect(
                          onTap: () async {
                            await _shareArticle();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_rounded,
                                    size: 16, color: Color(0xFF00E676)),
                                SizedBox(width: 6),
                                Text('Share',
                                    style: TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B261E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                          const Color(0xFF00E676).withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Color(0xFF00E676), size: 16),
                            SizedBox(width: 8),
                            Text('Quick Summary / সংক্ষেপ',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF81C784))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ScientificText(
                          NewsEditorialService.safeHeadline(
                              newsItem['snippet']?.toString() ?? ''),
                          selectable: true,
                          style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF81C784),
                              height: 1.6),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Detailed Report / বিস্তারিত প্রতিবেদন',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ScientificText(
                    newsItem['content']?.toString() ?? '',
                    selectable: true,
                    style: const TextStyle(
                        fontSize: 17, color: Colors.white70, height: 1.9),
                  ),
                  const SizedBox(height: 32),
                  KeyboardPressEffect(
                    onTap: () {
                      _launchSourceUrl(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142419),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                            const Color(0xFF00E676).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.language_rounded,
                              color: Color(0xFF00E676), size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Explore Original Report at ${newsItem['source']}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                    'উৎস সাইটে গিয়ে সম্পূর্ণ তথ্যচিত্র ও আলোকচিত্রসহ মূল খবরটি পড়ুন ↗',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}