import 'package:flutter/material.dart';
import '../models/writing_submission.dart';
import '../widgets/scientific_text.dart';
import '../services/analytics_service.dart';

class CommunityArticleReaderScreen extends StatefulWidget {
  final WritingSubmission article;

  const CommunityArticleReaderScreen({
    super.key,
    required this.article,
  });

  @override
  State<CommunityArticleReaderScreen> createState() => _CommunityArticleReaderScreenState();
}

class _CommunityArticleReaderScreenState extends State<CommunityArticleReaderScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService().logEvent(
      contentType: 'community_article',
      contentId: widget.article.id,
      eventType: 'open',
    );
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
    final article = widget.article;
    final pubDate = article.publishedAt ?? article.submittedAt;
    final dateStr = _formatDate(pubDate);

    // Collect all image URLs and captions
    final List<Map<String, String?>> allImages = [];

    if (article.communityImages.isNotEmpty) {
      for (final img in article.communityImages) {
        if (img.imageUrl.isNotEmpty) {
          allImages.add({'url': img.imageUrl, 'caption': img.caption});
        }
      }
    } else if (article.photoUrls.isNotEmpty) {
      for (final url in article.photoUrls) {
        if (url.isNotEmpty) {
          allImages.add({'url': url, 'caption': null});
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: const Text('আপনাদের কলমে'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Badge & Date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    article.category.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Title
            ScientificText(
              article.title,
              selectable: true,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),

            // Author Name
            Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Color(0xFF00E676), size: 18),
                const SizedBox(width: 6),
                Text(
                  'কলমে: ${article.authorName}',
                  style: const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Cover Photo
            if (article.coverPhotoUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  article.coverPhotoUrl,
                  width: double.infinity,
                  height: 230,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Article Content
            ScientificText(
              article.articleContent,
              selectable: true,
              style: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.8),
            ),
            const SizedBox(height: 28),

            // Additional Photo Gallery
            if (allImages.isNotEmpty) ...[
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),
              const Text(
                'ছবিসমূহ (Photo Gallery):',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allImages.length,
                itemBuilder: (context, index) {
                  final imgMap = allImages[index];
                  final url = imgMap['url'];
                  final caption = imgMap['caption'];
                  if (url == null || url.isEmpty) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            url,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        if (caption != null && caption.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            caption,
                            style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
