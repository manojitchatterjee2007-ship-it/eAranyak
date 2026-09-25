import 'dart:async';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../core/config.dart';
import '../models/content_protection_models.dart';
import '../models/wildlife_gallery_item.dart';
import '../services/content_protection_service.dart';
import '../services/protected_asset_service.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/protected_content.dart';
import '../widgets/protected_image.dart';
import '../widgets/scientific_text.dart';

class WildlifeGalleryScreen extends StatefulWidget {
  final String userEmail;
  final bool isAdmin;
  final String? initialStoragePath;

  const WildlifeGalleryScreen({
    super.key,
    required this.userEmail,
    required this.isAdmin,
    this.initialStoragePath,
  });

  @override
  State<WildlifeGalleryScreen> createState() => WildlifeGalleryScreenState();
}

class WildlifeGalleryScreenState extends State<WildlifeGalleryScreen> {
  List<WildlifeGalleryItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadPhotos();
  }

  void _openInitialPhoto() {
    final pathOrId = widget.initialStoragePath;
    if (pathOrId == null || pathOrId.isEmpty || !mounted) return;
    final index = _items.indexWhere((p) =>
        p.storagePath == pathOrId || p.id == pathOrId);
    if (index < 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenProtectedImageViewer(
          items: _items,
          initialIndex: index,
          userEmail: widget.userEmail,
        ),
      ),
    );
  }

  Future<void> loadPhotos() async {
    setState(() => _isLoading = true);
    try {
      var query = supabase.from('wildlife_gallery').select();
      if (!widget.isAdmin) {
        query = query.eq('is_published', true);
      }
      final res = await query
          .order('editorial_priority', ascending: false)
          .order('created_at', ascending: false);

      if (mounted) {
        final rawList = (res as List).map((e) => WildlifeGalleryItem.fromJson(e)).toList();
        final now = DateTime.now().toUtc();

        final filteredList = widget.isAdmin
            ? rawList
            : rawList.where((item) {
                if (!item.isPublished) return false;
                if (item.scheduledPublishAt != null && item.scheduledPublishAt!.isAfter(now)) {
                  return false;
                }
                if (item.expiresAt != null && !item.expiresAt!.isAfter(now)) {
                  return false;
                }
                return true;
              }).toList();

        setState(() {
          _items = filteredList;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }

    if (widget.initialStoragePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialPhoto();
      });
    }
  }

  Future<void> _deletePhoto(WildlifeGalleryItem item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Delete Photo', style: TextStyle(color: Colors.white)),
            Text('(ছবিটি মুছে ফেলা নিশ্চিত করুন)',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        content: const Text(
            'Are you sure you want to completely delete this gallery photo from servers?\n(আপনি কি নিশ্চিত যে ছবিটি সম্পূর্ণভাবে মুছে ফেলতে চান?)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel (বাতিল)', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete (মুছে ফেলুন)'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (item.storagePath.isNotEmpty) {
        await supabase.storage
            .from('wildlife_gallery')
            .remove([item.storagePath]);
      }
      await supabase
          .from('wildlife_gallery')
          .delete()
          .eq('id', item.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Photo deleted successfully / ছবিটি মুছে ফেলা হয়েছে।')),
        );
        loadPhotos();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error deleting photo / ছবিটি মুছে ফেলা যায়নি।')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF00E676),
      onRefresh: loadPhotos,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(18),
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wildlife Gallery',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Text('(আরণ্যক চিত্রশালা)',
                      style: TextStyle(color: Color(0xFF81C784), fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
            )
          else if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF18221B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.photo_library_outlined, color: Color(0xFF00E676), size: 48),
                  SizedBox(height: 12),
                  Text(
                    'চিত্রশালায় বর্তমানে কোনো ছবি উপলব্ধ নেই।',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.8),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];

                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Protected Image Card with Signed Short-Lived URL
                      KeyboardPressEffect(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullscreenProtectedImageViewer(
                                items: _items,
                                initialIndex: index,
                                userEmail: widget.userEmail,
                              ),
                            ),
                          );
                        },
                        child: ProtectedImage(
                          bucket: 'wildlife_gallery',
                          storagePath: item.storagePath,
                          fit: BoxFit.cover,
                        ),
                      ),

                      // Gradient Bottom Overlay for Text Metadata
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              if (item.photographerCredit != null &&
                                  item.photographerCredit!.isNotEmpty)
                                Text(
                                  '📷 ${item.photographerCredit}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF81C784),
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Featured Badge
                      if (item.isFeatured)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFFD54F)),
                            ),
                            child: const Text(
                              '★ বিশেষ',
                              style: TextStyle(
                                color: Color(0xFFFFD54F),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                      // Admin Delete Overlay Button
                      if (widget.isAdmin)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: KeyboardPressEffect(
                            onTap: () => _deletePhoto(item),
                            depth: 2,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.redAccent),
                              ),
                              child: const Icon(Icons.delete_forever_rounded,
                                  color: Colors.redAccent, size: 17),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class FullscreenProtectedImageViewer extends StatefulWidget {
  final List<WildlifeGalleryItem> items;
  final int initialIndex;
  final String userEmail;

  const FullscreenProtectedImageViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.userEmail,
  });

  @override
  State<FullscreenProtectedImageViewer> createState() =>
      _FullscreenProtectedImageViewerState();
}

