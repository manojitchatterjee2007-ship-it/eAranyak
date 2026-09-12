import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_notification.dart';
import '../widgets/scientific_text.dart';
import '../services/analytics_service.dart';

class NotificationDetailScreen extends StatefulWidget {
  final AppNotificationItem notification;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
  });

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService().logEvent(
      contentType: 'notification',
      contentId: widget.notification.id,
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

  Future<void> _openPdf(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF ফাইলটি খুলতে সমস্যা হয়েছে।')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF খোলার ভুল: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final pubDate = notification.publishedAt ?? notification.createdAt;
    final dateStr = _formatDate(pubDate);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: const Text('সর্বশেষ বিজ্ঞপ্তি'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge & Date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: notification.notificationType == 'pdf'
                        ? const Color(0xFFFFB74D)
                        : (notification.notificationType == 'image'
                            ? Colors.lightBlueAccent
                            : const Color(0xFF2E7D32)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    notification.notificationType.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
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
              notification.title,
              selectable: true,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),

            // PDF Download/Open Button
            if (notification.notificationType == 'pdf' && notification.pdfUrl != null && notification.pdfUrl!.isNotEmpty) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB74D),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _openPdf(context, notification.pdfUrl!),
                icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.black),
                label: const Text('📄 PDF বিজ্ঞপ্তিটি খুলুন / ডাউনলোড করুন',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 20),
            ],

            // Primary Image
            if (notification.displayThumbnail.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  notification.displayThumbnail,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Content Body
            if (notification.content != null && notification.content!.isNotEmpty) ...[
              ScientificText(
                notification.content!,
                selectable: true,
                style: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.8),
              ),
              const SizedBox(height: 20),
            ] else if (notification.snippet != null && notification.snippet!.isNotEmpty) ...[
              ScientificText(
                notification.snippet!,
                selectable: true,
                style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.6),
              ),
              const SizedBox(height: 20),
            ],

            // Additional Images
            if (notification.images.isNotEmpty) ...[
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),
              const Text(
                'সংযুক্ত ছবিসমূহ:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: notification.images.length,
                itemBuilder: (context, index) {
                  final img = notification.images[index];
                  if (img.imageUrl.isEmpty) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            img.imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        if (img.caption != null && img.caption!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            img.caption!,
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
