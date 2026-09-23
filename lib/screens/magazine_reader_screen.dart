import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';
import 'package:page_flip/page_flip.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/forest_ambience_service.dart';
import '../widgets/keyboard_press_effect.dart';

enum ReaderViewState { spread, single, zoomed }

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
  
  // Controllers
  final FlipbookController _flipbookController = FlipbookController();
  final GlobalKey<PageFlipWidgetState> _pageFlipKey = GlobalKey<PageFlipWidgetState>();
  final TransformationController _zoomController = TransformationController();

  List<String> _signedUrls = [];
  List<FlipbookPage?> _flipbookPages = [];
  bool _isLoading = true;
  late int _currentPage;
  bool _showControls = true;
  
  // 3-State Cycle Controller
  ReaderViewState _viewState = ReaderViewState.spread;
  bool _enablePageFlipSound = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;

    // Magazine Reader is always silent with respect to forest ambience.
    // Page-flip audio remains independently controlled and defaults to ON.
    unawaited(ForestAmbienceService.stopAmbience());
    _initAudioEngine();
    _fetchSignedPageUrls().then((_) {
      _saveReadingProgress(_currentPage);
    });
    _loadReaderSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _initAudioEngine() async {
    try {
      await _pageFlipAudioPlayer.setPlayerMode(PlayerMode.lowLatency);
      // FIX: Explicitly set ReleaseMode to stop. This prevents the Windows audio engine 
      // from hanging after playing the sound for the first time.[cite: 21]
      await _pageFlipAudioPlayer.setReleaseMode(ReleaseMode.stop);
      await _pageFlipAudioPlayer.setVolume(1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    _thumbScrollController.dispose();
    _focusNode.dispose();
    _pageFlipAudioPlayer.stop();
    _pageFlipAudioPlayer.dispose();
    unawaited(ForestAmbienceService.stopAmbience());
    _zoomController.dispose();
    super.dispose();
  }

  Future<void> _loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enablePageFlipSound = prefs.getBool('pref_page_flip_sound') ?? true;
    });
  }

  Future<void> _saveReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_page_flip_sound', _enablePageFlipSound);
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
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _buildFlipbookPages() {
    final pages = <FlipbookPage?>[null];
    for (final url in _signedUrls) {
      final provider = CachedNetworkImageProvider(url);
      pages.add(FlipbookPage(image: provider, hiResImage: provider));
    }
    _flipbookPages = pages;
  }

  void _cycleViewState(BuildContext context) {
    setState(() {
      if (_viewState == ReaderViewState.spread) {
        _viewState = ReaderViewState.single;
      } else if (_viewState == ReaderViewState.single) {
        _viewState = ReaderViewState.zoomed;
        
        final Size screenSize = MediaQuery.of(context).size;
        const double scale = 2.5;
        final double tx = -(screenSize.width * scale - screenSize.width) / 2;
        final double ty = -(screenSize.height * scale - screenSize.height) / 2;
        
        _zoomController.value = Matrix4.identity()
          ..translate(tx, ty)
          ..scale(scale);
          
      } else {
        _viewState = ReaderViewState.spread;
        _flipbookController.goToPage((_currentPage + 1).clamp(1, _signedUrls.length));
      }
    });
  }

  void _updateCurrentPage(int newPage) {
    if (newPage == _currentPage) return;
    setState(() => _currentPage = newPage);
    _saveReadingProgress(newPage);
    _syncThumbnails();
  }

  void _onFlipbookPageSettled() {
    final page = (_flipbookController.page - 1).clamp(0, _signedUrls.length - 1);
    _updateCurrentPage(page);
  }

  Future<void> _playPageFlipSound() async {
    if (_enablePageFlipSound && !SoundService.isMuted) {
      try {
        // FIX: Forcefully stop the player and reset position before playing to prevent freeze[cite: 21]
        await _pageFlipAudioPlayer.stop(); 
        await _pageFlipAudioPlayer.play(AssetSource('audio/page_flip.mp3'), position: Duration.zero);
      } catch (_) {}
    }
  }

  void _turnNext() {
    _focusNode.requestFocus();
    if (_viewState == ReaderViewState.zoomed) return;
    if (_currentPage >= _signedUrls.length - 1) return;
    _playPageFlipSound();

    if (_viewState == ReaderViewState.spread) {
      if (_flipbookController.canFlipRight) {
        try { _flipbookController.flipRight(); } catch (_) {}
      } else {
        final target = (_flipbookController.page + 2).clamp(1, _signedUrls.length);
        _flipbookController.goToPage(target);
        _updateCurrentPage((target - 1).clamp(0, _signedUrls.length - 1));
      }
    } else if (_viewState == ReaderViewState.single) {
      _pageFlipKey.currentState?.nextPage();
      _updateCurrentPage((_currentPage + 1).clamp(0, _signedUrls.length - 1));
    }
  }

  void _turnPrev() {
    _focusNode.requestFocus();
    if (_viewState == ReaderViewState.zoomed) return; 
    if (_currentPage <= 0) return;
    _playPageFlipSound();

    if (_viewState == ReaderViewState.spread) {
      if (_flipbookController.canFlipLeft) {
        try { _flipbookController.flipLeft(); } catch (_) {}
      } else {
        final target = (_flipbookController.page - 2).clamp(1, _signedUrls.length);
        _flipbookController.goToPage(target);
        _updateCurrentPage((target - 1).clamp(0, _signedUrls.length - 1));
      }
    } else if (_viewState == ReaderViewState.single) {
      _pageFlipKey.currentState?.previousPage();
      _updateCurrentPage((_currentPage - 1).clamp(0, _signedUrls.length - 1));
    }
  }

  void _jumpToPage(int index) {
    if (index < 0 || index >= _signedUrls.length) return;
    if (index == _currentPage) return;
    
    _playPageFlipSound();
    
    if (_viewState == ReaderViewState.spread) {
      _flipbookController.goToPage(index + 1);
    } 
    
    _updateCurrentPage(index);
  }

  void _syncThumbnails() {
    if (_thumbScrollController.hasClients) {
      final targetOffset = (_currentPage * 68.0) - (MediaQuery.of(context).size.width / 2) + 29;
      _thumbScrollController.animateTo(
        targetOffset.clamp(0.0, _thumbScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);

  void _nudgeZoom(double dx, double dy) {
    final matrix = _zoomController.value.clone();
    matrix.translate(dx, dy);
    _zoomController.value = matrix;
  }

  Widget _buildCustomZoomView(BuildContext context) {
    final content = CachedNetworkImage(imageUrl: _signedUrls[_currentPage], fit: BoxFit.contain);

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTap: () => _cycleViewState(context), 
          child: InteractiveViewer(
            transformationController: _zoomController,
            minScale: 1.0,
            maxScale: 5.0,
            panEnabled: true, 
            child: Center(child: content),
          ),
        ),
        Positioned(
          bottom: _showControls ? 120 : 20,
          right: 16,
          child: Container(
            width: 140,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.9),
              border: Border.all(color: const Color(0xFF00E676), width: 1.5),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 10)],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(width: 400, height: 600, child: content),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _zoomController,
                  builder: (context, child) {
                    final matrix = _zoomController.value;
                    final scale = matrix.getMaxScaleOnAxis();
                    final tx = -matrix.getTranslation().x;
                    final ty = -matrix.getTranslation().y;
                    
                    final screenWidth = MediaQuery.of(context).size.width;
                    final screenHeight = MediaQuery.of(context).size.height;
                    
                    const double mapWidth = 140.0;
                    const double mapHeight = 180.0;
                    
                    final rectWidth = (mapWidth / scale).clamp(0.0, mapWidth);
                    final rectHeight = (mapHeight / scale).clamp(0.0, mapHeight);
                    
                    final maxTx = (screenWidth * scale) - screenWidth;
                    final maxTy = (screenHeight * scale) - screenHeight;
                    
                    final progressX = maxTx > 0 ? (tx / maxTx).clamp(0.0, 1.0) : 0.5;
                    final progressY = maxTy > 0 ? (ty / maxTy).clamp(0.0, 1.0) : 0.5;
                    
                    final left = progressX * (mapWidth - rectWidth);
                    final top = progressY * (mapHeight - rectHeight);

                    return Positioned(
                      left: left, top: top, width: rectWidth, height: rectHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF00E676), width: 2),
                          color: const Color(0xFF00E676).withOpacity(0.25),
                        ),
                      ),
                    );
                  }
                ),
                Align(alignment: Alignment.topCenter, child: IconButton(icon: const Icon(Icons.arrow_drop_up, color: Colors.white), onPressed: () => _nudgeZoom(0, 50))),
                Align(alignment: Alignment.bottomCenter, child: IconButton(icon: const Icon(Icons.arrow_drop_down, color: Colors.white), onPressed: () => _nudgeZoom(0, -50))),
                Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.arrow_left, color: Colors.white), onPressed: () => _nudgeZoom(50, 0))),
                Align(alignment: Alignment.centerRight, child: IconButton(icon: const Icon(Icons.arrow_right, color: Colors.white), onPressed: () => _nudgeZoom(-50, 0))),
              ],
            ),
          ),
        )
      ],
    );
  }

  void _openReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18221B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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
                      Text('Reader Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('(পাঠক সেটিংস)', style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.touch_app_rounded, color: Colors.white54, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Double-tap anywhere on the screen to cycle between:\n1. 2-Page Spread View\n2. Single Page View\n3. Zoom Navigator',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
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
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
            : Stack(
                fit: StackFit.expand,
                children: [
                  // --- STATE 1: SPREAD VIEW ---
                  if (_viewState == ReaderViewState.spread)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      onDoubleTap: () => _cycleViewState(context), 
                      child: RealisticFlipbook(
                        controller: _flipbookController,
                        pages: _flipbookPages,
                        flipDuration: const Duration(milliseconds: 600),
                        zoomDuration: const Duration(milliseconds: 300),
                        singlePageSpreadNavigation: false, 
                        forwardDirection: FlipbookForwardDirection.right,
                        centering: true,
                        startPage: (_currentPage + 1).clamp(1, _flipbookPages.isEmpty ? 1 : _flipbookPages.length - 1),
                        tapToFlip: false,
                        clickToZoom: false,
                        dragToFlip: true,
                        nPolygons: 10,
                        ambient: 0.8,
                        onFlipLeftStart: (_) => _playPageFlipSound(),
                        onFlipRightStart: (_) => _playPageFlipSound(),
                        onFlipLeftEnd: (_) => _onFlipbookPageSettled(),
                        onFlipRightEnd: (_) => _onFlipbookPageSettled(),
                      ),
                    ),

                  // --- STATE 2: SINGLE PAGE VIEW (Page_Flip Package) ---
                  if (_viewState == ReaderViewState.single)
                    // FIX: Replaced opaque gesture overlays with a non-blocking onTapUp wrapper.
                    // This allows you to tap the edges to navigate, or swipe directly to peel the page![cite: 21]
                    GestureDetector(
                      onTapUp: (details) {
                        final width = MediaQuery.of(context).size.width;
                        final dx = details.globalPosition.dx;
                        if (dx < width * 0.25) {
                          _turnPrev();
                        } else if (dx > width * 0.75) {
                          _turnNext();
                        } else {
                          _toggleControls();
                        }
                      },
                      onDoubleTap: () => _cycleViewState(context),
                      child: PageFlipWidget(
                        key: _pageFlipKey,
                        backgroundColor: Colors.black,
                        initialIndex: _currentPage,
                        lastPage: Container(color: Colors.black),
                        children: <Widget>[
                          for (final url in _signedUrls)
                            CachedNetworkImage(
                              imageUrl: url, 
                              fit: BoxFit.contain,
                              placeholder: (c, u) => const Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                            )
                        ],
                      ),
                    ),

                  // --- STATE 3: ZOOM VIEW ---
                  if (_viewState == ReaderViewState.zoomed) 
                    _buildCustomZoomView(context),

                  // Watermark overlay
                  IgnorePointer(
                    child: Center(
                      child: Transform.rotate(
                        angle: -0.45,
                        child: Text(
                          widget.userEmail,
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.08), letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // UI Controls
                  if (_showControls) ...[
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: AppBar(
                        backgroundColor: Colors.black.withOpacity(0.85),
                        title: Text(
                          '${formatMagazineTitle(widget.title)} (Page ${_signedUrls.isEmpty ? 0 : _currentPage + 1}/${_signedUrls.length})',
                          style: const TextStyle(fontSize: 15),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.tune_rounded, color: Color(0xFF00E676)),
                            onPressed: _openReaderSettings,
                          ),
                          IconButton(
                            icon: const Icon(Icons.fullscreen_exit_rounded),
                            onPressed: _toggleControls,
                          ),
                        ],
                      ),
                    ),
                    if (_signedUrls.isNotEmpty)
                      Positioned(
                        bottom: 12, left: 16, right: 16,
                        child: Container(
                          height: 94,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.90),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: ListView.builder(
                            controller: _thumbScrollController,
                            scrollDirection: Axis.horizontal,
                            itemCount: _signedUrls.length,
                            itemBuilder: (context, index) {
                              final isSelected = index == _currentPage;
                              return Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  width: isSelected ? 58 : 44,
                                  height: isSelected ? 80 : 60,
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF00E676) : Colors.white24,
                                      width: isSelected ? 2.5 : 1,
                                    ),
                                  ),
                                  child: KeyboardPressEffect(
                                    onTap: () => _jumpToPage(index),
                                    child: CachedNetworkImage(
                                      imageUrl: _signedUrls[index],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ]
                ],
              ),
      ),
    );
  }
}

// --------------------------------------------------------
// AranyakPdfReaderScreen remains unmodified
// --------------------------------------------------------
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
                      color: Colors.black.withOpacity(0.5),
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