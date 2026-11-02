import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/forest_ambience_service.dart';
import '../services/forest_scene_manager.dart';
import '../services/magazine_download_service.dart';
import '../widgets/magazine_cover_image.dart';
import '../widgets/realistic_rack_widget.dart';
import '../widgets/seamless_scrolling_background.dart';
import 'magazine_preview_screen.dart';
import 'magazine_reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  final String userEmail;
  const LibraryScreen({super.key, required this.userEmail});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  SupabaseClient get _supabase => supabase;
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
    MagazineDownloadService.progressNotifier.addListener(_syncActiveDownloads);
  }

  void _syncActiveDownloads() {
    if (!mounted) return;
    final map = MagazineDownloadService.progressNotifier.value;
    bool changed = false;
    for (final entry in map.entries) {
      final id = entry.key;
      final progress = entry.value;
      final current = _downloadStates[id];
      final target = progress.isCompleted
          ? 'downloaded'
          : progress.error != null
              ? 'none'
              : 'downloading';
      if (current != target) {
        _downloadStates[id] = target;
        changed = true;
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
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
    MagazineDownloadService.progressNotifier.removeListener(_syncActiveDownloads);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMagazines() async {
    setState(() => _loading = true);
    try {
      final magRes = await _supabase
          .from('magazines')
          .select()
          .order('created_at', ascending: false);
      final mags = List<Map<String, dynamic>>.from(magRes);

      for (final mag in mags) {
        final id = mag['id'].toString();
        if (_downloadStates[id] == 'downloading' ||
            MagazineDownloadService.isDownloading(id)) {
          _downloadStates[id] = 'downloading';
          continue;
        }
        final isDownloaded =
            await MagazineDownloadService.isMagazineDownloaded(id);
        _downloadStates[id] = isDownloaded ? 'downloaded' : 'none';
      }

      if (mounted) {
        setState(() {
          _magazines = mags;
          _filteredMagazines = mags;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[LibraryScreen] _loadMagazines error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadMagazine(Map<String, dynamic> mag) async {
    final id = mag['id'].toString();
    final title = formatMagazineTitle(mag['title']?.toString());
    if (_downloadStates[id] == 'downloading' ||
        MagazineDownloadService.isDownloading(id)) {
      return;
    }
    setState(() {
      _downloadStates[id] = 'downloading';
    });

    final success = await MagazineDownloadService.downloadMagazine(
      magazine: mag,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _downloadStates[id] = p.isCompleted
                ? 'downloaded'
                : p.error != null
                    ? 'none'
                    : 'downloading';
          });
        }
      },
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _downloadStates[id] = 'downloaded';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF142419),
          content: Text(
              '✓ "$title" সম্পূর্ণ ম্যাগাজিনটি সফলভাবে ডাউনলোড হয়েছে এবং আপনার বুকশেলফে যুক্ত হয়েছে!'),
          action: SnackBarAction(
            label: 'পড়ুন (Read)',
            textColor: const Color(0xFF00E676),
            onPressed: () {
              ForestAmbienceService.stopAmbience();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProtectedReaderScreen(
                    magazineId: id,
                    title: title,
                    userEmail: widget.userEmail,
                  ),
                ),
              ).then((_) {
                ForestAmbienceService.startAmbience();
                _loadMagazines();
              });
            },
          ),
        ),
      );
    } else {
      setState(() {
        _downloadStates[id] = 'none';
      });
      final errorDetail =
          MagazineDownloadService.progressNotifier.value[id]?.error ??
              'Unknown error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF321313),
          content: Text('ডাউনলোড ব্যর্থ হয়েছে: $errorDetail'),
          action: SnackBarAction(
            label: 'পুনরায় চেষ্টা (Retry)',
            textColor: const Color(0xFFFF5252),
            onPressed: () => _downloadMagazine(mag),
          ),
        ),
      );
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
    final List<Widget> magazineCards = [];
    final List<String> issueLabels = [];

    for (final mag in _filteredMagazines) {
      final id = mag['id'].toString();
      final title = formatMagazineTitle(mag['title']?.toString());
      final issueDate = mag['issue_date']?.toString() ?? '';
      final downloadState = _downloadStates[id] ?? 'none';

      issueLabels.add(issueDate);

      magazineCards.add(
        GestureDetector(
          onTap: () {
            SoundService.playButtonSound();
            if (downloadState == 'downloaded') {
              ForestAmbienceService.stopAmbience();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProtectedReaderScreen(
                    magazineId: id,
                    title: title,
                    userEmail: widget.userEmail,
                  ),
                ),
              ).then((_) {
                ForestAmbienceService.startAmbience();
                _loadMagazines();
              });
            } else if (downloadState == 'downloading') {
              final p = MagazineDownloadService.progressNotifier.value[id];
              final msg = p?.statusMessage ?? 'ম্যাগাজিনটি বর্তমানে ডাউনলোড হচ্ছে...';
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF142018),
                  duration: const Duration(seconds: 2),
                  content: Text(msg),
                ),
              );
            } else {
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
                ForestAmbienceService.startAmbience();
                _loadMagazines();
              });
            }
          },
          child: Container(
            width: 170,
            height: 235,
            decoration: BoxDecoration(
              color: const Color(0xFF152018),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35)),
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
                    bottom: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        if (downloadState == 'none') {
                          SoundService.playButtonSound();
                          _downloadMagazine(mag);
                        } else if (downloadState == 'downloaded') {
                          SoundService.playButtonSound();
                          ForestAmbienceService.stopAmbience();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProtectedReaderScreen(
                                magazineId: id,
                                title: title,
                                userEmail: widget.userEmail,
                              ),
                            ),
                          ).then((_) {
                            ForestAmbienceService.startAmbience();
                            _loadMagazines();
                          });
                        } else if (downloadState == 'downloading') {
                          SoundService.playButtonSound();
                          final p = MagazineDownloadService.progressNotifier.value[id];
                          final msg = p?.statusMessage ?? 'ম্যাগাজিনটি বর্তমানে ডাউনলোড হচ্ছে...';
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF142018),
                              duration: const Duration(seconds: 2),
                              content: Text(msg),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF00E676), width: 1),
                        ),
                        child: downloadState == 'downloaded'
                            ? const Icon(Icons.check_rounded,
                                color: Color(0xFF00E676), size: 16)
                            : downloadState == 'downloading'
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF00E676)),
                                  )
                                : const Icon(Icons.download_rounded,
                                    color: Color(0xFF00E676), size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.85),
        title: const Text('📚  Library - লাইব্রেরি',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00E676)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SeamlessScrollingBackground(
              imagePath: ForestSceneManager.assetPath(_sceneIndex),
              duration: const Duration(seconds: 40),
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
                      border: Border.all(
                          color:
                              const Color(0xFF00E676).withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 10),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'প্রকৃতি ও বন্যপ্রাণ ডিজিটাল ম্যাগাজিন লাইব্রেরি',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'মেটাল র্যাকে ম্যাগাজিনগুলো সাজানো রয়েছে।',
                          style:
                              TextStyle(color: Color(0xFF81C784), fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'ম্যাগাজিনের নাম বা তারিখ দিয়ে খুঁজুন...',
                            hintStyle: const TextStyle(
                                color: Colors.white38, fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: Color(0xFF00E676)),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        color: Colors.white54, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      FocusScope.of(context).unfocus();
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF0D1410),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 0, horizontal: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF00E676), width: 1.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF00E676)))
                        : RealisticRackWidget(
                            isWooden: false,
                            issueLabels: issueLabels,
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
