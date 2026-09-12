import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final PhotoViewController _photoController = PhotoViewController();

  List<String> _signedUrls = [];
  bool _isLoading = true;
  late int _currentPage;
  bool _showControls = true;
  bool _isZoomed = false;

  late AnimationController _animController;
  double _flipProgress = 0.0;
  bool _isDragging = false;

  bool _enablePageFlipAnimation = true;
  bool _enablePageFlipSound = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      lowerBound: -1.0,
      upperBound: 1.0,
      value: 0.0,
    );
    _animController.addListener(() {
      setState(() {
        _flipProgress = _animController.value;
      });
    });

    _photoController.outputStateStream.listen((state) {
      final zoomed = (state.scale ?? 1.0) > 1.05;
      if (zoomed != _isZoomed) {
        setState(() {
          _isZoomed = zoomed;
        });
      }
    });

    _initAudioEngine();
    _fetchSignedPageUrls().then((_) {
      _saveReadingProgress(_currentPage);
    });
    _loadReaderSettings();
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
    _photoController.dispose();
    _animController.dispose();
    _thumbScrollController.dispose();
    _focusNode.dispose();
    _pageFlipAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enablePageFlipAnimation = prefs.getBool('pref_page_flip_anim') ?? true;
      _enablePageFlipSound = prefs.getBool('pref_page_flip_sound') ?? true;
    });
  }

  Future<void> _saveReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_page_flip_anim', _enablePageFlipAnimation);
    await prefs.setBool('pref_page_flip_sound', _enablePageFlipSound);
  }

  Future<void> _saveReadingProgress(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_read_mag_id', widget.magazineId);
    await prefs.setString('last_read_title', widget.title);
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
      setState(() {
        _signedUrls = urls;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
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
    if (_isZoomed || _currentPage >= _signedUrls.length - 1 || _animController.isAnimating) {
      return;
    }
    _playPageFlipSound();
    if (!_enablePageFlipAnimation) {
      setState(() {
        _currentPage++;
      });
      _saveReadingProgress(_currentPage);
      _syncThumbnails();
      return;
    }
    setState(() {
      _currentPage++;
    });
    _saveReadingProgress(_currentPage);
    _syncThumbnails();

    _animController.value = 1.0;
    _animController.animateTo(0.0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuad);
  }

  void _turnPrev() {
    if (_isZoomed || _currentPage <= 0 || _animController.isAnimating) {
      return;
    }
    _playPageFlipSound();
    if (!_enablePageFlipAnimation) {
      setState(() {
        _currentPage--;
      });
      _saveReadingProgress(_currentPage);
      _syncThumbnails();
      return;
    }
    setState(() {
      _currentPage--;
    });
    _saveReadingProgress(_currentPage);
    _syncThumbnails();

    _animController.value = -1.0;
    _animController.animateTo(0.0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuad);
  }

  void _jumpToPage(int index) {
    if (index == _currentPage || _animController.isAnimating) {
      return;
    }
    _playPageFlipSound();
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

  void _handleHorizontalDragUpdate(
      DragUpdateDetails details, double screenWidth) {
    if (_isZoomed) return;
    if (_isDragging && _signedUrls.length > 1) {
      final delta = details.primaryDelta ?? 0.0;
      setState(() {
        _flipProgress -= (delta / screenWidth) * 1.35;
        _flipProgress = _flipProgress.clamp(-1.0, 1.0);
        _animController.value = _flipProgress;
      });
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    _isDragging = false;
    if (_flipProgress > 0.18 && _currentPage < _signedUrls.length - 1) {
      _playPageFlipSound();
      _turnNext();
    } else if (_flipProgress < -0.18 && _currentPage > 0) {
      _playPageFlipSound();
      _turnPrev();
    } else {
      _animController.animateTo(0.0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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
              SwitchListTile(
                activeThumbColor: const Color(0xFF00E676),
                contentPadding: EdgeInsets.zero,
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3D Book Curl Flip Animation'),
                    Text('(কিন্ডল ৩ডি রিয়েল পেজ কার্ল)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                  ],
                ),
                subtitle: const Text(
                    'Realistic 3D spine and paper curling effect\n(বাস্তবধর্মী বইয়ের পাতার মতো স্পাইন বাঁক ও শেডিং)',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: _enablePageFlipAnimation,
                onChanged: (val) {
                  setModalState(() {
                    _enablePageFlipAnimation = val;
                  });
                  setState(() {
                    _enablePageFlipAnimation = val;
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

  Widget _buildSinglePageImage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _signedUrls.length) {
      return const SizedBox.shrink();
    }
    final url = _signedUrls[pageIndex];

    return PhotoView(
      controller: pageIndex == _currentPage ? _photoController : null,
      imageProvider: CachedNetworkImageProvider(url),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3.0,
      initialScale: PhotoViewComputedScale.contained,
      heroAttributes: PhotoViewHeroAttributes(tag: 'mag_page_$pageIndex'),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E676)),
      ),
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image, color: Colors.white38, size: 48),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.pageDown) {
            _turnNext();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            _turnPrev();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _toggleControls();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E676)))
            : GestureDetector(
                onTap: _isZoomed ? null : _toggleControls,
                onHorizontalDragStart: (_) {
                  if (!_isZoomed) _isDragging = true;
                },
                onHorizontalDragUpdate: (details) {
                  if (!_isZoomed) _handleHorizontalDragUpdate(details, screenWidth);
                },
                onHorizontalDragEnd: (details) {
                  if (!_isZoomed) _handleHorizontalDragEnd(details);
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_flipProgress > 0 &&
                        _currentPage < _signedUrls.length - 1)
                      _buildSinglePageImage(_currentPage + 1)
                    else if (_flipProgress < 0 && _currentPage > 0)
                      _buildSinglePageImage(_currentPage - 1)
                    else
                      _buildSinglePageImage(_currentPage),
                    if (_flipProgress != 0.0 && _enablePageFlipAnimation && !_isZoomed) ...[
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: _flipProgress > 0
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                end: Alignment.center,
                                colors: [
                                  Colors.black.withValues(
                                      alpha: (math.sin(_flipProgress.abs() *
                                                  math.pi) *
                                              0.28)
                                          .clamp(0.0, 0.30)),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.35],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Transform(
                        alignment: _flipProgress > 0
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(-_flipProgress * (math.pi / 2.0)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildSinglePageImage(_currentPage),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: _flipProgress > 0
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  end: _flipProgress > 0
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  colors: [
                                    Colors.black.withValues(
                                        alpha: (_flipProgress.abs() * 0.12)
                                            .clamp(0.0, 0.14)),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.30],
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: _flipProgress > 0
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  end: Alignment.center,
                                  colors: [
                                    Colors.white.withValues(
                                        alpha: (math.sin(_flipProgress.abs() *
                                                    math.pi) *
                                                0.16)
                                            .clamp(0.0, 0.18)),
                                    Colors.black.withValues(
                                        alpha: (math.sin(_flipProgress.abs() *
                                                    math.pi) *
                                                0.24)
                                            .clamp(0.0, 0.26)),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.055, 0.22],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                    if (_showControls && _currentPage > 0 && !_isZoomed)
                      Positioned(
                        left: 14,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: KeyboardPressEffect(
                            onTap: _turnPrev,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                    if (_showControls && _currentPage < _signedUrls.length - 1 && !_isZoomed)
                      Positioned(
                        right: 14,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: KeyboardPressEffect(
                            onTap: _turnNext,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white,
                                  size: 20),
                            ),
                          ),
                        ),
                      ),
                    // Zoomed state navigation overlay with miniature thumbnail & 4 direction arrows
                    if (_isZoomed)
                      Positioned(
                        bottom: 90,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 10),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Zoomed Navigation',
                                style: TextStyle(color: Color(0xFF00E676), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 50,
                                height: 65,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white38),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: CachedNetworkImage(
                                    imageUrl: _signedUrls[_currentPage],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              IconButton(
                                icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF00E676), size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  _photoController.position = Offset(_photoController.position.dx, _photoController.position.dy + 80);
                                },
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.keyboard_arrow_left_rounded, color: Color(0xFF00E676), size: 22),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _photoController.position = Offset(_photoController.position.dx + 80, _photoController.position.dy);
                                    },
                                  ),
                                  const SizedBox(width: 20),
                                  IconButton(
                                    icon: const Icon(Icons.keyboard_arrow_right_rounded, color: Color(0xFF00E676), size: 22),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _photoController.position = Offset(_photoController.position.dx - 80, _photoController.position.dy);
                                    },
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF00E676), size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  _photoController.position = Offset(_photoController.position.dx, _photoController.position.dy - 80);
                                },
                              ),
                            ],
                          ),
                        ),
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
                                '${widget.title} (Page ${_signedUrls.isEmpty ? 0 : _currentPage + 1}/${_signedUrls.length})',
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
