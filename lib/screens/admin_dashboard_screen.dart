import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../services/push_notification_service.dart';
import '../services/writing_submission_service.dart';
import '../services/online_book_service.dart';
import '../services/app_notification_service.dart';
import '../services/analytics_service.dart';
import '../models/writing_submission.dart';
import '../models/online_book.dart';
import '../models/app_notification.dart';
import '../widgets/scientific_text.dart';
import '../widgets/keyboard_press_effect.dart';
import '../screens/notification_detail_screen.dart';
import '../widgets/editorial/gallery_admin_section.dart';
import '../widgets/editorial/podcast_admin_section.dart';
import '../widgets/editorial/vlog_admin_section.dart';
import '../widgets/editorial/tutorial_admin_section.dart';

class UploadTask {
  final String id;
  final String fileName;
  final String issueString;
  double progress;
  String status;
  bool isCompleted;
  bool hasError;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.issueString,
    this.progress = 0.0,
    this.status = 'Queued / সারিবদ্ধ...',
    this.isCompleted = false,
    this.hasError = false,
  });
}

class UploadManager {
  static final UploadManager instance = UploadManager._internal();
  UploadManager._internal();

  final ValueNotifier<List<UploadTask>> tasksNotifier = ValueNotifier([]);

  Future<void> startUpload({
    required PlatformFile file,
    required String issueString,
    required VoidCallback onAllCompleted,
  }) async {
    final task = UploadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${file.name}',
      fileName: file.name,
      issueString: issueString,
      status: 'Rendering & Slicing PDF...',
    );

    tasksNotifier.value = [...tasksNotifier.value, task];
    _processTask(task, file, onAllCompleted);
  }

  Future<void> _processTask(
      UploadTask task,
      PlatformFile file,
      VoidCallback onAllCompleted,
      ) async {
    try {
      // file_picker 13.x removed `PlatformFile.bytes`; the picked PDF bytes are
      // now read on demand before rendering.
      final pdfBytes = await file.readAsBytes();
      final doc = await pdfx.PdfDocument.openData(pdfBytes);
      final int totalPages = doc.pagesCount;

      final magRes = await supabase
          .from('magazines')
          .insert({
        'title': 'এখন আরণ্যক',
        'issue_date': task.issueString,
        'total_pages': totalPages,
      })
          .select()
          .single();

      final String magId = magRes['id'];

      for (int i = 1; i <= totalPages; i++) {
        task.status = 'Uploading page $i of $totalPages...';
        task.progress = i / totalPages;
        tasksNotifier.value = List.from(tasksNotifier.value);

        final page = await doc.getPage(i);
        final pageImg = await page.render(
          width: page.width * 1.6,
          height: page.height * 1.6,
          format: pdfx.PdfPageImageFormat.jpeg,
          quality: 82,
        );
        await page.close();

        if (pageImg != null) {
          final storagePath = '$magId/page_$i.jpg';

          await supabase.storage.from('magazine_pages').uploadBinary(
            storagePath,
            pageImg.bytes,
            fileOptions:
            const FileOptions(contentType: 'image/jpeg', upsert: true),
          );

          await supabase.from('magazine_pages').insert({
            'magazine_id': magId,
            'page_number': i,
            'storage_path': storagePath,
          });
        }
      }

      await doc.close();

      task.progress = 1.0;
      task.isCompleted = true;
      task.status = 'Completed / সম্পন্ন হয়েছে!';
      tasksNotifier.value = List.from(tasksNotifier.value);

      onAllCompleted();

      // Notify all app users about the new magazine issue.
      unawaited(AppNotifier.notify(
        title: 'নতুন সংখ্যা প্রকাশিত! (New Issue Published)',
        body: 'এখন আরণ্যক — ${task.issueString} এসেছে। পড়তে ট্যাপ করুন।',
        data: {
          'type': 'magazine',
          'id': magId,
          'title': 'এখন আরণ্যক — ${task.issueString}',
        },
      ));
    } catch (e) {
      task.hasError = true;
      task.status = 'Error: $e';
      tasksNotifier.value = List.from(tasksNotifier.value);
    }
  }

  void clearCompleted() {
    tasksNotifier.value =
        tasksNotifier.value.where((t) => !t.isCompleted).toList();
  }
}

String _safeHeadline(String text) {
  final cleaned = text
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  return cleaned
      .replaceFirst(RegExp(r'^(?:headline|title)\s*:\s*', caseSensitive: false), '')
      .trim();
}

