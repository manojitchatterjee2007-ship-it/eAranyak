import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';

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
  List<FlipbookPage?> _flipbookPages = [];
  bool _isLoading = true;
  bool _showDownloadPrompt = false;

  @override
  void initState() {
    super.initState();
    _fetchPreviewPages();
  }

  Future<void> _fetchPreviewPages() async {
    try {
      // LIMIT to first 4 pages for the preview
      final pages = await _supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', widget.magazineId)
          .order('page_number', ascending: true)
          .limit(4); 

      final List<FlipbookPage?> builtPages = [null]; // Null flyleaf for odd/even spread
      
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
    // If the user reaches page 4 (index 4 in the 1-based controller due to flyleaf)
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
        title: Text('${widget.title} (Preview)'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
          : Stack(
              fit: StackFit.expand,
              children: [
                RealisticFlipbook(
                  controller: _flipbookController,
                  pages: _flipbookPages,
                  singlePage: false,
                  onFlipLeftEnd: (_) => _checkPageEnd(),
                  onFlipRightEnd: (_) => _checkPageEnd(),
                ),
                if (_showDownloadPrompt)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.8),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          margin: const EdgeInsets.symmetric(horizontal: 32),
                          decoration: BoxDecoration(
                            color: const Color(0xFF142018),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.menu_book_rounded, color: Color(0xFF00E676), size: 48),
                              const SizedBox(height: 16),
                              const Text(
                                'Download to your bookshelf to read the full issue.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E676),
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () {
                                  Navigator.pop(context); // Close preview
                                  widget.onDownloadTriggered(); // Trigger download in Library
                                },
                                child: const Text('Download Full Issue', style: TextStyle(fontWeight: FontWeight.bold)),
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