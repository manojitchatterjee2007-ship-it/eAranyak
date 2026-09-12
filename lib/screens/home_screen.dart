import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/app_notification_service.dart';
import '../models/app_notification.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/rotating_book_card.dart';
import 'magazine_reader_screen.dart';
import 'news_detail_screen.dart';
import 'expedition_tab.dart';
import 'notification_detail_screen.dart';
import 'nature_games_screen.dart';
import 'writing_submission_screen.dart';
import 'online_book_store_screen.dart';
import 'free_book_preview_screen.dart';
import 'library_screen.dart';

class NewsEditorialService {
  static String safeHeadline(String text) {
    if (text.isEmpty) return text;
    var cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  static void applyBengaliEditorial(Map<String, dynamic> item, {Map<String, dynamic>? translation}) {
    if (translation != null) {
      if ((translation['headline'] ?? '').toString().isNotEmpty) {
        item['title'] = translation['headline'];
      }
      if ((translation['dek'] ?? '').toString().isNotEmpty) {
        item['snippet'] = translation['dek'];
      }
      if ((translation['body'] ?? '').toString().isNotEmpty) {
        item['content'] = translation['body'];
      }
      return;
    }

    if ((item['bengali_headline'] ?? '').toString().isNotEmpty) {
      item['title'] = item['bengali_headline'];
    }
    if ((item['bengali_dek'] ?? '').toString().isNotEmpty) {
      item['snippet'] = item['bengali_dek'];
    }
    if ((item['bengali_body'] ?? '').toString().isNotEmpty) {
      item['content'] = item['bengali_body'];
    }
  }

  static bool hasUsableBengaliContent(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    final body = (item['content'] ?? '').toString();
    if (title.isEmpty || body.isEmpty) return false;
    final bengaliCharRegex = RegExp(r'[\u0980-\u09FF]');
    return bengaliCharRegex.hasMatch(title) || bengaliCharRegex.hasMatch(body);
  }

  static Future<bool> ensureBengaliEdition(Map<String, dynamic> item, {bool force = false}) async {
    final srcUrl = (item['source_url'] ?? '').toString();
    if (srcUrl.isEmpty) return false;

    if (!force && hasUsableBengaliContent(item)) {
      return false;
    }

    try {
      final res = await supabase.functions.invoke(
        'bengali-news-editor',
        body: {'source_url': srcUrl, 'force': force},
      );
      final data = res.data;
      if (data is Map<String, dynamic> && data['ok'] == true && data['article'] is Map) {
        final article = Map<String, dynamic>.from(data['article'] as Map);
        applyBengaliEditorial(item, translation: article);
        return true;
      }
    } catch (_) {}
    return false;
  }
}

class NewsImageFallbackWidget extends StatelessWidget {
  final String tags;
  final String category;

  const NewsImageFallbackWidget({super.key, required this.tags, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B2E1E),
      child: const Center(
        child: Icon(Icons.nature_people_rounded, color: Color(0xFF00E676), size: 42),
      ),
    );
  }
}

class NewsImageWidget extends StatelessWidget {
  final Map<String, dynamic> item;
  final BoxFit fit;

  const NewsImageWidget({super.key, required this.item, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final imgUrl = item['image_url']?.toString();
    final tags = item['img_tags']?.toString() ?? '';
    final cat = item['category']?.toString() ?? '';

    if (imgUrl != null && imgUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imgUrl,
        fit: fit,
        placeholder: (c, u) => Container(color: const Color(0xFF142419)),
        errorWidget: (c, u, e) => NewsImageFallbackWidget(tags: tags, category: cat),
      );
    }
    return NewsImageFallbackWidget(tags: tags, category: cat);
  }
}

class HomeScreen extends StatefulWidget {
  final String userEmail;
  final Function(int) onNavigateToTab;
  final String fullName;

