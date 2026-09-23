import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/wildlife_gallery_item.dart';
import '../../services/wildlife_gallery_admin_service.dart';
import '../../services/push_notification_service.dart';
import '../scientific_text.dart';

class GalleryAdminSection extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const GalleryAdminSection({super.key, required this.onUploadComplete});

  @override
  State<GalleryAdminSection> createState() => _GalleryAdminSectionState();
}

class _GalleryAdminSectionState extends State<GalleryAdminSection> {
  final WildlifeGalleryAdminService _galleryService = WildlifeGalleryAdminService();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<WildlifeGalleryItem> _items = [];
  bool _isLoading = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final list = await _galleryService.fetchAllGalleryItems();
      if (mounted) {
        setState(() {
          _items = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<WildlifeGalleryItem> get _filteredItems {
    if (_filter == 'published') {
      return _items.where((e) => e.isPublished).toList();
    } else if (_filter == 'draft') {
      return _items.where((e) => !e.isPublished).toList();
    } else if (_filter == 'featured') {
      return _items.where((e) => e.isFeatured).toList();
    }
    return _items;
  }

  String _getImagePublicUrl(String storagePath) {
    if (storagePath.startsWith('http://') || storagePath.startsWith('https://')) {
      return storagePath;
    }
    return _supabase.storage.from('wildlife_gallery').getPublicUrl(storagePath);
  }

  Future<void> _handlePublishStatusToggle(WildlifeGalleryItem item) async {
    try {
      final wasPublished = item.isPublished;
      if (wasPublished) {
        await _galleryService.unpublishGalleryItem(item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ছবি অপ্রকাশিত করা হয়েছে / Photo unpublished.')),
          );
        }
      } else {
        await _galleryService.publishGalleryItem(item.id);
        // Publishing Rule: Send notification ONLY when transitioning from unpublished to published!
        await AppNotifier.notify(
          title: 'নতুন ছবি যোগ হয়েছে! (New Gallery Photo)',
          body: item.displayTitle.isNotEmpty
              ? '${item.displayTitle} — দেখতে ট্যাপ করুন।'
              : 'বন্যপ্রাণের নতুন ছবি এসেছে — দেখতে ট্যাপ করুন।',
          data: {'type': 'gallery', 'id': item.storagePath},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ছবি সফলভাবে প্রকাশিত হয়েছে! / Photo published successfully!')),
          );
        }
      }
      _loadItems();
      widget.onUploadComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleDelete(WildlifeGalleryItem item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('🗑 Delete Gallery Photo', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${item.displayTitle}"?\n(আপনি কি নিশ্চিত যে ছবিটি স্থায়ীভাবে মুছে ফেলতে চান?)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel (বাতিল)', style: TextStyle(color: Colors.white54)),
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
      await _galleryService.deleteGalleryItem(item.id, item.storagePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ছবিটি সফলভাবে মুছে ফেলা হয়েছে / Photo deleted successfully.')),
        );
        _loadItems();
        widget.onUploadComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting photo: $e')),
        );
      }
    }
  }

  void _showAddOrEditDialog({WildlifeGalleryItem? existingItem}) {
    final isEditing = existingItem != null;
    final titleCtrl = TextEditingController(text: existingItem?.title ?? '');
    final descriptionCtrl = TextEditingController(text: existingItem?.description ?? existingItem?.caption ?? '');
    final locationCtrl = TextEditingController(text: existingItem?.location ?? '');
    final creditCtrl = TextEditingController(text: existingItem?.photographerCredit ?? '');
    final categoryCtrl = TextEditingController(text: existingItem?.category ?? 'Wildlife');
    int priority = existingItem?.editorialPriority ?? 10;
    bool isFeatured = existingItem?.isFeatured ?? false;
    bool isPublished = existingItem?.isPublished ?? true;

    PlatformFile? selectedFile;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF18221B),
              title: Text(
                isEditing ? '✏️ Edit Gallery Item' : '📸 Add Gallery Photo',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 550,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isEditing)
                        Container(
                          height: 140,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: _getImagePublicUrl(existingItem.storagePath),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                      // Pick Image Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                        ),
                        onPressed: isUploading
                            ? null
                            : () async {
                                // file_picker 13.x: single-file pick, null = cancelled.
                                final picked = await FilePicker.pickFile(
                                  type: FileType.image,
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    selectedFile = picked;
                                  });
                                }
                              },
                        icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                        label: Text(
                          selectedFile != null
                              ? 'Selected: ${selectedFile!.name}'
                              : (isEditing ? 'Replace Image (ঐচ্ছিক)' : 'Select Image File (ছবি বাছুন) *'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Title (শিরোনাম) *',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: descriptionCtrl,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Description / Caption (বর্ণনা)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: locationCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Location (স্থান)',
                                labelStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: creditCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Photographer (আলোকচিত্রী)',
                                labelStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: categoryCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Category (বিভাগ)',
                                labelStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: priority,
                              dropdownColor: const Color(0xFF18221B),
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Priority (অগ্রাধিকার)',
                                border: OutlineInputBorder(),
                              ),
                              items: [1, 5, 10, 20, 50, 100]
                                  .map((p) => DropdownMenuItem(value: p, child: Text('$p')))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setDialogState(() => priority = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        value: isFeatured,
                        activeTrackColor: const Color(0xFF00E676),
                        title: const Text('Featured Photo (বিশেষ স্লাইডে দেখান)', style: TextStyle(color: Colors.white)),
                        onChanged: (val) => setDialogState(() => isFeatured = val),
                      ),

                      SwitchListTile(
                        value: isPublished,
                        activeTrackColor: const Color(0xFF00E676),
                        title: const Text('Publish Immediately (অবিলম্বে প্রকাশ করুন)', style: TextStyle(color: Colors.white)),
                        onChanged: (val) => setDialogState(() => isPublished = val),
                      ),

                      if (isUploading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(color: Color(0xFF00E676)),
                                SizedBox(height: 8),
                                Text('Uploading image and saving record...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (titleCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a title / শিরোনাম প্রদান করুন')),
                            );
                            return;
                          }
                          if (!isEditing && selectedFile == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select an image file / ছবি নির্বাচন করুন')),
                            );
                            return;
                          }

                          setDialogState(() => isUploading = true);

                          try {
                            String? newPath;
                            if (selectedFile != null) {
                              final uploadRes = await _galleryService.uploadGalleryImage(selectedFile!);
                              newPath = uploadRes['storagePath'];
                            }

                            if (isEditing) {
                              final updated = await _galleryService.updateGalleryItem(
                                id: existingItem.id,
                                title: titleCtrl.text.trim(),
                                description: descriptionCtrl.text.trim(),
                                location: locationCtrl.text.trim(),
                                photographerCredit: creditCtrl.text.trim(),
                                category: categoryCtrl.text.trim(),
                                priority: priority,
                                isFeatured: isFeatured,
                                isPublished: isPublished,
                                newStoragePath: newPath,
                                oldStoragePath: existingItem.storagePath,
                              );

                              // Trigger notification ONLY if transitioned from draft -> published
                              if (!existingItem.isPublished && isPublished) {
                                await AppNotifier.notify(
                                  title: '📸 নতুন গ্যালারি চিত্র: ${updated.displayTitle}',
                                  body: updated.caption?.isNotEmpty == true
                                      ? updated.caption!
                                      : 'আরণ্যক গ্যালারিতে নতুন বন্যপ্রাণীর ছবি দেখুন।',
                                  data: {'type': 'gallery', 'id': updated.id},
                                );
                              }
                            } else {
                              final created = await _galleryService.createGalleryItem(
                                title: titleCtrl.text.trim(),
                                description: descriptionCtrl.text.trim(),
                                location: locationCtrl.text.trim(),
                                photographerCredit: creditCtrl.text.trim(),
                                category: categoryCtrl.text.trim(),
                                priority: priority,
                                isFeatured: isFeatured,
                                isPublished: isPublished,
                                storagePath: newPath!,
                              );

                              // Trigger notification ONLY if created directly in published state
                              if (isPublished) {
                                await AppNotifier.notify(
                                  title: '📸 নতুন গ্যালারি চিত্র: ${created.displayTitle}',
                                  body: created.caption?.isNotEmpty == true
                                      ? created.caption!
                                      : 'আরণ্যক গ্যালারিতে নতুন বন্যপ্রাণীর ছবি দেখুন।',
                                  data: {'type': 'gallery', 'id': created.id},
                                );
                              }
                            }

                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadItems();
                            widget.onUploadComplete();
                          } catch (e) {
                            setDialogState(() => isUploading = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Save error: $e')),
                              );
                            }
                          }
                        },
                  child: Text(
                    isEditing ? 'Update (হালনাগাদ)' : 'Save (সংরক্ষণ)',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPreviewDialog(WildlifeGalleryItem item) {
    final imageUrl = _getImagePublicUrl(item.storagePath);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: Text(item.displayTitle, style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (item.displayDescription.isNotEmpty)
                Text(item.displayDescription, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              if (item.location != null && item.location!.isNotEmpty)
                Text('📍 Location: ${item.location}', style: const TextStyle(color: Color(0xFF81C784), fontSize: 12)),
              if (item.photographerCredit != null && item.photographerCredit!.isNotEmpty)
                Text('📷 Photographer: ${item.photographerCredit}', style: const TextStyle(color: Color(0xFF81C784), fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close (বন্ধ করুন)', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🖼️ Wildlife Gallery Control Centre — চিত্রশালা ব্যবস্থাপনা',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('(ছবি প্রকাশ, সম্পাদনা ও সংগৃহীত ছবি নিয়ন্ত্রণ)', style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
              tooltip: 'রিফ্রেশ করুন',
              onPressed: _loadItems,
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.add_a_photo, size: 18, color: Colors.white),
              label: const Text('➕ নতুন ছবি যুক্ত করুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              {'id': 'all', 'label': 'সবগুলো'},
              {'id': 'published', 'label': 'প্রকাশিত'},
              {'id': 'draft', 'label': 'খসড়া'},
              {'id': 'featured', 'label': '⭐ Featured'},
            ].map((f) {
              final isSelected = _filter == f['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    f['label']!,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00E676),
                  backgroundColor: const Color(0xFF18221B),
                  onSelected: (val) {
                    if (val) setState(() => _filter = f['id']!);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
        else if (_filteredItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text('এই বিভাগে কোনো ছবি পাওয়া যায়নি।', style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredItems.length,
            itemBuilder: (context, index) {
              final item = _filteredItems[index];
              final statusColor = item.isPublished ? const Color(0xFF00E676) : Colors.amber;
              final statusText = item.isPublished ? 'প্রকাশিত' : 'খসড়া (Draft)';
              final imageUrl = _getImagePublicUrl(item.storagePath);

              return Card(
                color: const Color(0xFF18221B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 80,
                          height: 80,
                          color: Colors.black26,
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScientificText(
                              item.displayTitle,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            if (item.displayDescription.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.displayDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: statusColor, width: 0.8),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                  ),
                                ),
                                if (item.isFeatured)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('⭐ Featured', style: TextStyle(fontSize: 10, color: Colors.amber)),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Priority: ${item.editorialPriority}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white38),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => _showPreviewDialog(item),
                                  icon: const Icon(Icons.visibility, size: 16),
                                  label: const Text('প্ৰিভিউ'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF81C784),
                                    side: const BorderSide(color: Color(0xFF81C784)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => _showAddOrEditDialog(existingItem: item),
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('সম্পাদনা'),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: item.isPublished ? Colors.orange.shade800 : const Color(0xFF00E676),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => _handlePublishStatusToggle(item),
                                  icon: Icon(item.isPublished ? Icons.visibility_off : Icons.publish_rounded, size: 16, color: item.isPublished ? Colors.white : Colors.black),
                                  label: Text(
                                    item.isPublished ? 'Unpublish' : '📢 Publish',
                                    style: TextStyle(color: item.isPublished ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  tooltip: 'স্থায়ীভাবে মুছে ফেলুন',
                                  onPressed: () => _handleDelete(item),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
