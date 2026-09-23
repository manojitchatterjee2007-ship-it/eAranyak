import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/forest_ambience_service.dart';
import '../services/forest_scene_manager.dart';
import '../widgets/magazine_cover_image.dart';
import '../widgets/realistic_rack_widget.dart';

class LibraryScreen extends StatefulWidget {
  final String userEmail;
  const LibraryScreen({super.key, required this.userEmail});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _magazines = [];
  List<Map<String, dynamic>> _filteredMagazines = [];
  bool _loading = true;
  int _sceneIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _downloadStates = {};

  @override
  void initState() {
    super.initState();
    _loadSceneIndex();
    _loadMagazines();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadSceneIndex() async {
    final idx = await ForestSceneManager.pickFor('library');
    if (mounted) {
      setState(() {
        _sceneIndex = idx;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMagazines() async {
    setState(() => _loading = true);
    try {
      final magRes = await _supabase.from('magazines').select().order('created_at', ascending: false);
      final mags = List<Map<String, dynamic>>.from(magRes);

      final prefs = await SharedPreferences.getInstance();
      for (final mag in mags) {
        final id = mag['id'].toString();
        final downloaded = prefs.getBool('downloaded_mag_$id') ?? false;
        _downloadStates[id] = downloaded ? 'downloaded' : 'none';
      }

      if (mounted) {
        setState(() {
          _magazines = mags;
          _filteredMagazines = mags;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadMagazine(Map<String, dynamic> mag) async {
    final id = mag['id'].toString();
    setState(() {
      _downloadStates[id] = 'downloading';
    });

    try {
      final pages = await _supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', id)
          .limit(1);

      if (pages.isEmpty) {
        throw Exception('Magazine pages not found');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_mag_$id', true);

      List<String> downloadedIds = prefs.getStringList('downloaded_magazine_ids') ?? [];
      if (!downloadedIds.contains(id)) {
        downloadedIds.add(id);
        await prefs.setStringList('downloaded_magazine_ids', downloadedIds);
      }
      await prefs.setString('mag_meta_$id', jsonEncode(mag));

      if (mounted) {
        setState(() {
          _downloadStates[id] = 'downloaded';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ "${mag['title']}" সফলভাবে ডাউনলোড হয়েছে এবং আপনার বুকশেলফে যুক্ত হয়েছে!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadStates[id] = 'none';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ডাউনলোড ব্যর্থ হয়েছে: ${e.toString()}')),
        );
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredMagazines = _magazines;
      } else {
        _filteredMagazines = _magazines.where((m) {
          final title = (m['title'] ?? '').toLowerCase();
          final date = (m['issue_date'] ?? '').toLowerCase();
          return title.contains(query) || date.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final magazineCards = _filteredMagazines.map((mag) {
      final id = mag['id'].toString();
      final title = formatMagazineTitle(mag['title']?.toString());
      final issueDate = mag['issue_date']?.toString() ?? '';
      final downloadState = _downloadStates[id] ?? 'none';

      return GestureDetector(
        onTap: () {
          SoundService.playButtonSound();
          if (downloadState != 'downloaded') {
            // FIX: Stop ambience before launching reader
            ForestAmbienceService.stopAmbience();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MagazinePreviewScreen(
                  magazineId: id,
                  title: title,
                  onDownloadTriggered: () => _downloadMagazine(mag),
                ),
              ),
            ).then((_) {
              // FIX: Restart ambience when returning to Library
              ForestAmbienceService.startAmbience();
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('এই ম্যাগাজিনটি ইতিমধ্যে আপনার বুকশেলফে রয়েছে! (Already in Bookshelf)')),
            );
          }
        },
        child: Container(
          width: 170,
          height: 235,
          decoration: BoxDecoration(
            color: const Color(0xFF152018),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MagazineCoverImage(
                  magazineId: id,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 170 - 16),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      issueDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    color: Colors.black.withValues(alpha: 0.88),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        downloadState == 'downloaded'
                            ? Container(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: const Color(0xFF00E676)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_rounded, color: Color(0xFF00E676), size: 14),
                                    SizedBox(width: 4),
                                    Text('সংরক্ষিত', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )
                            : downloadState == 'downloading'
                                ? const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)),
                                    ),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00E676),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                    ),
                                    onPressed: () {
                                      SoundService.playButtonSound();
                                      _downloadMagazine(mag);
                                    },
                                    child: const Text('ডাউনলোড', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.85),
        title: const Text('📚  Library - লাইব্রেরি', style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00E676)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              ForestSceneManager.assetPath(_sceneIndex),
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142018).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'প্রকৃতি ও বন্যপ্রাণ ডিজিটাল ম্যাগাজিন লাইব্রেরি',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'মেটাল র্যাকে ম্যাগাজিনগুলো সাজানো রয়েছে।',
                          style: TextStyle(color: Color(0xFF81C784), fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'ম্যাগাজিনের নাম বা তারিখ দিয়ে খুঁজুন...',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E676)),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      FocusScope.of(context).unfocus();
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF0D1410),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF00E676), width: 1.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                        : _filteredMagazines.isEmpty
                            ? Center(
                                child: Container(
                                  padding: const EdgeInsets.all(28),
                                  margin: const EdgeInsets.symmetric(horizontal: 24),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF142018).withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.newspaper_rounded, size: 52, color: Color(0xFF81C784)),
                                      SizedBox(height: 14),
                                      Text(
                                        'কোনো ম্যাগাজিন পাওয়া যায়নি',
                                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'অনুগ্রহ করে অন্য শব্দ দিয়ে খুঁজুন অথবা পরবর্তীতে আবার চেষ্টা করুন।',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : RealisticRackWidget(
                                isWooden: false,
                                children: magazineCards,
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
}

class MagazinePreviewScreen extends StatefulWidget {
  final String magazineId;
  final String title;
  final VoidCallback onDownloadTriggered;

  const MagazinePreviewScreen({
    super.key,
    required this.magazineId,
    required this.title,
    required this.onDownloadTriggered,
  });

  @override
  State<MagazinePreviewScreen> createState() => _MagazinePreviewScreenState();
}

class _MagazinePreviewScreenState extends State<MagazinePreviewScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlipbookController _flipbookController = FlipbookController();
  final AudioPlayer _flipPlayer = AudioPlayer(); // FIX: Added page flip sound engine
  List<FlipbookPage?> _flipbookPages = [];
  bool _isLoading = true;
  bool _showDownloadPrompt = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
    _fetchPreviewPages();
  }

  Future<void> _initAudio() async {
    try {
      await _flipPlayer.setPlayerMode(PlayerMode.lowLatency);
    } catch (_) {}
  }

  @override
  void dispose() {
    _flipPlayer.dispose();
    super.dispose();
  }

  Future<void> _playFlipSound() async {
    if (!SoundService.isMuted) {
      try {
        await _flipPlayer.stop();
        await _flipPlayer.play(AssetSource('audio/page_flip.mp3'));
      } catch (_) {}
    }
  }

  Future<void> _fetchPreviewPages() async {
    try {
      final pages = await _supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', widget.magazineId)
          .order('page_number', ascending: true)
          .limit(4); 

      final List<FlipbookPage?> builtPages = [null]; 
      
      for (final p in pages) {
        final signedUrl = await _supabase.storage
            .from('magazine_pages')
            .createSignedUrl(p['storage_path'], 120);
        final provider = NetworkImage(signedUrl);
        builtPages.add(FlipbookPage(image: provider, hiResImage: provider));
      }

      if (mounted) {
        setState(() {
          _flipbookPages = builtPages;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _checkPageEnd() {
    if (_flipbookController.page >= _flipbookPages.length - 1) {
      setState(() => _showDownloadPrompt = true);
    } else {
      setState(() => _showDownloadPrompt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        title: Text('${formatMagazineTitle(widget.title)} (Preview)', style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF00E676)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00E676)),
                  SizedBox(height: 16),
                  Text('প্রিভিউ লোড হচ্ছে...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                RealisticFlipbook(
                  controller: _flipbookController,
                  pages: _flipbookPages,
                  singlePage: false,
                  // FIX: Trigger audio on flip start
                  onFlipLeftStart: (_) => _playFlipSound(),
                  onFlipRightStart: (_) => _playFlipSound(),
                  onFlipLeftEnd: (_) => _checkPageEnd(),
                  onFlipRightEnd: (_) => _checkPageEnd(),
                ),
                if (_showDownloadPrompt)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.85),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          margin: const EdgeInsets.symmetric(horizontal: 32),
                          decoration: BoxDecoration(
                            color: const Color(0xFF142018),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              )
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.workspace_premium_rounded, color: Color(0xFF00E676), size: 48),
                              const SizedBox(height: 16),
                              const Text(
                                'সম্পূর্ণ ম্যাগাজিনটি পড়তে ডাউনলোড করুন',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Download to your bookshelf to read the full issue.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E676),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  Navigator.pop(context); // Close preview
                                  widget.onDownloadTriggered(); // Trigger download in Library
                                },
                                icon: const Icon(Icons.download_rounded, size: 20),
                                label: const Text('ডাউনলোড করুন (Download)', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
              ],
            ),
    );
  }
}