class _FullscreenProtectedImageViewerState
    extends State<FullscreenProtectedImageViewer> {
  late int _currentIndex;
  bool _showDetails = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    unawaited(ContentProtectionService.enable(
      scope: ContentProtectionScope.gallery,
      contentId: widget.items[widget.initialIndex].id,
      userId: widget.userEmail,
    ));
  }

  void _nextPhoto() {
    if (_currentIndex < widget.items.length - 1) {
      setState(() {
        _currentIndex++;
      });
      unawaited(ContentProtectionService.enable(
        scope: ContentProtectionScope.gallery,
        contentId: widget.items[_currentIndex].id,
        userId: widget.userEmail,
      ));
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      unawaited(ContentProtectionService.enable(
        scope: ContentProtectionScope.gallery,
        contentId: widget.items[_currentIndex].id,
        userId: widget.userEmail,
      ));
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  @override
  void dispose() {
    unawaited(ContentProtectionService.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        elevation: 0,
        title: Text(
          '${item.displayTitle} (${_currentIndex + 1}/${widget.items.length})',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showDetails ? Icons.info : Icons.info_outline,
              color: const Color(0xFF00E676),
            ),
            tooltip: 'বিবরণ দেখুন/লুকান',
            onPressed: () {
              setState(() => _showDetails = !_showDetails);
            },
          ),
        ],
      ),
      body: ProtectedContent(
        scope: ContentProtectionScope.gallery,
        contentId: item.id,
        userIdentity: widget.userEmail,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Zoomable Protected Photo View with Signed URL
            GestureDetector(
              onTap: () {
                setState(() => _showDetails = !_showDetails);
              },
              child: FutureBuilder<String?>(
                future: ProtectedAssetService.getSignedUrl(
                  bucket: 'wildlife_gallery',
                  storagePath: item.storagePath,
                  expiresInSeconds: 120,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00E676)),
                    );
                  }
                  final signedUrl = snapshot.data;
                  if (signedUrl == null) {
                    return const Center(
                      child: Icon(Icons.broken_image, color: Colors.white38, size: 48),
                    );
                  }
                  return PhotoView(
                    imageProvider: NetworkImage(signedUrl),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.contained * 3.0,
                  );
                },
              ),
            ),

            // Previous Navigation Button
            if (_currentIndex > 0)
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                      onPressed: _prevPhoto,
                    ),
                  ),
                ),
              ),

            // Next Navigation Button
            if (_currentIndex < widget.items.length - 1)
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded,
                          color: Colors.white, size: 20),
                      onPressed: _nextPhoto,
                    ),
                  ),
                ),
              ),

            // Bottom Metadata Drawer / Overlay
            if (_showDetails)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF142419).withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        ScientificText(
                          item.displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Metadata Row
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            if (item.photographerCredit != null &&
                                item.photographerCredit!.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.camera_alt_rounded,
                                      size: 13, color: Color(0xFF00E676)),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.photographerCredit!,
                                    style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            if (item.location != null && item.location!.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      size: 13, color: Color(0xFF81C784)),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.location!,
                                    style: const TextStyle(
                                        color: Color(0xFF81C784), fontSize: 12),
                                  ),
                                ],
                              ),
                            if (item.category != null && item.category!.isNotEmpty)
                              Text(
                                '📁 ${item.category}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            Text(
                              '📅 ${_formatDate(item.publishedAt ?? item.createdAt)}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),

                        // Description / Caption
                        if (item.displayDescription.isNotEmpty &&
                            item.displayDescription != item.displayTitle) ...[
                          const SizedBox(height: 8),
                          ScientificText(
                            item.displayDescription,
                            selectable: true,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
