import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/protected_asset_service.dart';
import '../services/sound_service.dart';
import '../core/config.dart';

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
  final AudioPlayer _flipPlayer = AudioPlayer();
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
        final signedUrl = await ProtectedAssetService.getSignedUrl(
          bucket: 'magazine_pages',
          storagePath: p['storage_path'],
          expiresInSeconds: 120,
        );
        if (signedUrl != null) {
          final provider = NetworkImage(signedUrl);
          builtPages.add(FlipbookPage(image: provider, hiResImage: provider));
        }
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
