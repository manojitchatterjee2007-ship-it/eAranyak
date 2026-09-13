import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_notification.dart';
import '../widgets/keyboard_press_effect.dart';
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

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year — $hour:$minute';
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

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ওয়েব লিঙ্কে যেতে সমস্যা হয়েছে।')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final pubDate = notification.publishedAt ?? notification.createdAt;
    final dateStr = _formatDate(pubDate);
    final isEventNotif = notification.isEvent || notification.eventDate != null || notification.venue != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: Text(isEventNotif ? 'অনুষ্ঠান সংক্রান্ত বিজ্ঞপ্তি' : 'সর্বশেষ বিজ্ঞপ্তি'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badges & Date Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (notification.isFeatured) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFD54F)),
                        ),
                        child: const Text(
                          '★ বিশেষ',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFFD54F)),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: notification.isEvent
                            ? const Color(0xFF00E676)
                            : (notification.notificationType == 'pdf'
                                ? const Color(0xFFFFB74D)
                                : (notification.notificationType == 'image'
                                    ? Colors.lightBlueAccent
                                    : const Color(0xFF2E7D32))),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        notification.isEvent ? 'EVENT' : notification.notificationType.toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ],
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

            // Event Details Box if Event Metadata present
            if (isEventNotif) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF142419),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.1),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.event_available_rounded, color: Color(0xFF00E676), size: 22),
                        SizedBox(width: 8),
                        Text(
                          'অনুষ্ঠানের বিবরণ (Event Details)',
                          style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 20),

                    if (notification.eventDate != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.access_time_filled_rounded, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'তারিখ ও সময়: ${_formatDateTime(notification.eventDate)}',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (notification.venue != null && notification.venue!.trim().isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'স্থান: ${notification.venue!.trim()}',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (notification.contactInfo != null && notification.contactInfo!.trim().isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.phone_rounded, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'যোগাযোগ: ${notification.contactInfo!.trim()}',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (notification.registrationUrl != null && notification.registrationUrl!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      KeyboardPressEffect(
                        onTap: () => _openUrl(context, notification.registrationUrl!.trim()),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.how_to_reg_rounded, color: Colors.black, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'নিবন্ধন করুন (Register Now)',
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

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
