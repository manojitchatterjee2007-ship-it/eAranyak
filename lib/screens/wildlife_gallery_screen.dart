import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../services/push_notification_service.dart';
import '../widgets/keyboard_press_effect.dart';

class WildlifeGalleryScreen extends StatefulWidget {
  final String userEmail;
  final bool isAdmin;
  final String? initialStoragePath;

  const WildlifeGalleryScreen(
      {super.key,
        required this.userEmail,
        required this.isAdmin,
        this.initialStoragePath});

  @override
  State<WildlifeGalleryScreen> createState() => WildlifeGalleryScreenState();
}

class WildlifeGalleryScreenState extends State<WildlifeGalleryScreen> {
  final _titleCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();
  List<Map<String, dynamic>> _photos = [];

  @override
  void initState() {
    super.initState();
    loadPhotos();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  void _openInitialPhoto() {
    final path = widget.initialStoragePath;
    if (path == null || path.isEmpty || !mounted) return;
    final index = _photos.indexWhere((p) =>
        (p['storage_path'] ?? '').toString() == path);
    if (index < 0) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => FullscreenProtectedImageViewer(
                photos: _photos,
                initialIndex: index,
                userEmail: widget.userEmail)));
  }

  Future<void> loadPhotos() async {
    try {
      final res = await supabase
          .from('wildlife_gallery')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _photos = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
    if (widget.initialStoragePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialPhoto();
      });
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.single.bytes == null) {
      return;
    }

    try {
      final fileBytes = result.files.single.bytes!;
      final filename =
          '${DateTime.now().millisecondsSinceEpoch}_${result.files.single.name}';
      final storagePath = 'photos/$filename';

      await supabase.storage.from('wildlife_gallery').uploadBinary(
          storagePath, fileBytes,
          fileOptions:
          const FileOptions(contentType: 'image/jpeg', upsert: true));
      await supabase.from('wildlife_gallery').insert({
        'title': _titleCtrl.text.trim(),
        'caption': _captionCtrl.text.trim(),
        'storage_path': storagePath
      });

      unawaited(AppNotifier.notify(
        title: 'নতুন ছবি যোগ হয়েছে! (New Gallery Photo)',
        body: _titleCtrl.text.trim().isNotEmpty
            ? '${_titleCtrl.text.trim()} — দেখতে ট্যাপ করুন।'
            : 'বন্যপ্রাণের নতুন ছবি এসেছে — দেখতে ট্যাপ করুন।',
        data: {'type': 'gallery', 'id': storagePath},
      ));

      _titleCtrl.clear();
      _captionCtrl.clear();
      loadPhotos();
    } catch (_) {}
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Delete Photo'),
            Text('(ছবিটি মুছে ফেলা নিশ্চিত করুন)',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        content: const Text(
            'Are you sure you want to completely delete this gallery photo from servers?\n(আপনি কি নিশ্চিত যে ছবিটি সম্পূর্ণভাবে মুছে ফেলতে চান?)'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancel (বাতিল)',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx, true);
            },
            child: const Text('Delete (মুছে ফেলুন)'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      final storagePath = (photo['storage_path'] ?? '').toString();
      if (storagePath.isNotEmpty) {
        await supabase.storage
            .from('wildlife_gallery')
            .remove([storagePath]);
      }
      await supabase
          .from('wildlife_gallery')
          .delete()
          .eq('id', photo['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Photo deleted successfully / ছবিটি মুছে ফেলা হয়েছে।')),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
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
              if (widget.isAdmin)
                KeyboardPressEffect(
                  onTap: _pickAndUploadPhoto,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_a_photo, size: 18, color: Colors.black),
                        SizedBox(width: 8),
                        Text('Add Photo (ছবি যোগ করুন)',
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
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.82),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final signedUrl = supabase.storage
                  .from('wildlife_gallery')
                  .getPublicUrl(photo['storage_path']);

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    KeyboardPressEffect(
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => FullscreenProtectedImageViewer(
                                    photos: _photos,
                                    initialIndex: index,
                                    userEmail: widget.userEmail)));
                      },
                      child: CachedNetworkImage(
                          imageUrl: signedUrl, fit: BoxFit.cover),
                    ),
                    if (widget.isAdmin)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: KeyboardPressEffect(
                          onTap: () => _deletePhoto(photo),
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
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final String userEmail;

  const FullscreenProtectedImageViewer({
    super.key,
    required this.photos,
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _nextPhoto() {
    if (_currentIndex < widget.photos.length - 1) {
      setState(() {
        _currentIndex++;
      });
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    final signedUrl = supabase.storage
        .from('wildlife_gallery')
        .getPublicUrl(photo['storage_path']);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(
            '${photo['title'] ?? 'Gallery'} (${_currentIndex + 1}/${widget.photos.length})'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          PhotoView(
            imageProvider: CachedNetworkImageProvider(signedUrl),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.contained * 2.5,
          ),
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
          if (_currentIndex < widget.photos.length - 1)
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
        ],
      ),
    );
  }
}
