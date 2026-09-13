import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../services/sound_service.dart';
import '../widgets/keyboard_press_effect.dart';

class ProtectedReaderScreen extends StatefulWidget {
  final String magazineId;
  final String title;
  final String userEmail;
  final int initialPage;

  const ProtectedReaderScreen({
    super.key,
    required this.magazineId,
    required this.title,
    required this.userEmail,
    this.initialPage = 0,
  });

  @override
  State<ProtectedReaderScreen> createState() => _ProtectedReaderScreenState();
}

class _ProtectedReaderScreenState extends State<ProtectedReaderScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _thumbScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final AudioPlayer _pageFlipAudioPlayer = AudioPlayer();
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlipbookController _flipbookController = FlipbookController();

  List<String> _signedUrls = [];
  List<FlipbookPage?> _flipbookPages = [];
  bool _isLoading = true;
  late int _currentPage;
  bool _showControls = true;
  bool _isZoomed = false;

  /// Layout state: 'auto' (device orientation driven on mobile/tablet), 'spread' (force 2-page view), or 'single' (force 1-page view).
  String _userLayoutPreference = 'auto';

  bool _enablePageFlipSound = true;

  bool _isSinglePageMode(BuildContext context) {
    if (_userLayoutPreference == 'single') return true;
    if (_userLayoutPreference == 'spread') return false;

    // Mobile & Tablet: driven by device orientation (portrait = single page, landscape = 2-page spread)
    final isMobileOrTablet = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobileOrTablet) {
      final orientation = MediaQuery.of(context).orientation;
      return orientation == Orientation.portrait;
    }

    // Desktop & Laptop: defaults to single page if narrow (<700), or 2-page spread if wide
    final width = MediaQuery.of(context).size.width;
    return width < 700;
  }

  void _toggleLayoutMode() {
    final currentSingle = _isSinglePageMode(context);
    setState(() {
      _userLayoutPreference = currentSingle ? 'spread' : 'single';
    });
    _saveReaderSettings();
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;

    _initAudioEngine();
    _fetchSignedPageUrls().then((_) {
      _saveReadingProgress(_currentPage);
    });
    _loadReaderSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _initAudioEngine() async {
    try {
      await _pageFlipAudioPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _pageFlipAudioPlayer.setVolume(1.0);
      await _pageFlipAudioPlayer.setSource(AssetSource('audio/page_flip.mp3'));
    } catch (_) {}
  }

  @override
  void dispose() {
    _thumbScrollController.dispose();
    _focusNode.dispose();
    _pageFlipAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enablePageFlipSound = prefs.getBool('pref_page_flip_sound') ?? true;
      _userLayoutPreference = prefs.getString('pref_reader_layout') ?? 'auto';
    });
  }

  Future<void> _saveReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_page_flip_sound', _enablePageFlipSound);
    await prefs.setString('pref_reader_layout', _userLayoutPreference);
  }

  Future<void> _saveReadingProgress(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_read_mag_id', widget.magazineId);
    await prefs.setString('last_read_title', formatMagazineTitle(widget.title));
    await prefs.setInt('last_read_page', page);
    await prefs.setInt('last_read_total_pages', _signedUrls.length);
    if (_signedUrls.isNotEmpty) {
      await prefs.setDouble(
          'progress_${widget.magazineId}', (page + 1) / _signedUrls.length);
    }
  }

  Future<void> _fetchSignedPageUrls() async {
    try {
      final pages = await _supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', widget.magazineId)
          .order('page_number', ascending: true);
      final List<String> urls = [];
      for (final p in pages) {
        final signedUrl = await _supabase.storage
            .from('magazine_pages')
            .createSignedUrl(p['storage_path'], 120);
        urls.add(signedUrl);
      }
      _signedUrls = urls;
      _buildFlipbookPages();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Builds the flipbook page list ONCE from the short-lived signed URLs.
  ///
  /// The first entry is a `null` flyleaf so the package's odd/even spread
  /// pairing matches the real printed magazine (page 1 sits on the right
  /// side). Image mode is used because magazine pages are raster page
  /// images; `NetworkImage` streams each URL lazily (the package preloads
  /// only the few pages around the current one) so the whole issue is not
  /// downloaded eagerly and no huge in-memory image cache is created.
  void _buildFlipbookPages() {
    final pages = <FlipbookPage?>[null];
    for (final url in _signedUrls) {
      final provider = NetworkImage(url);
      pages.add(FlipbookPage(image: provider, hiResImage: provider));
    }
    _flipbookPages = pages;
  }

  /// Called whenever the flipbook settles on a page (flip end callbacks).
  /// Keeps the page counter, thumbnails and saved progress in sync with the
  /// package's authoritative page state (`FlipbookController.page`).
  void _onPageSettled() {
    final page = (_flipbookController.page - 1).clamp(0, _signedUrls.length - 1);
    if (page == _currentPage) {
      return;
    }
    setState(() {
      _currentPage = page;
    });
    _saveReadingProgress(page);
    _syncThumbnails();
  }

  Future<void> _playPageFlipSound() async {
    if (_enablePageFlipSound && !SoundService.isMuted) {
      try {
        await _pageFlipAudioPlayer.seek(Duration.zero);
        await _pageFlipAudioPlayer.resume();
      } catch (_) {}
    }
  }

  void _turnNext() {
    _focusNode.requestFocus();
    if (_isZoomed) {
      try {
        _flipbookController.zoomOut();
        _flipbookController.zoomOut();
      } catch (_) {}
    }
    _playPageFlipSound();

    if (_flipbookController.canFlipRight) {
      try {
        _flipbookController.flipRight();
      } catch (_) {}
    } else {
      final step = _isSinglePageMode(context) ? 1 : 2;
      final target =
          (_flipbookController.page + step).clamp(1, _signedUrls.length);
      _flipbookController.goToPage(target);
      final newPage = (target - 1).clamp(0, _signedUrls.length - 1);
      if (newPage != _currentPage) {
        setState(() {
          _currentPage = newPage;
        });
        _saveReadingProgress(newPage);
        _syncThumbnails();
      }
    }
  }

  void _turnPrev() {
    _focusNode.requestFocus();
    if (_isZoomed) {
      try {
        _flipbookController.zoomOut();
        _flipbookController.zoomOut();
      } catch (_) {}
    }
    _playPageFlipSound();

    if (_flipbookController.canFlipLeft) {
      try {
        _flipbookController.flipLeft();
      } catch (_) {}
    } else {
      final step = _isSinglePageMode(context) ? 1 : 2;
      final target =
          (_flipbookController.page - step).clamp(1, _signedUrls.length);
      _flipbookController.goToPage(target);
      final newPage = (target - 1).clamp(0, _signedUrls.length - 1);
      if (newPage != _currentPage) {
        setState(() {
          _currentPage = newPage;
        });
        _saveReadingProgress(newPage);
        _syncThumbnails();
      }
    }
  }

  void _jumpToPage(int index) {
    if (index < 0 || index >= _signedUrls.length) {
      return;
    }
    final target = index + 1;
    if (target == _flipbookController.page) {
      return;
    }
    _playPageFlipSound();
    _flipbookController.goToPage(target);
    // goToPage jumps without animating, so page state is synced immediately.
    setState(() {
      _currentPage = index;
    });
    _saveReadingProgress(index);
    _syncThumbnails();
  }

  void _syncThumbnails() {
    if (_thumbScrollController.hasClients) {
      final targetOffset =
          (_currentPage * 68.0) - (MediaQuery.of(context).size.width / 2) + 29;
      _thumbScrollController.animateTo(
        targetOffset.clamp(
            0.0, _thumbScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _openReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18221B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF00E676)),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reader Settings',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('(পাঠক সেটিংস)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF81C784))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Page Layout (পেজ লেআউট)',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text(
                      'Auto — single page on portrait phones, two-page spread '
                      'on wide/landscape screens\n(অটো — পোর্ট্রেটে এক পাতা, '
                      'ল্যান্ডস্কেপ/ট্যাবলেটে দুই পেজের স্প্রেড)\n'
                      'Single — always show one page (সবসময় একটি পাতা)',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                      value: 'auto',
                      label: Text('Auto'),
                      tooltip: 'Auto (Recommended)'),
                  ButtonSegment<String>(
                      value: 'single',
                      label: Text('Single'),
                      tooltip: 'Force single page'),
                ],
                selected: {_readerLayout},
                onSelectionChanged: (selection) {
                  final value = selection.isEmpty ? null : selection.first;
                  if (value == null) return;
                  setModalState(() {
                    _readerLayout = value;
                  });
                  setState(() {
                    _readerLayout = value;
                  });
                  _saveReaderSettings();
                },
              ),
              const Divider(color: Colors.white12),
              SwitchListTile(
                activeThumbColor: const Color(0xFF00E676),
                contentPadding: EdgeInsets.zero,
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Page Flip Sound Effect'),
                    Text('(পৃষ্ঠা ওল্টানোর শব্দ)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                  ],
                ),
                subtitle: const Text(
                    'Mute audio for silent reading\n(শব্দহীন পাঠের জন্য মিউট করুন)',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: _enablePageFlipSound,
                onChanged: (val) {
                  setModalState(() {
                    _enablePageFlipSound = val;
                  });
                  setState(() {
                    _enablePageFlipSound = val;
                  });
                  _saveReaderSettings();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flipbookLoadingBuilder(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E676)),
      );

  /// The real `flutter_realistic_flipbook` page-presentation layer.
  ///
  /// Configuration notes:
  ///  - `singlePage: _readerLayout == 'single'` — otherwise the package uses
  ///    its native responsive layout (1 page on portrait, 2-page spread on
  ///    wide/landscape screens), which keeps the printed odd/even pairing
  ///    (the leading `null` flyleaf puts page 1 on the right side).
  ///  - `startPage` is the magazine page number to resume from: with the
  ///    leading flyleaf the package reports `controller.page` as the
  ///    1-based magazine page (here `initialPage` is a 0-based index).
  ///  - Gestures: drag/swipe turns pages (dragToFlip), drag pans while
  ///    zoomed (dragToScroll), wheel zooms on desktop. `tapToFlip` and
  ///    `clickToZoom` stay OFF so plain taps keep toggling the reader
  ///    controls (existing reader behaviour) without gesture-arena
  ///    conflicts. 0.1.4 has no pinch handler, so zoom is driven by the
  ///    on-screen zoom controls through FlipbookController.zoomIn/zoomOut.
  ///  - Flip start/end callbacks drive the existing flip sound, page
  ///    counter, thumbnails and reading-progress persistence.
  Widget _buildFlipbook() {
    return RealisticFlipbook(
      controller: _flipbookController,
      pages: _flipbookPages,
      flipDuration: const Duration(milliseconds: 600),
      zoomDuration: const Duration(milliseconds: 300),
      singlePage: _readerLayout == 'single',
      forwardDirection: FlipbookForwardDirection.right,
      centering: true,
      startPage: (widget.initialPage + 1)
          .clamp(1, _flipbookPages.isEmpty ? 1 : _flipbookPages.length - 1),
      tapToFlip: true,
      clickToZoom: true,
      dragToFlip: true,
      dragToScroll: true,
      wheel: FlipbookWheelMode.scroll,
      clipToViewport: false,
      nPolygons: 10,
      perspective: 2000,
      ambient: 0.8,
      gloss: 0.15,
      singlePageSpreadNavigation: true,
      singlePageSlideDuration: const Duration(milliseconds: 250),
      loadingBuilder: _flipbookLoadingBuilder,
      onFlipLeftStart: (_) => _playPageFlipSound(),
      onFlipRightStart: (_) => _playPageFlipSound(),
      onFlipLeftEnd: (_) => _onPageSettled(),
      onFlipRightEnd: (_) => _onPageSettled(),
      onZoomStart: (zoom) {
        final zoomed = zoom > 1.05;
        if (zoomed != _isZoomed) {
          setState(() {
            _isZoomed = zoomed;
          });
        }
      },
      onZoomEnd: (zoom) {
        final zoomed = zoom > 1.05;
        if (zoomed != _isZoomed) {
          setState(() {
            _isZoomed = zoomed;
          });
        }
      },
    );
  }

  /// Compact zoom controls shown while the flipbook is zoomed in.
  /// Zoom in/out drive the package controller; panning is handled by the
  /// package's own drag-to-scroll, so no custom pan arrows are layered on.
  Widget _buildZoomPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E676), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.75), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded,
                color: Color(0xFF00E676), size: 26),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Zoom out (জুম আউট)',
            onPressed: () {
              try {
                _flipbookController.zoomOut();
              } catch (_) {}
            },
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.5)),
            ),
            child: const Text(
              'ZOOM',
              style: TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded,
                color: Color(0xFF00E676), size: 26),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Zoom in (জুম ইন)',
            onPressed: () {
              try {
                _flipbookController.zoomIn();
              } catch (_) {}
            },
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.fullscreen_exit_rounded,
                color: Colors.white70, size: 22),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Reset zoom (জুম বন্ধ করুন)',
            onPressed: () {
              try {
                _flipbookController.zoomOut();
                _flipbookController.zoomOut();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  /// Error/empty view shown when the signed page list could not be loaded.
  Widget _buildLoadErrorView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, color: Colors.redAccent, size: 52),
            SizedBox(height: 12),
            Text(
              'Unable to load magazine pages.\nপত্রিকার পাতা লোড করা যায়নি।',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Please check your connection and reopen.\nসংযোগ পরীক্ষা করে আবার খুলুন।',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.pageDown ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _turnNext();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _turnPrev();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _toggleControls();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isLoading || _signedUrls.isEmpty
            ? (_isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E676)))
                : _buildLoadErrorView())
            : Stack(
                fit: StackFit.expand,
                children: [
                  // Page Presentation Layer with Double-Tap & Pinch Gestures
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTapDown: (details) {
                      if (_isZoomed) {
                        try {
                          _flipbookController.zoomOut();
                          _flipbookController.zoomOut();
                        } catch (_) {}
                      } else {
                        try {
                          _flipbookController.zoomIn(details.localPosition);
                        } catch (_) {}
                      }
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount >= 2) {
                        if (details.scale > 1.12) {
                          try {
                            _flipbookController.zoomIn();
                          } catch (_) {}
                        } else if (details.scale < 0.88) {
                          try {
                            _flipbookController.zoomOut();
                          } catch (_) {}
                        }
                      }
                    },
                    child: _buildFlipbook(),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Transform.rotate(
                        angle: -0.45,
                        child: Text(
                          widget.userEmail,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.08),
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_showControls && _currentPage > 0)
                    Positioned(
                      left: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: KeyboardPressEffect(
                          onTap: _turnPrev,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF00E676), width: 1.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 8),
                              ],
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  if (_showControls && _currentPage < _signedUrls.length - 1)
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: KeyboardPressEffect(
                          onTap: _turnNext,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF00E676), width: 1.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 8),
                              ],
                            ),
                            child: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white,
                                size: 20),
                          ),
                        ),
                      ),
                    ),
                  // Zoom panel positioned ABOVE bottom thumbnail bar
                  if (_isZoomed)
                    Positioned(
                      bottom: _showControls ? 120 : 20,
                      right: 16,
                      child: _buildZoomPanel(),
                    ),
                    if (_showControls)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AppBar(
                          backgroundColor: Colors.black.withValues(alpha: 0.85),
                          elevation: 0,
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${formatMagazineTitle(widget.title)} (Page ${_signedUrls.isEmpty ? 0 : _currentPage + 1}/${_signedUrls.length})',
                                style: const TextStyle(fontSize: 15),
                              ),
                              Text(
                                '(পৃষ্ঠা ${_signedUrls.isEmpty ? 0 : _currentPage + 1}/${_signedUrls.length})',
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFF81C784)),
                              ),
                            ],
                          ),
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.tune_rounded,
                                  color: Color(0xFF00E676)),
                              tooltip: 'Settings (সেটিংস)',
                              onPressed: _openReaderSettings,
                            ),
                            IconButton(
                              icon: const Icon(Icons.fullscreen_exit_rounded),
                              tooltip: 'Toggle Controls (কন্ট্রোল লুকান)',
                              onPressed: _toggleControls,
                            ),
                          ],
                        ),
                      ),
                    if (_showControls && _signedUrls.isNotEmpty)
                      Positioned(
                        bottom: 12,
                        left: 16,
                        right: 16,
                        child: Container(
                          height: 94,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: ListView.builder(
                            controller: _thumbScrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _signedUrls.length,
                            itemBuilder: (context, index) {
                              final isSelected = index == _currentPage;

                              return Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  width: isSelected ? 58 : 44,
                                  height: isSelected ? 80 : 60,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF00E676)
                                          : Colors.white24,
                                      width: isSelected ? 2.5 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF00E676)
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: KeyboardPressEffect(
                                      onTap: () {
                                        _jumpToPage(index);
                                      },
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          CachedNetworkImage(
                                            imageUrl: _signedUrls[index],
                                            fit: BoxFit.cover,
                                            placeholder: (c, u) => Container(
                                                color: Colors.black45),
                                            errorWidget: (c, u, e) =>
                                                const Icon(Icons.broken_image,
                                                    size: 14),
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              color: isSelected
                                                  ? const Color(0xFF00E676)
                                                  : Colors.black87,
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 2),
                                              child: Text(
                                                '${index + 1}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: isSelected ? 11 : 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: isSelected
                                                      ? Colors.black
                                                      : Colors.white70,
                                                ),
                                              ),
                                            ),
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
                      ),
                  ],
                ),
      ),
    );
  }
}