  const HomeScreen({
    super.key,
    required this.userEmail,
    required this.onNavigateToTab,
    required this.fullName,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _issues = [];
  Timer? _autoShuffleTimer;
  int _lastAnimalSoundIndex = -1;
  final AudioPlayer _notificationAudioPlayer = AudioPlayer();

  String? _lastReadMagId;
  String? _lastReadTitle;
  int _lastReadPage = 0;
  int _lastReadTotalPages = 0;

  bool _travelExpanded = false;
  bool _travelContentVisible = false;

  final AppNotificationService _appNotificationService = AppNotificationService();

  static const List<String> _animalAudioAssets = [
    'audio/tiger_roar.mp3',
    'audio/elephant_trumpet.mp3',
    'audio/deer_call.mp3',
    'audio/owl_hoot.mp3',
  ];

  List<Map<String, dynamic>> _visibleNews = [];
  late final PageController _newsPageController;
  int _currentNewsPage = 0;

  final List<Map<String, dynamic>> _liveNews = [];
  List<AppNotification> _latestNotifications = [];
  bool _loadingNotifications = false;

  @override
  void initState() {
    super.initState();
    _newsPageController = PageController(viewportFraction: 0.85);
    _refreshVisibleNewsWindow();
    loadData();
    _loadContinueReadingSession();
    _startAutoNewsShufflingTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLiveNews();
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _triggerAnimalAcousticAlert();
      });
    });
  }

  @override
  void dispose() {
    _autoShuffleTimer?.cancel();
    _newsPageController.dispose();
    _notificationAudioPlayer.dispose();
    super.dispose();
  }

  void _refreshVisibleNewsWindow() {
    final combined = <Map<String, dynamic>>[
      ..._liveNews.map((e) => Map<String, dynamic>.from(e)),
    ]..shuffle();

    if (!mounted) {
      _visibleNews = combined.take(5).toList();
      return;
    }
    setState(() {
      _visibleNews = combined.take(5).toList();
    });
  }

  Future<void> _fetchLiveNews() async {
    try {
      final res = await supabase
          .from('wildlife_news')
          .select()
          .eq('is_published', true)
          .order('editorial_priority', ascending: false)
          .order('published_at', ascending: false)
          .limit(10);

      if (mounted) {
        final rawItems = List<Map<String, dynamic>>.from(res);
        final validItems = <Map<String, dynamic>>[];
        for (var item in rawItems) {
          NewsEditorialService.applyBengaliEditorial(item);
          final imageUrl = item['image_url']?.toString();
          final hasValidImage = imageUrl != null && imageUrl.trim().isNotEmpty;
          final title = item['bengali_headline']?.toString() ?? item['title']?.toString() ?? '';
          final content = item['bengali_body']?.toString() ?? item['snippet']?.toString() ?? '';
          final hasBengali = title.trim().isNotEmpty && content.trim().isNotEmpty;
          if (hasValidImage && hasBengali) {
            validItems.add(item);
          }
        }
        _liveNews.clear();
        _liveNews.addAll(validItems);
        _refreshVisibleNewsWindow();
      }
    } catch (_) {}
  }

  Future<void> _triggerAnimalAcousticAlert() async {
    if (SoundService.isMuted) return;
    try {
      int newIndex;
      do {
        newIndex = math.Random().nextInt(_animalAudioAssets.length);
      } while (
          newIndex == _lastAnimalSoundIndex && _animalAudioAssets.length > 1);
      _lastAnimalSoundIndex = newIndex;

      await _notificationAudioPlayer.stop();
      await _notificationAudioPlayer.setVolume(0.40);
      await _notificationAudioPlayer
          .play(AssetSource(_animalAudioAssets[newIndex]));
    } catch (_) {}
  }

  void _startAutoNewsShufflingTimer() {
    _autoShuffleTimer?.cancel();
    _autoShuffleTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (!mounted) return;
      _refreshVisibleNewsWindow();
      _triggerAnimalAcousticAlert();
    });
  }

  Future<void> loadData() async {
    await Future.wait([
      _loadMagazines(),
      _loadContinueReadingSession(),
      _fetchLiveNews(),
      _loadLatestNotifications(),
    ]);
  }

  Future<void> _loadMagazines() async {
    try {
      final res = await supabase
          .from('magazines')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _issues = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadContinueReadingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('last_read_mag_id');
      final title = prefs.getString('last_read_title');
      final page = prefs.getInt('last_read_page') ?? 0;
      final total = prefs.getInt('last_read_total_pages') ?? 0;

      if (id != null && mounted) {
        setState(() {
          _lastReadMagId = id;
          _lastReadTitle = title;
          _lastReadPage = page;
          _lastReadTotalPages = total;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadLatestNotifications() async {
    if (_loadingNotifications) return;
    setState(() => _loadingNotifications = true);
    try {
      final list = await _appNotificationService.fetchAllNotifications(filter: 'published');
      if (mounted) {
        setState(() {
          _latestNotifications = list;
          _loadingNotifications = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNotifications = false);
    }
  }

  void _toggleTravelExpanded() {
    SoundService.playButtonSound();
    setState(() {
      if (_travelExpanded) {
        _travelExpanded = false;
        _travelContentVisible = false;
      } else {
        _travelExpanded = true;
        _travelContentVisible = false;
        // Fade the content in on the following frame so it fades in
        // gently while AnimatedSize expands the drawer beneath the tab.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _travelExpanded) {
            setState(() => _travelContentVisible = true);
          }
        });
      }
    });
  }

  Widget _buildTravelSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FOREST EXPEDITION PORTAL TAB
          ExpeditionTab(
            onActivated: _toggleTravelExpanded,
            expanded: _travelExpanded,
          ),
          // Expedition drawer: the travel content emerges smoothly
          // beneath the tab (expand + gentle fade, no harsh transition).
          ClipRect(
            child: AnimatedSize(
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeInOutCubic,
              child: _travelExpanded
                  ? AnimatedOpacity(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                      opacity: _travelContentVisible ? 1.0 : 0.0,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _buildTravelContent(),
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelContent() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🌿', style: TextStyle(fontSize: 22)),
              SizedBox(width: 8),
              Text(
                'Travel with এখন আরণ্যক',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'প্রকৃতির আরও কাছে যাওয়ার পরিকল্পনা করছেন? 🌿',
            style: TextStyle(
              color: Color(0xFF81C784),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'আপনার পরবর্তী বনভ্রমণ, বন্যপ্রাণী পর্যবেক্ষণ, পাখি দেখা, প্রকৃতি অন্বেষণ বা অফবিট ভ্রমণের পরিকল্পনায় এখন আরণ্যক আপনার সঙ্গী হতে চায়।\n\nআপনি কোথায় যেতে চান, কতদিনের জন্য ভ্রমণের পরিকল্পনা করছেন, কী ধরনের অভিজ্ঞতা খুঁজছেন—আমাদের জানান। আমরা চেষ্টা করব আপনার যাত্রা পরিকল্পনা, গন্তব্য সম্পর্কে তথ্য এবং প্রয়োজনীয় পরামর্শ দিয়ে আপনাকে সাহায্য করতে।',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          // Coming soon section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF18221B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.2)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E2E23),
                  Color(0xFF18221B),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('🏡', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 10),
                    Text(
                      'Coming soon..............',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Exclusively "এখন আরণ্যক" maintained homestays in...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTravelPoint(
                    '🌲', 'the forests and foothills of North Bengal'),
                _buildTravelPoint(
                    '⛰️', 'the Himalayan landscapes of Sikkim and Darjeeling'),
                _buildTravelPoint('🦏',
                    "the wilderness surrounding Eastern India's great forests and wildlife landscapes"),
                const SizedBox(height: 16),
                const Text(
                  'প্রকৃতির একেবারে কাছাকাছি, শান্ত পরিবেশে, স্থানীয় সংস্কৃতি ও প্রকৃতির সঙ্গে যুক্ত এক বিশেষ ভ্রমণ অভিজ্ঞতা—খুব শিগগিরই।',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Stay close to nature. Travel responsibly. Discover the wild with এখন আরণ্যক. 🌿',
                  style: TextStyle(
                    color: Color(0xFF81C784),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Query section
          const Text(
            '💬 পরিকল্পনা করুন আপনার পরবর্তী যাত্রা',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'আপনার ভ্রমণ সংক্রান্ত যেকোনো প্রশ্ন আমাদের পাঠান।',
            style: TextStyle(
                color: Color(0xFF81C784),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          const Text(
            'আপনি জানতে চাইতে পারেন:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildQueryPoint(
              '🌲', 'কোথায় গেলে প্রকৃতির সবচেয়ে কাছাকাছি থাকা যাবে?'),
          _buildQueryPoint('🐦', 'পাখি দেখার জন্য কোন জায়গা উপযুক্ত?'),
          _buildQueryPoint(
              '🐅', 'Wildlife এবং বনভ্রমণের পরিকল্পনা কীভাবে করবেন?'),
          _buildQueryPoint('⛰️', 'পাহাড়, বন বা অফবিট গন্তব্য সম্পর্কে তথ্য'),
          _buildQueryPoint('🏡', 'ভবিষ্যতে আমাদের homestay সম্পর্কিত তথ্য'),
          const SizedBox(height: 16),
          const Text(
            'আপনার প্রশ্ন পাঠান—আমরা আপনাকে সাহায্য করার চেষ্টা করব।',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          KeyboardPressEffect(
            onTap: () => _openTravelQueryDialog(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      color: Colors.black, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'আপনার প্রশ্ন পাঠান (Send Query)',
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
        ],
      ),
    );
  }

  Widget _buildTravelPoint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryPoint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTravelQueryDialog() async {
    final msgCtrl = TextEditingController();
    bool sending = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF18221B),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Column(
            children: [
              Text('💬 Travel Query',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              SizedBox(height: 4),
              Text('(ভ্রমণ সংক্রান্ত প্রশ্ন)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF81C784))),
            ],
          ),
          content: TextField(
            controller: msgCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'আপনার প্রশ্ন লিখুন…',
              hintStyle: TextStyle(color: Colors.white38),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('বাতিল', style: TextStyle(color: Colors.white54)),
            ),
            KeyboardPressEffect(
              onTap: sending
                  ? null
                  : () async {
                      final msg = msgCtrl.text.trim();
                      if (msg.isEmpty) return;
                      setModalState(() => sending = true);
                      try {
                        await supabase.from('travel_queries').insert({
                          'message': msg,
                          'user_email': widget.userEmail,
                          'created_at': DateTime.now().toIso8601String(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    '✅ আপনার প্রশ্ন পাঠানো হয়েছে (Query sent successfully)')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString()}')),
                          );
                        }
                      } finally {
                        setModalState(() => sending = false);
                      }
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('পাঠান (Send)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(String phone) async {
    final uri = Uri.parse('https://wa.me/91$phone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Widget _buildNewsTextPanel(Map<String, dynamic> item, bool compact) {
    final TextStyle titleStyle = TextStyle(
      fontSize: compact ? 15 : 20,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: const Color(0xFF382B25),
    );
    final TextStyle snippetStyle = TextStyle(
      fontSize: compact ? 10 : 11,
      height: 1.25,
      color: const Color(0xFF5E5A53),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF3EFE6),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: PaperTexturePainter(seed: (item['title'] ?? '').hashCode),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 22,
              compact ? 10 : 16,
              compact ? 12 : 28,
              compact ? 10 : 16,
            ),
            child: LayoutBuilder(
              builder: (context, panelConstraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: panelConstraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB52B18),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  item['source']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item['date_str']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF746E66),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['title']?.toString() ?? '',
                          maxLines: compact ? 3 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['snippet']?.toString() ?? '',
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: snippetStyle,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB52B18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'পড়ুন',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeGameTile(BuildContext context, String bn, String en,
      String imageAsset, Color color, String type, VoidCallback onTap) {
    return KeyboardPressEffect(
      onTap: onTap,
      child: Container(
        width: 145,
        height: 145,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: CustomPaint(
                  painter: GameDiagramPainter(type: type, color: color),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            imageAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                alignment: Alignment.center,
                                color: color.withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.image_not_supported_rounded,
                                  size: 32,
                                  color: color,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(bn,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.2,
                            shadows: [
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                  offset: Offset(0, 1))
                            ])),
                    const SizedBox(height: 2),
                    Text(en,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 2)
                            ])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportantLinksSection() {
    const links = <Map<String, String>>[
      {
        'name': 'eBird',
        'url': 'https://ebird.org/',
        'logo': 'https://www.google.com/s2/favicons?sz=128&domain=ebird.org',
      },
      {
        'name': 'iNaturalist',
        'url': 'https://www.inaturalist.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=inaturalist.org',
      },
      {
        'name': 'Macaulay Library',
        'url': 'https://macaulaylibrary.org/',
        'logo': 'assets/images/macaulay_library.png',
      },
      {
        'name': 'Observation.org',
        'url': 'https://observation.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=observation.org',
      },
      {
        'name': 'Xeno-canto',
        'url': 'https://xeno-canto.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=xeno-canto.org',
      },
      {
        'name': 'Project Noah',
        'url': 'https://projectnoah.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=projectnoah.org',
      },
      {
        'name': 'BirdTrack',
        'url': 'https://www.birdtrack.net/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=birdtrack.net',
      },
      {
        'name': 'Ornitho',
        'url': 'https://www.ornitho.ch/',
        'logo': 'https://www.google.com/s2/favicons?sz=128&domain=ornitho.ch',
      },
      {
        'name': 'Mushroom Observer',
        'url': 'https://mushroomobserver.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=mushroomobserver.org',
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/important_links.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium),
              const SizedBox(width: 8),
              const Text(
                'Important Links',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Padding(
            padding: EdgeInsets.only(left: 28),
            child: Text(
              '(গুরুত্বপূর্ণ লিঙ্ক)',
              style: TextStyle(
                color: Color(0xFF81C784),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720
                  ? 6
                  : constraints.maxWidth >= 480
                  ? 5
                  : 4;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: links.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final link = links[index];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: KeyboardPressEffect(
                          onTap: () async {
                            final uri = Uri.parse(link['url']!);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/blank.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                                FractionallySizedBox(
                                  widthFactor: 0.6,
                                  heightFactor: 0.6,
                                  child: link['logo']!.startsWith('http')
                                      ? CachedNetworkImage(
                                          imageUrl: link['logo']!,
                                          fit: BoxFit.contain,
                                          placeholder: (context, url) =>
                                              const Center(
                                            child: SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              const Icon(
                                            Icons.public_rounded,
                                            color: Colors.white30,
                                            size: 20,
                                          ),
                                        )
                                      : Image.asset(
                                          link['logo']!,
                                          fit: BoxFit.contain,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        link['name']!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLatestNotificationsSection() {
    if (_loadingNotifications) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
      );
    }

    if (_latestNotifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 24, 18, 12),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, color: Color(0xFF00E676), size: 24),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('সর্বশেষ বিজ্ঞপ্তি', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('Latest Notifications & Announcements', style: TextStyle(fontSize: 10, color: Color(0xFF81C784))),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _latestNotifications.length,
            itemBuilder: (context, index) {
              final notif = _latestNotifications[index];
              return Container(
                width: 260,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Card(
                  color: const Color(0xFF18221B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      SoundService.playButtonSound();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationDetailScreen(notification: notif),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notif.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notif.snippet ?? notif.content ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${notif.createdAt.day}/${notif.createdAt.month}/${notif.createdAt.year}',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                              const Text('পড়ুন ↗', style: TextStyle(fontSize: 10, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
        color: const Color(0xFF00E676),
        onRefresh: () async {
          await loadData();
          _refreshVisibleNewsWindow();
          await _triggerAnimalAcousticAlert();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // 1) CONTINUE READING SECTION
            if (_lastReadMagId != null && _lastReadTotalPages > 0) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image(
                            image:
                                AssetImage('assets/images/continue_reading.png'),
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain),
                        SizedBox(width: 8),
                        Text('Continue Reading',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 30),
                      child: Text('(পড়া জারি রাখুন)',
                          style:
                          TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF142419),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 65,
                      decoration: BoxDecoration(
                          color: const Color(0xFF1E2E23),
                          borderRadius: BorderRadius.circular(6)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: CachedNetworkImage(
                          imageUrl: supabase.storage
                              .from('magazine_pages')
                              .getPublicUrl('$_lastReadMagId/page_1.jpg'),
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => const Icon(
                              Icons.menu_book_rounded,
                              color: Color(0xFF00E676),
                              size: 26),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_lastReadTitle ?? 'eআরণ্যক',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                              'Page ${_lastReadPage + 1} / $_lastReadTotalPages (${((_lastReadPage + 1) / _lastReadTotalPages * 100).round()}% Completed)',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF81C784))),
                          Text(
                            '(পৃষ্ঠা ${_lastReadPage + 1} / $_lastReadTotalPages)',
                            style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                                value: (_lastReadPage + 1) / _lastReadTotalPages,
                                minHeight: 5,
                                backgroundColor: Colors.white12,
                                color: const Color(0xFF00E676)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    KeyboardPressEffect(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProtectedReaderScreen(
                                magazineId: _lastReadMagId!,
                                title: _lastReadTitle ?? 'eআরণ্যক',
                                userEmail: widget.userEmail,
                                initialPage: _lastReadPage),
                          ),
                        ).then((_) => _loadContinueReadingSession());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/images/resume.png',
                                width: 24,
                                height: 24,
                                filterQuality: FilterQuality.medium),
                            const SizedBox(width: 6),
                            const Text('Resume (চালিয়ে যান)',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.black)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 2) CURRENT HAPPENINGS & WILDLIFE NEWS CAROUSEL
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image(
                          image: AssetImage('assets/images/latest_news.png'),
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Current Happenings & Wildlife News',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 30),
                    child: Text(
                        '(চলতি ঘটনা ও বন্যপ্রাণ বার্তা - প্রতি ২ মিনিটে ৫টি নির্বাচিত খবর)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 292,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _newsPageController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _visibleNews.length,
                        onPageChanged: (index) {
                          if (mounted) {
                            setState(() {
                              _currentNewsPage = index;
                            });
                          }
                        },
                        itemBuilder: (context, index) {
                          final item = _visibleNews[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              margin: EdgeInsets.zero,
                              color: const Color(0xFFF2EEE3),
                              elevation: 7,
                              shadowColor: Colors.black54,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          NewsDetailScreen(newsItem: item),
                                    ),
                                  );
                                },
                                child: LayoutBuilder(
                                  builder: (context, cardConstraints) {
                                    final bool compact =
                                        cardConstraints.maxWidth < 600;
                                    final double artFlex = compact ? 1 : 62;
                                    final double textFlex = compact ? 1 : 38;
                                    return Flex(
                                      direction: compact
                                          ? Axis.vertical
                                          : Axis.horizontal,
                                      children: [
                                        Expanded(
                                          flex: compact ? 1 : artFlex.toInt(),
                                          child: ClipRect(
                                            child: NewsImageWidget(item: item),
                                          ),
                                        ),
                                        Expanded(
                                          flex: compact ? 1 : textFlex.toInt(),
                                          child:
                                          _buildNewsTextPanel(item, compact),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_visibleNews.length > 1)
                        Positioned(
                          left: 16,
                          top: 0,
                          bottom: 30,
                          child: Center(
                            child: Material(
                              color: const Color(0xFFF7F3E8)
                                  .withValues(alpha: 0.92),
                              elevation: 3,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  final prev = (_currentNewsPage - 1 +
                                          _visibleNews.length) %
                                      _visibleNews.length;
                                  _newsPageController.animateToPage(
                                    prev,
                                    duration:
                                        const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    color: Color(0xFF1B241D),
                                    size: 21,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_visibleNews.length > 1)
                        Positioned(
                          right: 16,
                          top: 0,
                          bottom: 30,
                          child: Center(
                            child: Material(
                              color:
                              const Color(0xFFF7F3E8).withValues(alpha: 0.92),
                              elevation: 3,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  final next = (_currentNewsPage + 1) %
                                      _visibleNews.length;
                                  _newsPageController.animateToPage(
                                    next,
                                    duration: const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Color(0xFF1B241D),
                                    size: 21,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_visibleNews.length > 1)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _visibleNews.length,
                                  (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: index == _currentNewsPage ? 18 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: index == _currentNewsPage
                                      ? const Color(0xFF1A201A)
                                      : const Color(0xFF8A8B86),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // 3) LATEST RELEASE SECTION
            if (_issues.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image(
                            image:
                                AssetImage('assets/images/latest_release.png'),
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain),
                        SizedBox(width: 8),
                        Text('Latest Release',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 30),
                      child: Text('(সদ্য প্রকাশিত সংখ্যা)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF81C784))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                    color: const Color(0xFF18221B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 110,
                        height: 155,
                        decoration: BoxDecoration(
                            color: const Color(0xFF1E2E23),
                            borderRadius: BorderRadius.circular(8)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: supabase.storage
                                .from('magazine_pages')
                                .getPublicUrl(
                                '${_issues.first['id']}/page_1.jpg'),
                            fit: BoxFit.cover,
                            placeholder: (c, u) => const Center(
                                child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF00E676)))),
                            errorWidget: (c, u, e) => const Icon(
                                Icons.menu_book_rounded,
                                color: Color(0xFF00E676),
                                size: 42),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_issues.first['title'] ?? 'eআরণ্যক',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const SizedBox(height: 6),
                            Text(
                                '${_issues.first['issue_date']} • Total ${_issues.first['total_pages']} Pages',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 20),
                            KeyboardPressEffect(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LibraryScreen(
                                      userEmail: widget.userEmail,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset('assets/images/read_full_issue.png',
                                        width: 30,
                                        height: 30,
                                        filterQuality: FilterQuality.medium),
                                    const SizedBox(width: 10),
                                    const Flexible(
                                      child: Text(
                                        'Download from Library (লাইব্রেরি থেকে ডাউনলোড করুন)',
                                        maxLines: 2,
                                        softWrap: true,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.black),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 4) NATURE STUDY THROUGH GAMES SECTION
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image(
                          image: AssetImage(
                              'assets/images/nature_study_through_games.png'),
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain),
                      SizedBox(width: 8),
                      Text('খেলার ছলে প্রকৃতি পাঠ',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 30),
                    child: Text('(Nature Study through Games)',
                        style: TextStyle(fontSize: 10, color: Color(0xFF81C784))),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _buildHomeGameTile(
                    context,
                    'আলোকচিত্র চেনা',
                    'Identify Photos',
                    'assets/images/identify_image.png',
                    const Color(0xFF2E7D32),
                    'photo',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const WildlifeQuizGame(type: 'photo'))),
                  ),
                  const SizedBox(width: 12),
                  _buildHomeGameTile(
                    context,
                    'ডাক শুনে চেনা',
                    'Identify from Call',
                    'assets/images/identify_call.png',
                    const Color(0xFF00897B),
                    'audio',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const WildlifeQuizGame(type: 'audio'))),
                  ),
                  const SizedBox(width: 12),
                  _buildHomeGameTile(
                    context,
                    'ইঙ্গিত বুঝে চেনা',
                    'Identify Hints',
                    'assets/images/identify_clue.png',
                    const Color(0xFF1B5E20),
                    'hint',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const WildlifeQuizGame(type: 'hint'))),
                  ),
                  const SizedBox(width: 12),
                  _buildHomeGameTile(
                    context,
                    'টুকরো ছবি জোড়া',
                    'Scrambled Image',
                    'assets/images/zigshaw_puzzle.png',
                    const Color(0xFFE65100),
                    'puzzle',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ScrambledImageGame())),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 5) COMMUNITY ARTICLE SUBMISSION CALL TO ACTION BANNER
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF142419),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: Color(0xFF00E676), size: 24),
                      SizedBox(width: 10),
                      Text('✍️ এখন আরণ্যকের জন্য কলম ধরুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('🌿 প্রকৃতি নিয়ে আপনার ভাবনা আমাদের সঙ্গে ভাগ করে নিন', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  const Text('প্রকৃতি, বন, বন্যপ্রাণী, পাখি বা পরিবেশ নিয়ে আপনার অভিজ্ঞতা, পর্যবেক্ষণ এবং ভাবনা পৌঁছে দিন এখন আরণ্যক-এর কাছে।\n\nআপনার লেখা প্রবন্ধ (এক হাজার শব্দের মধ্যে) এবং সেই বিষয়ের সঙ্গে সম্পর্কিত আপনার নিজের তোলা ছবি আমাদের পাঠাতে পারেন।\n\nনির্বাচিত লেখা ও ছবি প্রকাশিত হতে পারে এখন আরণ্যক App-এ।\n\n🌿 লিখুন। প্রকৃতিকে অনুভব করুন। আপনার অভিজ্ঞতা অন্যদের সঙ্গে ভাগ করে নিন।', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () {
                        SoundService.playButtonSound();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WritingSubmissionScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      label: const Text('✍️ এখানে আপনার লেখা জমা দিন ➔', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 6) ARANYAK PUBLISHED BOOKS & ONLINE BOOK STORE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 700;
                  return isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildPublishedBooksCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildOnlineStoreBannerCard()),
                          ],
                        )
                      : Column(
                          children: [
                            _buildPublishedBooksCard(),
                            const SizedBox(height: 16),
                            _buildOnlineStoreBannerCard(),
                          ],
                        );
                },
              ),
            ),
            const SizedBox(height: 24),

            // 7) FOREST EXPEDITION PORTAL
            _buildTravelSection(),
            const SizedBox(height: 24),

            // 8) IMPORTANT LINKS SECTION
            _buildImportantLinksSection(),
            const SizedBox(height: 32),

            // 9) LATEST NOTIFICATIONS (if any)
            _buildLatestNotificationsSection(),
            const SizedBox(height: 32),
          ],
        ),
      );
  }

  Widget _buildPublishedBooksCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'এখন আরণ্যক প্রকাশিত বই',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const Text(
          '(Aranyak Published Books)',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF81C784),
          ),
        ),
        const SizedBox(height: 12),
        const AranyakHardboundBookCard(),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _openWhatsApp('9432569171'),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WhatsAppLogo(size: 34),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '9432569171',
                      style: TextStyle(
                        color: Color(0xFF25D366),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '(বইটি কেনার জন্য যোগাযোগ করুন)',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineStoreBannerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF18221B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🛒 অনলাইন বই অর্ডার', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 2),
          const Text('(Ekhon Aranyak Online Book Store)', style: TextStyle(color: Color(0xFF81C784), fontSize: 10)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF121B12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storefront_rounded, color: Color(0xFF00E676), size: 18),
                    SizedBox(width: 8),
                    Text('অন্যান্য প্রকাশনা থেকে প্রকাশিত বইঘর', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                SizedBox(height: 6),
                Text('এখন আরণ্যকের সহযোগিতায় ও অন্যান্য প্রথিতযশা প্রকাশনা থেকে প্রকাশিত বন্যপ্রাণ ও প্রকৃতি বিষয়ক বইসমূহ অনলাইন ক্যাটালগ থেকে পছন্দ করুন এবং সরাসরি অর্ডার করুন।', style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: () {
                SoundService.playButtonSound();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OnlineBookStoreScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.shopping_bag_rounded, color: Colors.black, size: 18),
              label: const Text('🛒 বই ঘর খুলুন', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