class _NewsImageFallback extends StatelessWidget {
  const _NewsImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3524), Color(0xFF101C12)],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.landscape_outlined, color: Color(0xFF81C784), size: 38),
            SizedBox(height: 6),
            Text('ছবি উপলব্ধ নয়', style: TextStyle(color: Color(0xFF81C784), fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _NewsImage extends StatelessWidget {
  final Map<String, dynamic> item;
  final BoxFit fit;

  const _NewsImage({required this.item, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final imageUrl = <String?>[
      item['image_url'], item['primaryImage'], item['primary_image'], item['image'],
    ].map((value) => value?.toString().trim()).firstWhere(
          (value) => value != null && value.isNotEmpty,
      orElse: () => null,
    );
    final sourceName = item['source']?.toString().trim() ?? '';
    var rawCredit = item['image_credit']?.toString().trim() ?? '';
    rawCredit = rawCredit
        .replaceFirst(RegExp(r'^photo\s*:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^original image(?: from|:)?\s*', caseSensitive: false), '')
        .trim();
    final credit = rawCredit.isNotEmpty ? rawCredit : (sourceName.isNotEmpty ? sourceName : 'Source publication');
    if (imageUrl == null || imageUrl.isEmpty) return const _NewsImageFallback();
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          httpHeaders: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36'},
          fit: fit,
          filterQuality: FilterQuality.medium,
          fadeInDuration: const Duration(milliseconds: 180),
          placeholder: (context, url) => Container(
            color: const Color(0xFF142419),
            alignment: Alignment.center,
            child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF81C784))),
          ),
          errorWidget: (context, url, error) => const _NewsImageFallback(),
        ),
        if (credit.isNotEmpty)
          Positioned(
            left: 8, right: 8, bottom: 8,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.68), borderRadius: BorderRadius.circular(4)),
                child: Text('Photo: $credit', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
      ],
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  final VoidCallback onUploadComplete;
  final VoidCallback? onOpenGallery;
  const AdminDashboardScreen({
    super.key,
    required this.onUploadComplete,
    this.onOpenGallery,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTabIndex = 0;
  late String _startMonth;
  late String _endMonth;
  late String _selectedYear;

  final List<String> _months = [
    'January (জানুয়ারি)',
    'February (ফেব্রুয়ারি)',
    'March (মার্চ)',
    'April (এপ্রিল)',
    'May (মে)',
    'June (জুন)',
    'July (জুলাই)',
    'August (আগস্ট)',
    'September (সেপ্টেম্বর)',
    'October (অক্টোবর)',
    'November (নভেম্বর)',
    'December (ডিসেম্বর)'
  ];

  late final List<String> _years;
  List<Map<String, dynamic>> _adminMagazines = [];

  // --- News Article (via website link) editor state ---
  final TextEditingController _newsUrlCtrl = TextEditingController();
  final TextEditingController _newsSourceNameCtrl = TextEditingController();
  int _editorialPriority = 10;
  bool _newsBusy = false;
  bool _publishing = false;
  String? _newsError;
  String? _publishError;
  Map<String, dynamic>? _newsPreview;
  List<Map<String, dynamic>> _adminNews = [];

  // --- Writing Submissions State ---
  final WritingSubmissionService _writingSubmissionService = WritingSubmissionService();
  List<WritingSubmission> _adminSubmissions = [];
  bool _loadingSubmissions = false;

  @override
  void initState() {
    super.initState();
    _startMonth = _months[0];
    _endMonth = _months[2];

    _years = List.generate(31, (index) {
      final y = 2030 - index;
      final banglaDigits = {
        '0': '০',
        '1': '১',
        '2': '২',
        '3': '৩',
        '4': '৪',
        '5': '৫',
        '6': '৬',
        '7': '৭',
        '8': '৮',
        '9': '৯'
      };
      final bStr =
      y.toString().split('').map((e) => banglaDigits[e] ?? e).join('');
      return '$y ($bStr)';
    });

    _selectedYear = _years.firstWhere(
          (y) => y.startsWith('2026'),
      orElse: () => _years.first,
    );

    _loadAdminMagazines();
    _loadAdminNews();
    _loadAdminSubmissions();
    _loadAdminNotifications();
    _loadAdminOnlineBooks();
    _loadAdminAnalytics();
  }

  String _adminSubmissionStatusFilter = 'all';

  Future<void> _loadAdminSubmissions() async {
    setState(() => _loadingSubmissions = true);
    try {
      final list = await _writingSubmissionService.fetchAllSubmissions(
        statusFilter: _adminSubmissionStatusFilter,
      );
      if (mounted) {
        setState(() {
          _adminSubmissions = list;
          _loadingSubmissions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSubmissions = false);
    }
  }

  // --- Online Books State ---
  final OnlineBookService _onlineBookService = OnlineBookService();
  List<OnlineBook> _adminOnlineBooks = [];
  bool _loadingOnlineBooks = false;
  String _adminBookFilter = 'all';

  // --- Analytics State ---
  final AnalyticsService _analyticsService = AnalyticsService();
  Map<String, dynamic> _adminAnalyticsStats = {};

  Future<void> _loadAdminOnlineBooks() async {
    if (!mounted) return;
    setState(() => _loadingOnlineBooks = true);
    try {
      final list = await _onlineBookService.fetchAllBooks(filter: _adminBookFilter);
      if (mounted) {
        setState(() {
          _adminOnlineBooks = list;
          _loadingOnlineBooks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingOnlineBooks = false);
    }
  }

  Future<void> _loadAdminAnalytics() async {
    if (!mounted) return;
    final stats = await _analyticsService.fetchAdminStats();
    if (mounted) {
      setState(() {
        _adminAnalyticsStats = stats;
      });
    }
  }

  void _showCreateOrEditBookDialog({OnlineBook? existingBook}) {
    final titleCtrl = TextEditingController(text: existingBook?.title ?? '');
    final authorCtrl = TextEditingController(text: existingBook?.author ?? '');
    final publisherCtrl = TextEditingController(text: existingBook?.publisher ?? 'এখন আরণ্যক');
    final descCtrl = TextEditingController(text: existingBook?.description ?? '');
    final priceCtrl = TextEditingController(text: existingBook != null ? existingBook.price.toStringAsFixed(0) : '');
    final origPriceCtrl = TextEditingController(text: existingBook?.originalPrice != null ? existingBook!.originalPrice!.toStringAsFixed(0) : '');
    final orderUrlCtrl = TextEditingController(text: existingBook?.orderUrl ?? '');
    bool isAvailable = existingBook?.isAvailable ?? true;
    int editorialPriority = existingBook?.editorialPriority ?? 10;
    DateTime? scheduledPublishAt = existingBook?.scheduledPublishAt;
    DateTime? expiresAt = existingBook?.expiresAt;
    PlatformFile? selectedCoverFile;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF18221B),
            title: Text(
              existingBook == null ? '➕ নতুন বই যুক্ত করুন' : '✏️ বইয়ের তথ্য পরিবর্তন করুন',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('১. বইয়ের নাম (Title) *', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'বইয়ের নাম লিখুন...', filled: true, fillColor: Color(0xFF121B12), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),

                  const Text('২. লেখক (Author)', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: authorCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'লেখকের নাম...', filled: true, fillColor: Color(0xFF121B12), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),

                  const Text('৩. প্রকাশনা (Publisher) *', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: publisherCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'প্রকাশনার নাম (যেমন: এখন আরণ্যক)...', filled: true, fillColor: Color(0xFF121B12), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('৪. বিক্রয়মূল্য (₹) *', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: priceCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(hintText: 'যেমন: 250', filled: true, fillColor: Color(0xFF121B12), border: OutlineInputBorder()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('আসল মূল্য (₹)', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: origPriceCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(hintText: 'ছাড়ের জন্য...', filled: true, fillColor: Color(0xFF121B12), border: OutlineInputBorder()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  const Text('৫. বর্ণনা (Description)', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: descCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'বইয়ের বিষয়বস্তু ও বিবরণ...', filled: true, fillColor: Color(0xFF121B12), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),

                  const Text('৬. অর্ডার লিঙ্ক (Order / WhatsApp URL)', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: orderUrlCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'https://wa.me/... অথবা ই-কমার্স লিঙ্ক', filled: true, fillColor: Color(0xFF121B12), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),

                  const Text('৭. প্রচ্ছদের ছবি (Book Cover)', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF81C784), side: const BorderSide(color: Color(0xFF388E3C))),
                    onPressed: () async {
                      // file_picker 13.x: `pickFile()` is the single-file API
                      // and `withData` no longer exists.
                      final picked = await FilePicker.pickFile(type: FileType.image);
                      if (picked != null) {
                        setDlgState(() => selectedCoverFile = picked);
                      }
                    },
                    icon: const Icon(Icons.image_search_rounded),
                    label: Text(selectedCoverFile == null ? (existingBook?.thumbnailUrl != null ? 'ছবি পরিবর্তন করুন' : 'প্রচ্ছদ নির্বাচন করুন') : 'নির্বাচিত: ${selectedCoverFile!.name}'),
                  ),
                  const SizedBox(height: 12),

                  SwitchListTile(
                    activeThumbColor: const Color(0xFF00E676),
                    title: const Text('স্টকে আছে (In Stock)', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                    value: isAvailable,
                    onChanged: (v) => setDlgState(() => isAvailable = v),
                  ),

                  const SizedBox(height: 8),
                  const Text('প্রাধিকার মান (Editorial Priority 0–100):', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  Slider(
                    value: editorialPriority.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: const Color(0xFF00E676),
                    label: editorialPriority.toString(),
                    onChanged: (v) => setDlgState(() => editorialPriority = v.round()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800),
                onPressed: () => _submitBook(
                  ctx: ctx,
                  existingBook: existingBook,
                  titleCtrl: titleCtrl,
                  authorCtrl: authorCtrl,
                  publisherCtrl: publisherCtrl,
                  descCtrl: descCtrl,
                  priceCtrl: priceCtrl,
                  origPriceCtrl: origPriceCtrl,
                  orderUrlCtrl: orderUrlCtrl,
                  isAvailable: isAvailable,
                  editorialPriority: editorialPriority,
                  scheduledPublishAt: scheduledPublishAt,
                  expiresAt: expiresAt,
                  coverFile: selectedCoverFile,
                  isPublished: false,
                ),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('💾 Save Draft', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () => _submitBook(
                  ctx: ctx,
                  existingBook: existingBook,
                  titleCtrl: titleCtrl,
                  authorCtrl: authorCtrl,
                  publisherCtrl: publisherCtrl,
                  descCtrl: descCtrl,
                  priceCtrl: priceCtrl,
                  origPriceCtrl: origPriceCtrl,
                  orderUrlCtrl: orderUrlCtrl,
                  isAvailable: isAvailable,
                  editorialPriority: editorialPriority,
                  scheduledPublishAt: scheduledPublishAt,
                  expiresAt: expiresAt,
                  coverFile: selectedCoverFile,
                  isPublished: true,
                ),
                icon: const Icon(Icons.publish_rounded, size: 16),
                label: const Text('📢 Publish Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitBook({
    required BuildContext ctx,
    OnlineBook? existingBook,
    required TextEditingController titleCtrl,
    required TextEditingController authorCtrl,
    required TextEditingController publisherCtrl,
    required TextEditingController descCtrl,
    required TextEditingController priceCtrl,
    required TextEditingController origPriceCtrl,
    required TextEditingController orderUrlCtrl,
    required bool isAvailable,
    required int editorialPriority,
    required DateTime? scheduledPublishAt,
    required DateTime? expiresAt,
    required PlatformFile? coverFile,
    required bool isPublished,
  }) async {
    final title = titleCtrl.text.trim();
    final publisher = publisherCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
    final origPrice = double.tryParse(origPriceCtrl.text.trim());

    if (title.isEmpty || publisher.isEmpty || price <= 0) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে বইয়ের নাম, প্রকাশনা ও সঠিক বিক্রয়মূল্য লিখুন')),
      );
      return;
    }

    Navigator.pop(ctx);

    try {
      if (existingBook == null) {
        await _onlineBookService.createBook(
          title: title,
          author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
          publisher: publisher,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          price: price,
          originalPrice: origPrice,
          orderUrl: orderUrlCtrl.text.trim().isEmpty ? null : orderUrlCtrl.text.trim(),
          isAvailable: isAvailable,
          editorialPriority: editorialPriority,
          isPublished: isPublished,
          scheduledPublishAt: scheduledPublishAt,
          expiresAt: expiresAt,
          coverFile: coverFile,
        );
      } else {
        await _onlineBookService.updateBook(
          id: existingBook.id,
          title: title,
          author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
          publisher: publisher,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          price: price,
          originalPrice: origPrice,
          orderUrl: orderUrlCtrl.text.trim().isEmpty ? null : orderUrlCtrl.text.trim(),
          isAvailable: isAvailable,
          editorialPriority: editorialPriority,
          isPublished: isPublished,
          scheduledPublishAt: scheduledPublishAt,
          expiresAt: expiresAt,
          newCoverFile: coverFile,
          existingStoragePath: existingBook.storagePath,
          existingThumbnailUrl: existingBook.thumbnailUrl,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isPublished ? 'বইটি সফলভাবে প্রকাশিত হয়েছে!' : 'বইটি খসড়া হিসেবে সংরক্ষিত হয়েছে।')),
        );
      }
      _loadAdminOnlineBooks();
      _loadAdminAnalytics();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('বই সংরক্ষণ করতে সমস্যা: $e')),
        );
      }
    }
  }

  Widget _buildUnifiedEditorialDashboard() {
    final pubNews = _adminNews.where((n) => n['is_published'] == true).length;
    final pendingArticles = _adminSubmissions.where((s) => s.status == 'pending').length;
    final pubArticles = _adminSubmissions.where((s) => s.isPublished).length;
    final pubNotifs = _adminNotifications.where((n) => n.isPublished).length;
    final pubBooks = _adminOnlineBooks.where((b) => b.isPublished).length;
    final totalOpens = _adminAnalyticsStats['totalOpens'] ?? 0;
    final totalOrderClicks = _adminAnalyticsStats['totalOrderClicks'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C2D1F), Color(0xFF121D13)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.dashboard_customize_rounded, color: Color(0xFF00E676), size: 24),
                  SizedBox(width: 10),
                  Text(
                    '🛠️ Editorial Control Center',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E676)),
                tooltip: 'ড্যাশবোর্ড রিফ্রেশ করুন',
                onPressed: () {
                  _loadAdminNews();
                  _loadAdminSubmissions();
                  _loadAdminNotifications();
                  _loadAdminOnlineBooks();
                  _loadAdminAnalytics();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'eআরণ্যক প্ল্যাটফর্মের সার্বিক সম্পাদকীয় নিয়ন্ত্রণ ও লাইভ পরিসংখ্যান',
            style: TextStyle(color: Color(0xFF81C784), fontSize: 12),
          ),
          const SizedBox(height: 18),

          // Overview Grid Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              final count = isWide ? 4 : 2;

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: count,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: isWide ? 1.6 : 1.3,
                children: [
                  _buildDashboardStatCard('📰 Wildlife News', '$pubNews', 'প্রকাশিত সংবাদ', const Color(0xFF2E7D32)),
                  _buildDashboardStatCard('✍️ Articles', '$pendingArticles Pending', '$pubArticles Published', const Color(0xFF00897B)),
                  _buildDashboardStatCard('🔔 Notifications', '$pubNotifs', 'প্রকাশিত বিজ্ঞপ্তি', const Color(0xFF1B5E20)),
                  _buildDashboardStatCard('📚 Online Books', '$pubBooks', 'ক্যাটালগ বই', const Color(0xFFE65100)),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Analytics Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    const Icon(Icons.remove_red_eye_rounded, color: Color(0xFF00E676), size: 18),
                    const SizedBox(width: 8),
                    Text('Total Views: $totalOpens', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
                Container(height: 16, width: 1, color: Colors.white24),
                Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined, color: Color(0xFFFFD54F), size: 18),
                    const SizedBox(width: 8),
                    Text('Order Clicks: $totalOrderClicks', style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardStatCard(String title, String mainStat, String subText, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(mainStat, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subText, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildOnlineBookAdminSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📚 Online Book Store Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('(অনলাইন বই ঘর ক্যাটালগ ও অর্ডার ব্যবস্থাপনা)', style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
              tooltip: 'রিফ্রেশ করুন',
              onPressed: _loadAdminOnlineBooks,
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: () => _showCreateOrEditBookDialog(),
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: const Text('➕ নতুন বই যুক্ত করুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              {'id': 'all', 'label': 'সবগুলো'},
              {'id': 'published', 'label': 'প্রকাশিত'},
              {'id': 'draft', 'label': 'খসড়া'},
              {'id': 'unavailable', 'label': 'স্টক শেষ'},
            ].map((filter) {
              final isSelected = _adminBookFilter == filter['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    filter['label']!,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00E676),
                  backgroundColor: const Color(0xFF18221B),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _adminBookFilter = filter['id']!;
                      });
                      _loadAdminOnlineBooks();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (_loadingOnlineBooks)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
        else if (_adminOnlineBooks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text('এই বিভাগে কোনো বই পাওয়া যায়নি।', style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adminOnlineBooks.length,
            itemBuilder: (context, index) {
              final book = _adminOnlineBooks[index];
              final statusColor = book.isPublished ? const Color(0xFF00E676) : Colors.amber;
              final statusText = book.isPublished ? 'প্রকাশিত' : 'খসড়া';

              return Card(
                color: const Color(0xFF18221B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 50,
                              height: 60,
                              child: book.thumbnailUrl != null && book.thumbnailUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                imageUrl: book.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(Icons.book, color: Colors.white38),
                              )
                                  : Container(color: const Color(0xFF121B12), child: const Icon(Icons.book, color: Colors.white38)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book.title,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'লেখক: ${book.author ?? 'অন্যান্য'} | প্রকাশনা: ${book.publisher}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF81C784)),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: statusColor, width: 0.8),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: book.isAvailable ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        book.isAvailable ? 'স্টকে আছে' : 'স্টক শেষ',
                                        style: TextStyle(fontSize: 10, color: book.isAvailable ? Colors.green : Colors.redAccent),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '₹${book.price.toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFFFFD54F), fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _showCreateOrEditBookDialog(existingBook: book),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('সম্পাদনা'),
                          ),
                          if (!book.isPublished)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await _onlineBookService.setPublishStatus(book.id, true);
                                _loadAdminOnlineBooks();
                              },
                              icon: const Icon(Icons.publish_rounded, size: 16, color: Colors.black),
                              label: const Text('📢 Publish', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                            ),
                          if (book.isPublished)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await _onlineBookService.setPublishStatus(book.id, false);
                                _loadAdminOnlineBooks();
                              },
                              icon: const Icon(Icons.visibility_off_rounded, size: 16),
                              label: const Text('Unpublish'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            tooltip: 'স্থায়ীভাবে মুছে ফেলুন',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF18221B),
                                  title: const Text('🗑 মুছে ফেলার নিশ্চিতকরণ', style: TextStyle(color: Colors.white)),
                                  content: Text('আপনি কি নিশ্চিত যে "${book.title}" বইটি স্থায়ীভাবে মুছে ফেলতে চান?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await _onlineBookService.deleteBook(book.id, storagePath: book.storagePath);
                                        _loadAdminOnlineBooks();
                                      },
                                      child: const Text('মুছে ফেলুন', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _showSubmissionDetailDialog(WritingSubmission sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: ScientificText(
          sub.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'লেখক: ${sub.authorName}',
                style: const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'শব্দ সংখ্যা: ${sub.wordCount} | জমা: ${sub.submittedAt.day}/${sub.submittedAt.month}/${sub.submittedAt.year}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              ScientificText(
                sub.articleContent,
                selectable: true,
                style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
              ),
              if (sub.photoUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'সংযুক্ত ছবি:',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: sub.photoUrls.length,
                    itemBuilder: (_, i) => Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          sub.photoUrls[i],
                          height: 120,
                          width: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বন্ধ করুন', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showPublishDialog(WritingSubmission sub) {
    int priority = sub.editorialPriority > 0 ? sub.editorialPriority : 10;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF18221B),
          title: const Text('📢 প্রকাশ করুন (Approve & Publish)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScientificText(
                sub.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 16),
              const Text('সম্পাদকীয় প্রাধিকার (Editorial Priority 0–100):',
                  style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text('বর্তমান মান: $priority (উচ্চ প্রাধিকার যুক্ত লেখা আগে থাকবে)',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Slider(
                value: priority.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: const Color(0xFF00E676),
                inactiveColor: Colors.white24,
                label: priority.toString(),
                onChanged: (v) => setDlgState(() => priority = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                try {
                  await _writingSubmissionService.publishSubmission(sub, priority: priority);
                  unawaited(AppNotifier.notify(
                    title: '✍️ নতুন নিবন্ধ প্রকাশিত: ${sub.title}',
                    body: sub.excerpt?.isNotEmpty == true
                        ? sub.excerpt!
                        : 'পাঠকের নতুন নিবন্ধ পড়তে ট্যাপ করুন।',
                    data: {'type': 'community_article', 'id': sub.id},
                  ));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('লেখাটি সফলভাবে অ্যাপে প্রকাশ করা হয়েছে!')),
                  );
                  _loadAdminSubmissions();
                  widget.onUploadComplete();
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('প্রকাশ করতে ব্যর্থ: $e')),
                  );
                }
              },
              child: const Text('প্রকাশ করুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnpublishDialog(WritingSubmission sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('👁 অপ্রকাশিত করুন', style: TextStyle(color: Colors.white)),
        content: ScientificText(
          'আপনি কি "${sub.title}" লেখাটি অপ্রকাশিত করতে চান?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () async {
              Navigator.pop(ctx);
              await _writingSubmissionService.unpublishSubmission(sub.id);
              _loadAdminSubmissions();
            },
            child: const Text('অপ্রকাশিত করুন', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(WritingSubmission sub) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('❌ লেখাটি প্রত্যাখ্যান করুন', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScientificText(
              sub.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'প্রত্যাখ্যানের কারণ (ঐচ্ছিক)...',
                hintStyle: TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF121B12),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await _writingSubmissionService.rejectSubmission(sub.id, reason: reasonCtrl.text.trim());
              _loadAdminSubmissions();
            },
            child: const Text('প্রত্যাখ্যান নিশ্চিত করুন', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteSubmissionDialog(WritingSubmission sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('🗑 স্থায়ীভাবে মুছে ফেলুন', style: TextStyle(color: Colors.white)),
        content: ScientificText(
          'আপনি কি নিশ্চিত যে "${sub.title}" লেখাটি সম্পূর্ণভাবে মুছে ফেলতে চান?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _writingSubmissionService.deleteSubmission(sub.id);
              _loadAdminSubmissions();
            },
            child: const Text('মুছে ফেলুন', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPriorityDialog(WritingSubmission sub) {
    int priority = sub.editorialPriority;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF18221B),
          title: const Text('🔢 প্রাধিকার পরিবর্তন (Editorial Priority)', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScientificText(sub.title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Text('বর্তমান প্রাধিকার মান: $priority', style: const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold)),
              Slider(
                value: priority.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: const Color(0xFF00E676),
                label: priority.toString(),
                onChanged: (v) => setDlgState(() => priority = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              onPressed: () async {
                Navigator.pop(ctx);
                await _writingSubmissionService.updatePriority(sub.id, priority);
                _loadAdminSubmissions();
              },
              child: const Text('সংরক্ষণ করুন', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _newsUrlCtrl.dispose();
    _newsSourceNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdminMagazines() async {
    try {
      final res = await supabase
          .from('magazines')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _adminMagazines = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _callAdminNewsManager(
      Map<String, dynamic> payload,
      ) async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      throw Exception('আপনার সম্পাদকীয় অনুমতি নেই। / Unauthenticated session.');
    }
    final accessToken = session.accessToken;
    final url = Uri.parse('$supabaseUrl/functions/v1/admin-news-manager');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    Map<String, dynamic> body = {};
    try {
      if (response.body.isNotEmpty) {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      throw Exception('সার্ভার থেকে ত্রুটিপূর্ণ প্রতিক্রিয়া এসেছে (${response.statusCode})।');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body['success'] == false) {
        throw Exception(body['error']?.toString() ?? 'Operation failed / ব্যর্থ হয়েছে।');
      }
      return body;
    } else {
      final errorMsg = body['error']?.toString() ??
          body['message']?.toString() ??
          'ত্রুটি (${response.statusCode}) / Request failed (${response.statusCode})';
      throw Exception(errorMsg);
    }
  }

  Future<void> _loadAdminNews() async {
    try {
      final res = await supabase
          .from('wildlife_news')
          .select('id, article_id, title, bengali_headline, source, source_name, source_url, image_url, created_at, published_at, is_published, publication_source, editorial_priority')
          .order('editorial_priority', ascending: false)
          .order('published_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _adminNews = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Error loading admin news: $e');
    }
  }

  Future<void> _previewNewsFromUrl() async {
    final url = _newsUrlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'অনুগ্রহ করে একটি সংবাদের URL দিন। / Please enter an article URL.')));
      return;
    }
    final uri = Uri.tryParse(url);
    final isValidUrl = uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!isValidUrl) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'অনুগ্রহ করে একটি বৈধ সংবাদের URL দিন (http/https)। / Please enter a valid URL.')));
      return;
    }

    setState(() {
      _newsBusy = true;
      _newsError = null;
      _newsPreview = null;
      _publishError = null;
    });

    try {
      final res = await _callAdminNewsManager({
        'action': 'PREVIEW_URL',
        'articleUrl': url,
      });

      final Map<String, dynamic> previewData = (res['preview'] is Map)
          ? Map<String, dynamic>.from(res['preview'])
          : res;

      if (mounted) {
        setState(() {
          _newsPreview = {
            'imageUrl': (previewData['imageUrl'] ?? previewData['primaryImage'] ?? previewData['image_url'] ?? '').toString(),
            'bengaliHeadline': (previewData['bengaliHeadline'] ?? previewData['headline'] ?? previewData['bengali_headline'] ?? '').toString(),
            'bengaliDek': (previewData['bengaliDek'] ?? previewData['dek'] ?? previewData['bengali_dek'] ?? '').toString(),
            'bengaliBody': (previewData['bengaliBody'] ?? previewData['body'] ?? previewData['bengali_body'] ?? '').toString(),
            'sourceName': (previewData['sourceName'] ?? previewData['source'] ?? '').toString(),
            'category': (previewData['category'] ?? '').toString(),
            'wordCount': previewData['wordCount'] ?? 0,
            'articleUrl': url,
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _newsError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _newsBusy = false;
        });
      }
    }
  }

  Future<void> _publishEditorialNews() async {
    final preview = _newsPreview;
    if (preview == null || _publishing) return;
    final url = (preview['articleUrl'] ?? _newsUrlCtrl.text).toString().trim();
    if (url.isEmpty) return;

    setState(() {
      _publishing = true;
      _publishError = null;
    });

    try {
      await _callAdminNewsManager({
        'action': 'PUBLISH_URL',
        'articleUrl': url,
        'editorialPriority': _editorialPriority,
      });

      if (mounted) {
        setState(() {
          _newsPreview = null;
          _publishError = null;
          _newsUrlCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'সংবাদটি সফলভাবে প্রকাশ করা হয়েছে! / Article published successfully!')));
        _loadAdminNews();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _publishError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _publishing = false;
        });
      }
    }
  }

  Future<void> _unpublishAdminNews(Map<String, dynamic> news) async {
    final newsId = news['id']?.toString() ?? '';
    if (newsId.isEmpty) return;

    try {
      await _callAdminNewsManager({
        'action': 'UNPUBLISH_NEWS',
        'newsId': newsId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('সংবাদটি অপ্রকাশিত করা হয়েছে। / Article unpublished.')));
        _loadAdminNews();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('অপ্রকাশিত করতে ব্যর্থ: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    }
  }

  Future<void> _publishExistingAdminNews(Map<String, dynamic> news) async {
    final newsId = news['id']?.toString() ?? '';
    if (newsId.isEmpty) return;

    try {
      await _callAdminNewsManager({
        'action': 'PUBLISH_EXISTING',
        'newsId': newsId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('সংবাদটি প্রকাশ করা হয়েছে! / Article published.')));
        _loadAdminNews();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('প্রকাশ করতে ব্যর্থ: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    }
  }

  Future<void> _deleteAdminNews(Map<String, dynamic> news) async {
    final headline = _safeHeadline(
        (news['bengali_headline'] ?? news['title'] ?? '').toString());
    final displayTitle = headline.isNotEmpty ? headline : (news['title'] ?? '').toString();
    final newsId = news['id']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('স্থায়ীভাবে মুছে ফেলবেন?',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(
          'এই সংবাদটি স্থায়ীভাবে মুছে ফেলতে চান?\n\nএই কাজটি ফিরিয়ে আনা যাবে না।\n\n"$displayTitle"',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল (Cancel)', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('মুছে ফেলুন (Delete)', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || newsId.isEmpty || !mounted) return;

    try {
      await _callAdminNewsManager({
        'action': 'DELETE_NEWS',
        'newsId': newsId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('সংবাদটি সফলভাবে মুছে ফেলা হয়েছে। / News deleted successfully.')));
        _loadAdminNews();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('মুছে ফেলতে ব্যর্থ: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    }
  }

  Future<void> _pickAndUploadMultiplePdfs() async {
    final issueString = '$_startMonth - $_endMonth $_selectedYear';
    // file_picker 13.x: `pickFiles()` itself returns the picked files (multiple
    // selection is the default) and `withData`/`allowMultiple` were removed.
    final selectedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf']);

    if (selectedFiles.isEmpty) {
      return;
    }

    for (final file in selectedFiles) {
      UploadManager.instance.startUpload(
          file: file,
          issueString: issueString,
          onAllCompleted: () {
            _loadAdminMagazines();
            widget.onUploadComplete();
          });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF18221B),
          content: Text(
            '${selectedFiles.length} PDF(s) added to background queue / ${selectedFiles.length}টি পিডিএফ ব্যাকগ্রাউন্ডে আপলোড হচ্ছে',
            style: const TextStyle(color: Color(0xFF00E676)),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _deleteMagazine(String magId, String issueDate) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Confirm Deletion'),
            Text('(সংখ্যা মুছে ফেলা নিশ্চিত করুন)',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        content: Text(
            'Are you sure you want to completely delete "$issueDate" issue from servers?\n(আপনি কি নিশ্চিত যে "$issueDate" সংখ্যাটি মুছে ফেলতে চান?)'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancel (বাতিল)',
                style: TextStyle(color: Colors.white70)),
          ),
          KeyboardPressEffect(
            onTap: () {
              Navigator.pop(ctx, true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Delete (মুছে ফেলুন)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      final pages = await supabase
          .from('magazine_pages')
          .select('storage_path')
          .eq('magazine_id', magId);
      final List<String> paths = [];
      for (final p in pages) {
        paths.add(p['storage_path'] as String);
      }
      if (paths.isNotEmpty) {
        await supabase.storage.from('magazine_pages').remove(paths);
      }
      await supabase.from('magazines').delete().eq('id', magId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Issue deleted successfully / সংখ্যাটি মুছে ফেলা হয়েছে।')),
        );
        _loadAdminMagazines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTabIndex) {
      case 0: return _buildUnifiedEditorialDashboard();
      case 1: return _buildNewsAdminSection();
      case 2: return _buildSubmissionsAdminSection();
      case 3: return _buildMagazineAdminSection();
      case 4: return GalleryAdminSection(onUploadComplete: widget.onUploadComplete);
      case 5: return TutorialAdminSection(onUploadComplete: widget.onUploadComplete);
      case 6: return PodcastAdminSection(onUploadComplete: widget.onUploadComplete);
      case 7: return VlogAdminSection(onUploadComplete: widget.onUploadComplete);
      case 8: return _buildNotificationAdminSection();
      case 9: return _buildOnlineBookAdminSection();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NavigationRail(
          backgroundColor: const Color(0xFF142419),
          selectedIndex: _selectedTabIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          labelType: NavigationRailLabelType.all,
          selectedLabelTextStyle: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelTextStyle: const TextStyle(color: Colors.white70, fontSize: 11),
          selectedIconTheme: const IconThemeData(color: Color(0xFF00E676)),
          unselectedIconTheme: const IconThemeData(color: Colors.white70),
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.dashboard_rounded), label: Text('Dashboard')),
            NavigationRailDestination(icon: Icon(Icons.newspaper_rounded), label: Text('News')),
            NavigationRailDestination(icon: Icon(Icons.article_rounded), label: Text('Articles')),
            NavigationRailDestination(icon: Icon(Icons.menu_book_rounded), label: Text('Magazines')),
            NavigationRailDestination(icon: Icon(Icons.photo_library_rounded), label: Text('Gallery')),
            NavigationRailDestination(icon: Icon(Icons.school_rounded), label: Text('Tutorials')),
            NavigationRailDestination(icon: Icon(Icons.podcasts_rounded), label: Text('Podcasts')),
            NavigationRailDestination(icon: Icon(Icons.video_library_rounded), label: Text('Vlogs')),
            NavigationRailDestination(icon: Icon(Icons.notifications_rounded), label: Text('Notifs')),
            NavigationRailDestination(icon: Icon(Icons.book_rounded), label: Text('Books')),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1, color: Colors.white24),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSelectedTabContent(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMagazineAdminSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),

        const Text('Publish Magazine Issues (2000 - 2030)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Text('(নতুন সংখ্যা প্রকাশনা - পত্রিকার নাম নির্দিষ্ট: "এখন আরণ্যক")',
            style: TextStyle(color: Color(0xFF81C784), fontSize: 12)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF18221B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _startMonth,
                      dropdownColor: const Color(0xFF18221B),
                      decoration: const InputDecoration(
                        labelText: 'Start Month',
                        helperText: '(শুরুর মাস)',
                        border: OutlineInputBorder(),
                      ),
                      items: _months
                          .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m,
                              style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _startMonth = val!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _endMonth,
                      dropdownColor: const Color(0xFF18221B),
                      decoration: const InputDecoration(
                        labelText: 'End Month',
                        helperText: '(শেষের মাস)',
                        border: OutlineInputBorder(),
                      ),
                      items: _months
                          .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m,
                              style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _endMonth = val!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedYear,
                      dropdownColor: const Color(0xFF18221B),
                      decoration: const InputDecoration(
                        labelText: 'Year',
                        helperText: '(বছর)',
                        border: OutlineInputBorder(),
                      ),
                      items: _years
                          .map((y) => DropdownMenuItem(
                          value: y,
                          child: Text(y,
                              style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedYear = val!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Selected Issue: $_startMonth - $_endMonth $_selectedYear',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        KeyboardPressEffect(
          onTap: _pickAndUploadMultiplePdfs,
          child: Container(
            height: 62,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_file, color: Colors.white),
                SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select PDF(s) & Upload in Background',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text(
                        '(একাধিক ফাইল নির্বাচন করুন ও ব্যাকগ্রাউন্ডে আপলোড চালান)',
                        style: TextStyle(fontSize: 10, color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 36),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),
        const Text('Manage & Delete Published Issues:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('(প্রকাশিত সংখ্যা পরিচালনা ও মুছে ফেলা)',
            style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
        const SizedBox(height: 12),
        if (_adminMagazines.isEmpty)
          const Text('No issues uploaded yet / আপাতত কোনো সংখ্যা নেই।',
              style: TextStyle(color: Colors.grey))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adminMagazines.length,
            itemBuilder: (context, index) {
              final mag = _adminMagazines[index];
              return Card(
                color: const Color(0xFF18221B),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.menu_book_rounded,
                      color: Color(0xFF00E676)),
                  title: Text('${formatMagazineTitle(mag['title']?.toString())} (${mag['issue_date']})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Total Pages: ${mag['total_pages']} (মোট পৃষ্ঠা: ${mag['total_pages']} টি)'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_forever_rounded,
                        color: Colors.redAccent),
                    tooltip: 'Delete Issue / সংখ্যাটি মুছে ফেলুন',
                    onPressed: () {
                      _deleteMagazine(mag['id'], mag['issue_date']);
                    },
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 36),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildNewsAdminSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // =========================================================
        // 📰 EDITORIAL NEWS MANAGEMENT
        // =========================================================
        const Text('📰 Editorial News Management',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        const Text('(সম্পাদকীয় বার্তা ব্যবস্থাপনা — যেকোনো ইউআরএল থেকে সংবাদ প্রকাশ ও পরিচালনা)',
            style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
        const SizedBox(height: 16),

        // --- PART 1: ADD / PREVIEW NEWS FROM URL ---
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF18221B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add / Preview News From URL',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
              const SizedBox(height: 12),
              const Text('Article URL:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 6),
              TextField(
                controller: _newsUrlCtrl,
                enabled: !_newsBusy && !_publishing,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Paste article URL',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // Priority Selector
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Editorial Priority:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142419),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00E676)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _editorialPriority,
                        dropdownColor: const Color(0xFF18221B),
                        style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 14),
                        items: [1, 5, 10, 15, 20, 25, 50, 100].map((p) {
                          return DropdownMenuItem<int>(
                            value: p,
                            child: Text('Priority $p'),
                          );
                        }).toList(),
                        onChanged: (_newsBusy || _publishing)
                            ? null
                            : (val) {
                          if (val != null) {
                            setState(() => _editorialPriority = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Higher priority articles appear before automated news.',
                  style: TextStyle(fontSize: 11, color: Colors.white54, fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),

              // Preview Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: (_newsBusy || _publishing) ? null : _previewNewsFromUrl,
                  icon: _newsBusy
                      ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.visibility_rounded, color: Colors.black, size: 20),
                  label: Text(
                    _newsBusy ? 'বাংলা সম্পাদকীয় সংস্করণ প্রস্তুত হচ্ছে…' : '👁 Preview Bengali Article',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),

              if (_newsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Text('Error: $_newsError',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.4)),
                  ),
                ),
            ],
          ),
        ),

        // --- PREVIEW RESULT UI ---
        if (_newsPreview != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF142419),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF00E676), size: 18),
                    SizedBox(width: 8),
                    Text('প্রিভিউ (Bengali Preview Ready)',
                        style: TextStyle(color: Color(0xFF81C784), fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),

                // Image
                if ((_newsPreview!['imageUrl'] ?? '').toString().isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: _NewsImage(
                        item: {'image_url': _newsPreview!['imageUrl']},
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Headline
                Text(
                  _newsPreview!['bengaliHeadline'] ?? '',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white, height: 1.3),
                ),

                // Dek
                if ((_newsPreview!['bengaliDek'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _newsPreview!['bengaliDek'] ?? '',
                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFF81C784), height: 1.4),
                  ),
                ],

                const SizedBox(height: 12),

                // Bounded / Expandable Body Preview
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _newsPreview!['bengaliBody'] ?? '',
                      style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.6),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Additional Metadata
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if ((_newsPreview!['sourceName'] ?? '').toString().isNotEmpty)
                      Text('Source: ${_newsPreview!['sourceName']}',
                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    if ((_newsPreview!['category'] ?? '').toString().isNotEmpty)
                      Text('Category: ${_newsPreview!['category']}',
                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    if (_newsPreview!['wordCount'] != null && _newsPreview!['wordCount'] != 0)
                      Text('Words: ${_newsPreview!['wordCount']}',
                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),

                const SizedBox(height: 16),

                // Publish Button
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _publishing ? null : _publishEditorialNews,
                      icon: _publishing
                          ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.check_circle_rounded, color: Colors.black, size: 20),
                      label: Text(
                        _publishing ? 'প্রকাশ করা হচ্ছে…' : '✅ Publish Article',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: _publishing
                          ? null
                          : () {
                        setState(() {
                          _newsPreview = null;
                          _publishError = null;
                        });
                      },
                      child: const Text('Discard (বাতিল)', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),

                if (_publishError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Publish Error: $_publishError',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00E676)),
                ),
                onPressed: widget.onOpenGallery,
                icon: const Icon(Icons.photo_library_rounded, color: Color(0xFF00E676), size: 18),
                label: const Text('Open Gallery Manager (গ্যালারি পরিচালনা)',
                    style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh News List / তালিকা রিফ্রেশ করুন',
              onPressed: _loadAdminNews,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E676)),
            ),
          ],
        ),

        const SizedBox(height: 36),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSubmissionsAdminSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📝 পাঠকদের লেখা — Editorial Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('(পাঠকদের পাঠানো লেখা পর্যালোচনা ও প্রকাশনা নিয়ন্ত্রণ)', style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
              tooltip: 'রিফ্রেশ করুন',
              onPressed: _loadAdminSubmissions,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Status Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              {'id': 'all', 'label': 'সবগুলো'},
              {'id': 'pending', 'label': 'অপেক্ষমাণ'},
              {'id': 'approved', 'label': 'অনুমোদিত'},
              {'id': 'published', 'label': 'প্রকাশিত'},
              {'id': 'unpublished', 'label': 'অপ্রকাশিত'},
              {'id': 'rejected', 'label': 'প্রত্যাখ্যাত'},
            ].map((filter) {
              final isSelected = _adminSubmissionStatusFilter == filter['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    filter['label']!,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00E676),
                  backgroundColor: const Color(0xFF18221B),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _adminSubmissionStatusFilter = filter['id']!;
                      });
                      _loadAdminSubmissions();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (_loadingSubmissions)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
        else if (_adminSubmissions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text('এই বিভাগে কোনো পাঠানো লেখা নেই।', style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adminSubmissions.length,
            itemBuilder: (context, index) {
              final sub = _adminSubmissions[index];
              Color statusColor;
              String statusText;
              switch (sub.status) {
                case 'approved':
                  statusColor = const Color(0xFF81C784);
                  statusText = 'অনুমোদিত';
                  break;
                case 'rejected':
                  statusColor = Colors.redAccent;
                  statusText = 'প্রত্যাখ্যাত';
                  break;
                case 'published':
                  statusColor = const Color(0xFF00E676);
                  statusText = 'প্রকাশিত';
                  break;
                case 'unpublished':
                  statusColor = Colors.grey;
                  statusText = 'অপ্রকাশিত';
                  break;
                default:
                  statusColor = Colors.amber;
                  statusText = 'অপেক্ষমাণ';
              }

              return Card(
                color: const Color(0xFF18221B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (sub.coverPhotoUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                sub.coverPhotoUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white38),
                              ),
                            )
                          else
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFF121B12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.article_outlined, color: Colors.white38, size: 24),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ScientificText(
                                  sub.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: statusColor, width: 0.8),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                    if (sub.photoUrls.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.blue, width: 0.8),
                                        ),
                                        child: Text(
                                          '📷 ${sub.photoUrls.length} টি ছবি',
                                          style: const TextStyle(fontSize: 10, color: Colors.blue),
                                        ),
                                      ),
                                    if (sub.isPublished)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E676).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF00E676), width: 0.8),
                                        ),
                                        child: Text(
                                          'Priority: ${sub.editorialPriority}',
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'লেখক: ${sub.authorName}  |  শব্দ: ${sub.wordCount}  |  জমা: ${sub.submittedAt.day}/${sub.submittedAt.month}/${sub.submittedAt.year}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF81C784)),
                      ),
                      const SizedBox(height: 8),
                      ScientificText(
                        sub.displayExcerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      if (sub.rejectionReason != null && sub.rejectionReason!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'প্রত্যাখ্যানের কারণ: ${sub.rejectionReason}',
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontStyle: FontStyle.italic),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _showSubmissionDetailDialog(sub),
                            icon: const Icon(Icons.visibility, size: 16),
                            label: const Text('পড়ুন'),
                          ),
                          if (sub.status != 'approved' && sub.status != 'published')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await _writingSubmissionService.approveSubmission(sub.id);
                                _loadAdminSubmissions();
                              },
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('✓ Approve'),
                            ),
                          if (sub.status != 'published')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _showPublishDialog(sub),
                              icon: const Icon(Icons.publish_rounded, size: 16, color: Colors.black),
                              label: const Text('📢 Publish', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                            ),
                          if (sub.status == 'published')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _showUnpublishDialog(sub),
                              icon: const Icon(Icons.visibility_off_rounded, size: 16),
                              label: const Text('Unpublish'),
                            ),
                          if (sub.status == 'published')
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF00E676),
                                side: const BorderSide(color: Color(0xFF00E676)),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _showPriorityDialog(sub),
                              icon: const Icon(Icons.tune_rounded, size: 16),
                              label: const Text('Priority'),
                            ),
                          if (sub.status != 'rejected')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade900,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _showRejectDialog(sub),
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('✕ Reject'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            tooltip: 'স্থায়ীভাবে মুছে ফেলুন',
                            onPressed: () => _showDeleteSubmissionDialog(sub),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        const SizedBox(height: 36),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),

        // --- PART 2: MANAGE EXISTING NEWS ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Existing News Management',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('(প্রকাশিত ও অপ্রকাশিত সকল সংবাদ পরিচালনা)',
                    style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              ],
            ),
            IconButton(
              tooltip: 'Refresh News List / তালিকা রিফ্রেশ করুন',
              onPressed: _loadAdminNews,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E676)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_adminNews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No news records found / আপাতত কোনো সংবাদ রেকর্ড নেই।', style: TextStyle(color: Colors.grey)),
          )
        else
          ..._adminNews.map((news) {
            final headline = _safeHeadline(
                (news['bengali_headline'] ?? news['title'] ?? '').toString());
            final displayTitle = headline.isNotEmpty ? headline : (news['title'] ?? 'Untitled Article').toString();
            final isPub = news['is_published'] == true;
            final pubSrc = (news['publication_source'] ?? '').toString();
            final priority = news['editorial_priority'] ?? 0;
            final sourceName = (news['source_name'] ?? news['source'] ?? 'eআরণ্যক').toString();

            return Card(
              color: const Color(0xFF18221B),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isPub ? Colors.green.withValues(alpha: 0.3) : Colors.white12,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 60,
                            height: 60,
                            child: _NewsImage(
                              item: news,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$sourceName • Priority: $priority',
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 8),

                    // Metadata Badges & Editor Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Wrap(
                          spacing: 6,
                          children: [
                            // Status Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPub ? Colors.green.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: isPub ? Colors.green : Colors.amber),
                              ),
                              child: Text(
                                isPub ? 'Published' : 'Unpublished',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isPub ? Colors.green : Colors.amber,
                                ),
                              ),
                            ),
                            // Publication Source Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: pubSrc == 'editorial'
                                    ? Colors.blueAccent.withValues(alpha: 0.2)
                                    : Colors.white12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                pubSrc == 'editorial' ? 'Editorial' : 'Automated',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: pubSrc == 'editorial' ? Colors.blueAccent : Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Action Buttons
                        Row(
                          children: [
                            if (isPub)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Colors.amber,
                                ),
                                onPressed: () => _unpublishAdminNews(news),
                                icon: const Icon(Icons.visibility_off_outlined, size: 16),
                                label: const Text('👁‍🗨 Unpublish', style: TextStyle(fontSize: 12)),
                              )
                            else
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: const Color(0xFF00E676),
                                ),
                                onPressed: () => _publishExistingAdminNews(news),
                                icon: const Icon(Icons.publish_rounded, size: 16),
                                label: const Text('📢 Publish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                              tooltip: 'Delete permanently',
                              onPressed: () => _deleteAdminNews(news),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

      ],
    );
  }

  // --- Notifications Admin Methods ---
  final AppNotificationService _notificationService = AppNotificationService();
  List<AppNotificationItem> _adminNotifications = [];
  bool _loadingAdminNotifications = false;
  String _adminNotificationFilter = 'all';

  Future<void> _loadAdminNotifications() async {
    if (!mounted) return;
    setState(() => _loadingAdminNotifications = true);
    try {
      final list = await _notificationService.fetchAllNotifications(filter: _adminNotificationFilter);
      if (mounted) {
        setState(() {
          _adminNotifications = list;
          _loadingAdminNotifications = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAdminNotifications = false);
    }
  }

  void _showCreateNotificationDialog() {
    final titleCtrl = TextEditingController();
    final snippetCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final venueCtrl = TextEditingController();
    final regUrlCtrl = TextEditingController();
    final contactCtrl = TextEditingController();

    String notificationType = 'text'; // 'text', 'image', 'pdf'
    String category = 'General'; // General, Announcement, Event, Magazine, Community, Other
    DateTime? eventDate;
    bool isFeatured = false;
    int priority = 10;
    List<PlatformFile> selectedImageFiles = [];
    PlatformFile? selectedPdfFile;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isEvent = category == 'Event';

          return AlertDialog(
            backgroundColor: const Color(0xFF18221B),
            title: const Row(
              children: [
                Text('🔔 ', style: TextStyle(fontSize: 20)),
                Expanded(
                  child: Text('নতুন বিজ্ঞপ্তি তৈরি করুন',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('১. বিজ্ঞপ্তির ধরন (Type) *',
                                style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF121B12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: notificationType,
                                  dropdownColor: const Color(0xFF18221B),
                                  isExpanded: true,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  items: const [
                                    DropdownMenuItem(value: 'text', child: Text('📝 Text')),
                                    DropdownMenuItem(value: 'image', child: Text('📷 Image')),
                                    DropdownMenuItem(value: 'pdf', child: Text('📄 PDF')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setDlgState(() => notificationType = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ক্যাটাগরি (Category)',
                                style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF121B12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: category,
                                  dropdownColor: const Color(0xFF18221B),
                                  isExpanded: true,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  items: const [
                                    DropdownMenuItem(value: 'General', child: Text('General')),
                                    DropdownMenuItem(value: 'Announcement', child: Text('Announcement')),
                                    DropdownMenuItem(value: 'Event', child: Text('📅 Event')),
                                    DropdownMenuItem(value: 'Magazine', child: Text('Magazine')),
                                    DropdownMenuItem(value: 'Community', child: Text('Community')),
                                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setDlgState(() => category = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (isEvent) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121B12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📅 ইভেন্ট বিস্তারিত তথ্য (Event Metadata)',
                              style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white38),
                                  ),
                                  onPressed: () async {
                                    final pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: eventDate ?? DateTime.now().add(const Duration(days: 1)),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (pickedDate != null && context.mounted) {
                                      final pickedTime = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.now(),
                                      );
                                      if (pickedTime != null) {
                                        setDlgState(() {
                                          eventDate = DateTime(
                                            pickedDate.year,
                                            pickedDate.month,
                                            pickedDate.day,
                                            pickedTime.hour,
                                            pickedTime.minute,
                                          );
                                        });
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.event_rounded, size: 18),
                                  label: Text(
                                    eventDate != null
                                        ? '${eventDate!.day}/${eventDate!.month}/${eventDate!.year} ${eventDate!.hour}:${eventDate!.minute.toString().padLeft(2, '0')}'
                                        : 'Select Event Date & Time *',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: venueCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Venue / স্থান',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: regUrlCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Registration Link (নিবন্ধন ইউআরএল)',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: contactCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Contact Info / যোগাযোগ',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SwitchListTile(
                            value: isFeatured,
                            contentPadding: EdgeInsets.zero,
                            activeTrackColor: const Color(0xFF00E676),
                            title: const Text('Featured Event (বিশেষ ইভেন্ট)', style: TextStyle(color: Colors.white, fontSize: 12)),
                            onChanged: (v) => setDlgState(() => isFeatured = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const Text('২. শিরোনাম (Title) *',
                      style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'বিজ্ঞপ্তির শিরোনাম লিখুন...',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Color(0xFF121B12),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('৩. সংক্ষিপ্ত সারসংক্ষেপ (Snippet / Optional)',
                      style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: snippetCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'কার্ডে দেখানোর জন্য সংক্ষিপ্ত বিবরণ...',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Color(0xFF121B12),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (notificationType == 'text' || notificationType == 'image') ...[
                    Text(
                      notificationType == 'text' ? '৪. বিজ্ঞপ্তির মূল বিবরণ (Full Content) *' : '৪. বিষদ বিবরণ (Optional Content)',
                      style: const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: contentCtrl,
                      maxLines: 5,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'সম্পূর্ণ বিজ্ঞপ্তিটি বিশদভাবে লিখুন...',
                        hintStyle: TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Color(0xFF121B12),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (notificationType == 'image') ...[
                    const Text('৫. বিজ্ঞপ্তি সংক্রান্ত ছবি যুক্ত করুন *',
                        style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF81C784),
                        side: const BorderSide(color: Color(0xFF388E3C)),
                      ),
                      onPressed: () async {
                        final picked = await FilePicker.pickFiles(
                          type: FileType.image,
                        );
                        if (picked.isNotEmpty) {
                          setDlgState(() {
                            selectedImageFiles.addAll(picked);
                          });
                        }
                      },
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(selectedImageFiles.isEmpty ? 'ছবি বেছে নিন' : 'আরও ছবি (${selectedImageFiles.length})'),
                    ),
                    if (selectedImageFiles.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('নির্বাচিত ছবি: ${selectedImageFiles.length} টি', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                    const SizedBox(height: 16),
                  ],

                  if (notificationType == 'pdf') ...[
                    const Text('৪. PDF ফাইল আপলোড করুন *',
                        style: TextStyle(color: Color(0xFFFFB74D), fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFFB74D),
                        side: const BorderSide(color: Color(0xFFFFB74D)),
                      ),
                      onPressed: () async {
                        final picked = await FilePicker.pickFile(
                          type: FileType.custom,
                          allowedExtensions: ['pdf'],
                        );
                        if (picked != null) {
                          setDlgState(() {
                            selectedPdfFile = picked;
                          });
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(selectedPdfFile == null ? 'PDF ফাইল বেছে নিন' : 'নির্বাচিত: ${selectedPdfFile!.name}'),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const Text('প্রাধিকার মান (Editorial Priority 0–100):',
                      style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  Slider(
                    value: priority.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: const Color(0xFF00E676),
                    label: priority.toString(),
                    onChanged: (v) => setDlgState(() => priority = v.round()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800),
                onPressed: () => _submitNotification(
                  ctx: ctx,
                  titleCtrl: titleCtrl,
                  snippetCtrl: snippetCtrl,
                  contentCtrl: contentCtrl,
                  notificationType: notificationType,
                  priority: priority,
                  selectedImageFiles: selectedImageFiles,
                  selectedPdfFile: selectedPdfFile,
                  publishNow: false,
                  category: category,
                  eventDate: eventDate,
                  venue: venueCtrl.text.trim(),
                  registrationUrl: regUrlCtrl.text.trim(),
                  contactInfo: contactCtrl.text.trim(),
                  isFeatured: isFeatured,
                ),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('💾 Save Draft', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () => _submitNotification(
                  ctx: ctx,
                  titleCtrl: titleCtrl,
                  snippetCtrl: snippetCtrl,
                  contentCtrl: contentCtrl,
                  notificationType: notificationType,
                  priority: priority,
                  selectedImageFiles: selectedImageFiles,
                  selectedPdfFile: selectedPdfFile,
                  publishNow: true,
                  category: category,
                  eventDate: eventDate,
                  venue: venueCtrl.text.trim(),
                  registrationUrl: regUrlCtrl.text.trim(),
                  contactInfo: contactCtrl.text.trim(),
                  isFeatured: isFeatured,
                ),
                icon: const Icon(Icons.publish_rounded, size: 16),
                label: const Text('📢 Publish Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitNotification({
    required BuildContext ctx,
    required TextEditingController titleCtrl,
    required TextEditingController snippetCtrl,
    required TextEditingController contentCtrl,
    required String notificationType,
    required int priority,
    required List<PlatformFile> selectedImageFiles,
    required PlatformFile? selectedPdfFile,
    required bool publishNow,
    String category = 'General',
    DateTime? eventDate,
    String? venue,
    String? registrationUrl,
    String? contactInfo,
    bool isFeatured = false,
  }) async {
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে বিজ্ঞপ্তির শিরোনাম লিখুন')),
      );
      return;
    }

    if (notificationType == 'pdf' && selectedPdfFile == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে একটি PDF ফাইল নির্বাচন করুন')),
      );
      return;
    }

    Navigator.pop(ctx);

    try {
      final createdNotif = await _notificationService.createNotification(
        title: title,
        snippet: snippetCtrl.text.trim(),
        content: contentCtrl.text.trim(),
        notificationType: notificationType,
        imageFiles: selectedImageFiles,
        pdfFile: selectedPdfFile,
        priority: priority,
        publishNow: publishNow,
        category: category,
        eventDate: eventDate,
        venue: venue,
        registrationUrl: registrationUrl,
        contactInfo: contactInfo,
        isFeatured: isFeatured,
      );

      if (publishNow) {
        unawaited(AppNotifier.notify(
          title: createdNotif.isEvent ? '📅 ${createdNotif.title}' : '📢 ${createdNotif.title}',
          body: createdNotif.displaySnippet,
          data: {'type': 'app_notification', 'id': createdNotif.id},
        ));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(publishNow
                ? 'বিজ্ঞপ্তিটি সফলভাবে অ্যাপে প্রকাশ করা হয়েছে!'
                : 'বিজ্ঞপ্তিটি খসড়া হিসেবে সংরক্ষিত হয়েছে।'),
          ),
        );
      }
      _loadAdminNotifications();
      widget.onUploadComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('বিজ্ঞপ্তি সংরক্ষণ করতে সমস্যা: $e')),
        );
      }
    }
  }

  Widget _buildNotificationAdminSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🔔 বিজ্ঞপ্তি ব্যবস্থাপনা — Editorial Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('(সার্কুলার, দাপ্তরিক নির্দেশিকা ও বিশেষ নোটিশ প্রকাশ নিয়ন্ত্রণ)', style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
              tooltip: 'রিফ্রেশ করুন',
              onPressed: _loadAdminNotifications,
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: _showCreateNotificationDialog,
              icon: const Icon(Icons.add_alert_rounded, size: 18, color: Colors.white),
              label: const Text('➕ নতুন বিজ্ঞপ্তি প্রকাশ করুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              {'id': 'all', 'label': 'সবগুলো'},
              {'id': 'published', 'label': 'প্রকাশিত'},
              {'id': 'draft', 'label': 'খসড়া'},
              {'id': 'event', 'label': '📅 Event'},
              {'id': 'text', 'label': '📝 Text'},
              {'id': 'image', 'label': '📷 Image'},
              {'id': 'pdf', 'label': '📄 PDF'},
            ].map((filter) {
              final isSelected = _adminNotificationFilter == filter['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    filter['label']!,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00E676),
                  backgroundColor: const Color(0xFF18221B),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _adminNotificationFilter = filter['id']!;
                      });
                      _loadAdminNotifications();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (_loadingAdminNotifications)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
        else if (_adminNotifications.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text('এই বিভাগে কোনো বিজ্ঞপ্তি পাওয়া যায়নি।', style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adminNotifications.length,
            itemBuilder: (context, index) {
              final notif = _adminNotifications[index];
              final statusColor = notif.isPublished ? const Color(0xFF00E676) : Colors.amber;
              final statusText = notif.isPublished ? 'প্রকাশিত' : 'খসড়া (Draft)';

              return Card(
                color: const Color(0xFF18221B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF121B12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              notif.notificationType == 'pdf'
                                  ? Icons.picture_as_pdf_rounded
                                  : (notif.notificationType == 'image'
                                  ? Icons.image_rounded
                                  : Icons.notifications_active_rounded),
                              color: notif.notificationType == 'pdf'
                                  ? const Color(0xFFFFB74D)
                                  : (notif.notificationType == 'image'
                                  ? Colors.lightBlueAccent
                                  : const Color(0xFF81C784)),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ScientificText(
                                  notif.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: statusColor, width: 0.8),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Type: ${notif.notificationType.toUpperCase()}',
                                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00E676).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Priority: ${notif.editorialPriority}',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
                                      ),
                                    ),
                                    if (notif.category != 'General')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Cat: ${notif.category}',
                                          style: const TextStyle(fontSize: 10, color: Colors.purpleAccent),
                                        ),
                                      ),
                                    if (notif.isEvent && notif.eventDate != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '📅 ${notif.eventDate!.day}/${notif.eventDate!.month}/${notif.eventDate!.year}',
                                          style: const TextStyle(fontSize: 10, color: Colors.lightBlueAccent),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ScientificText(
                        notif.displaySnippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NotificationDetailScreen(notification: notif),
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility, size: 16),
                            label: const Text('পড়ুন'),
                          ),
                          if (!notif.isPublished)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await _notificationService.publishNotification(notif.id);
                                unawaited(AppNotifier.notify(
                                  title: notif.isEvent ? '📅 ${notif.title}' : '📢 ${notif.title}',
                                  body: notif.displaySnippet,
                                  data: {'type': 'app_notification', 'id': notif.id},
                                ));
                                _loadAdminNotifications();
                                widget.onUploadComplete();
                              },
                              icon: const Icon(Icons.publish_rounded, size: 16, color: Colors.black),
                              label: const Text('📢 Publish', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                            ),
                          if (notif.isPublished)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await _notificationService.unpublishNotification(notif.id);
                                _loadAdminNotifications();
                                widget.onUploadComplete();
                              },
                              icon: const Icon(Icons.visibility_off_rounded, size: 16),
                              label: const Text('Unpublish'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            tooltip: 'স্থায়ীভাবে মুছে ফেলুন',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF18221B),
                                  title: const Text('🗑 মুছে ফেলার নিশ্চিতকরণ', style: TextStyle(color: Colors.white)),
                                  content: Text('আপনি কি নিশ্চিত যে "${notif.title}" বিজ্ঞপ্তিটি স্থায়ীভাবে মুছে ফেলতে চান?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await _notificationService.deleteNotification(notif.id);
                                        _loadAdminNotifications();
                                        widget.onUploadComplete();
                                      },
                                      child: const Text('মুছে ফেলুন', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