class AranyakPdfReaderScreen extends StatefulWidget {
  final String assetPath;
  final String title;

  const AranyakPdfReaderScreen({
    super.key,
    required this.assetPath,
    required this.title,
  });

  @override
  State<AranyakPdfReaderScreen> createState() => _AranyakPdfReaderScreenState();
}

class _AranyakPdfReaderScreenState extends State<AranyakPdfReaderScreen> {
  pdfx.PdfDocument? _document;
  int _pageCount = 0;
  int _currentPage = 0;
  bool _loading = true;
  String? _error;
  final Map<int, Uint8List> _pageCache = {};
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _openPdf();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final double offset = _scrollController.offset;
      final int index = (offset / 450).floor().clamp(0, _pageCount - 1);
      if (index != _currentPage) {
        setState(() {
          _currentPage = index;
        });
      }
    }
  }

  Future<void> _openPdf() async {
    try {
      final doc = await pdfx.PdfDocument.openAsset(widget.assetPath);
      if (mounted) {
        setState(() {
          _document = doc;
          _pageCount = doc.pagesCount;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<Uint8List?> _renderPage(int pageNumber) async {
    if (_pageCache.containsKey(pageNumber)) {
      return _pageCache[pageNumber];
    }
    if (_document == null) return null;

    try {
      final page = await _document!.getPage(pageNumber);
      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: pdfx.PdfPageImageFormat.jpeg,
      );
      await page.close();

      if (pageImage != null) {
        _pageCache[pageNumber] = pageImage.bytes;
        return pageImage.bytes;
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _document?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101510),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Enhanced Preview • উন্নত প্রাকদর্শন',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF81C784),
              ),
            ),
          ],
        ),
        actions: [
          if (!_loading && _pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  '${_currentPage + 1} / $_pageCount',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E676)),
            SizedBox(height: 14),
            Text(
              'Opening book preview...\nবইয়ের প্রাকদর্শন খোলা হচ্ছে...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_error != null || _document == null || _pageCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.redAccent,
                size: 52,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to open the preview PDF.\nপ্রাকদর্শন PDF খোলা যায়নি।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 20),
      itemCount: _pageCount,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;

        return FutureBuilder<Uint8List?>(
          future: _renderPage(pageNumber),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Container(
                height: 400,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                  color: Color(0xFF00E676),
                ),
              );
            }

            final bytes = snapshot.data;
            if (bytes == null) {
              return const SizedBox(
                height: 100,
                child: Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              );
            }

            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Container(
                margin: const EdgeInsets.only(bottom: 24, left: 12, right: 12),
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
