import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/protected_asset_service.dart';
import '../services/sound_service.dart';
import '../core/config.dart';
import '../widgets/magazine_flipbook_layout_gate.dart';
import '../widgets/magazine_cover_image.dart';

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
  SupabaseClient get _supabase => supabase;
  final FlipbookController _flipbookController = FlipbookController();
  final AudioPlayer _flipPlayer = AudioPlayer();
  final Stopwatch _openStopwatch = Stopwatch();

  List<FlipbookPage> _flipbookPages = [];
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;
  bool _loggedFirstLayout = false;
  bool _showDownloadPrompt = false;
  bool _isFlipping = false;

  @override
  void initState() {
    super.initState();
    _openStopwatch.start();
    debugPrint('[MagazinePreview] opened issue=${widget.magazineId} t=0ms');
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
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    debugPrint(
        '[MagazinePreview] page data loading issue=${widget.magazineId} t=${_openStopwatch.elapsedMilliseconds}ms');

    try {
      final pagesRes = await _supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', widget.magazineId)
          .order('page_number', ascending: true)
          .limit(4);

      final pages = List<Map<String, dynamic>>.from(pagesRes);
      if (pages.isEmpty) {
        throw StateError('No preview pages are available.');
      }
      debugPrint(
          '[MagazinePreview] page catalog received count=${pages.length} t=${_openStopwatch.elapsedMilliseconds}ms');

      // Request signed URLs in parallel to eliminate serial network latency
      final signedUrls = await Future.wait(
        pages.map((p) => ProtectedAssetService.getSignedUrl(
              bucket: 'magazine_pages',
              storagePath: p['storage_path']?.toString() ?? '',
              expiresInSeconds: 300,
            )),
      );

      if (!mounted || generation != _loadGeneration) return;

      final List<FlipbookPage> builtPages = [];
      final List<ImageProvider> providers = [];

      for (int i = 0; i < signedUrls.length; i++) {
        final url = signedUrls[i]?.trim();
        if (url != null && url.isNotEmpty) {
          final provider = CachedNetworkImageProvider(url);
          providers.add(provider);
          builtPages.add(FlipbookPage(
            image: provider,
            hiResImage: provider,
            sizeHint: const Size(1000, 1414),
          ));
        }
      }

      if (builtPages.isEmpty) {
        throw StateError('No preview pages could be signed.');
      }

      debugPrint(
          '[MagazinePreview] page data ready issue=${widget.magazineId} pages=${builtPages.length} t=${_openStopwatch.elapsedMilliseconds}ms');

      // Precache first visible spread before removing the loading overlay
      final isLandscapeSpread = mounted &&
          MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
      final initialSpreadCount = isLandscapeSpread ? 2 : 1;
      final precacheCount = math.min(initialSpreadCount, providers.length);

      debugPrint(
          '[MagazinePreview] precaching initial spread count=$precacheCount issue=${widget.magazineId} t=${_openStopwatch.elapsedMilliseconds}ms');
      final initialTasks = <Future<void>>[];
      for (int i = 0; i < precacheCount; i++) {
        if (mounted) {
          initialTasks.add(precacheImage(providers[i], context));
        }
      }
      await Future.wait(initialTasks);
      if (!mounted || generation != _loadGeneration) return;
      debugPrint(
          '[MagazinePreview] initial spread decoded issue=${widget.magazineId} t=${_openStopwatch.elapsedMilliseconds}ms');

      if (mounted) {
        setState(() {
          _flipbookPages = builtPages;
          _isLoading = false;
          _loadError = null;
        });
        debugPrint(
            '[MagazinePreview] loading overlay dismissed; flipbook mounted t=${_openStopwatch.elapsedMilliseconds}ms');
      }

      // Prefetch remaining pages in the background without delaying the first spread
      if (providers.length > precacheCount) {
        unawaited(() async {
          for (int pIdx = precacheCount; pIdx < providers.length; pIdx++) {
            if (!mounted || generation != _loadGeneration) return;
            try {
              await precacheImage(providers[pIdx], context);
              debugPrint(
                  '[MagazinePreview] background page precached page=${pIdx + 1} t=${_openStopwatch.elapsedMilliseconds}ms');
            } catch (_) {}
          }
        }());
      }
    } catch (e) {
      if (generation != _loadGeneration) return;
      debugPrint(
          '[MagazinePreview] load failed issue=${widget.magazineId}: $e t=${_openStopwatch.elapsedMilliseconds}ms');
      if (mounted) {
        setState(() {
          _loadError =
              'Unable to load this magazine preview. Check your connection and retry.';
          _isLoading = false;
        });
      }
    }
  }

  void _checkPageEnd() {
    final page = _flipbookController.page;
    final total = _flipbookPages.length;
    // In single-page mode (portrait), final page has page == total (e.g. 4 of 4).
    // In two-page mode (landscape), final spread has page >= total - 1 and cannot flip forward.
    final reachedEnd = page >= total ||
        (page >= total - 1 && !_flipbookController.canFlipRight);
    if (reachedEnd) {
      if (!_showDownloadPrompt && mounted) {
        setState(() => _showDownloadPrompt = true);
      }
    } else {
      if (_showDownloadPrompt && mounted) {
        setState(() => _showDownloadPrompt = false);
      }
    }
  }

  Widget _buildLoadingCoverPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 220,
            height: 310,
            decoration: BoxDecoration(
              color: const Color(0xFF152018),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MagazineCoverImage(
                    magazineId: widget.magazineId,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                  const Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF00E676),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'প্রিভিউ প্রস্তুত করা হচ্ছে...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Preparing realistic flipbook...',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        title: Text(
          '${formatMagazineTitle(widget.title)} (Preview)',
          style: const TextStyle(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF00E676)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? _buildLoadingCoverPlaceholder()
          : _loadError != null || _flipbookPages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_rounded,
                            color: Color(0xFF81C784), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _loadError ?? 'No preview pages are available.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            debugPrint(
                                '[MagazinePreview] retry requested issue=${widget.magazineId}');
                            _fetchPreviewPages();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : MagazineFlipbookLayoutGate(
                  builder: (context, constraints) {
                    if (!_loggedFirstLayout) {
                      debugPrint(
                          '[MagazinePreview] valid layout issue=${widget.magazineId} size=${constraints.maxWidth}x${constraints.maxHeight}; first page attached');
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_loggedFirstLayout) {
                          _loggedFirstLayout = true;
                          debugPrint(
                              '[MagazinePreview] first page frame rendered and presented t=${_openStopwatch.elapsedMilliseconds}ms');
                        }
                      });
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          ignoring: _isFlipping,
                          child: RealisticFlipbook(
                            controller: _flipbookController,
                            pages: _flipbookPages,
                            singlePage: false,
                            singlePageSpreadNavigation: false,
                            centering: true,
                            startPage: 1,
                            forwardDirection: FlipbookForwardDirection.right,
                            dragToFlip: true,
                            tapToFlip: false,
                            clickToZoom: false,
                            nPolygons: 10,
                            ambient: 0.8,
                            loadingBuilder: (_) => const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF00E676)),
                            ),
                            onFlipGuard: (currentPage, targetPage, direction, auto) =>
                                !_isFlipping,
                            onFlipLeftStart: (_) {
                              if (mounted) setState(() => _isFlipping = true);
                              _playFlipSound();
                            },
                            onFlipRightStart: (_) {
                              if (mounted) setState(() => _isFlipping = true);
                              _playFlipSound();
                            },
                            onFlipLeftEnd: (_) {
                              if (mounted) {
                                setState(() => _isFlipping = false);
                                _checkPageEnd();
                              }
                            },
                            onFlipRightEnd: (_) {
                              if (mounted) {
                                setState(() => _isFlipping = false);
                                _checkPageEnd();
                              }
                            },
                          ),
                        ),
                        if (_showDownloadPrompt)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.85),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 32),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF142018),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: const Color(0xFF00E676)
                                            .withValues(alpha: 0.5)),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.6),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      )
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                          Icons.workspace_premium_rounded,
                                          color: Color(0xFF00E676),
                                          size: 48),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'সম্পূর্ণ ম্যাগাজিনটি পড়তে ডাউনলোড করুন',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Download to your bookshelf to read the full issue.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                      ),
                                      const SizedBox(height: 24),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF00E676),
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                        ),
                                        onPressed: () {
                                          Navigator.pop(context); // Close preview
                                          widget.onDownloadTriggered(); // Trigger download
                                        },
                                        icon: const Icon(Icons.download_rounded,
                                            size: 20),
                                        label: const Text(
                                            'ডাউনলোড করুন (Download)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                      ],
                    );
                  },
                  loading: const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E676)),
                  ),
                ),
    );
  }
}
