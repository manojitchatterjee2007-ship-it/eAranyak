import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/vlog.dart';
import '../../services/vlog_service.dart';
import '../../services/push_notification_service.dart';
import '../scientific_text.dart';

class VlogAdminSection extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const VlogAdminSection({super.key, required this.onUploadComplete});

  @override
  State<VlogAdminSection> createState() => _VlogAdminSectionState();
}

class _VlogAdminSectionState extends State<VlogAdminSection> {
  final VlogService _vlogService = VlogService();

  List<Vlog> _vlogs = [];
  bool _isLoading = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadVlogs();
  }

  Future<void> _loadVlogs() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final list = await _vlogService.fetchAllVlogs(filter: _filter);
      if (mounted) {
        setState(() {
          _vlogs = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePublishStatusToggle(Vlog vlog) async {
    try {
      if (vlog.isPublished) {
        await _vlogService.unpublishVlog(vlog.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ব্লগ খসড়া অবস্থায় রাখা হয়েছে / Vlog unpublished.')),
          );
        }
      } else {
        await _vlogService.publishVlog(vlog.id);
        // Publishing Rule: Send notification ONLY on unpublished -> published!
        await AppNotifier.notify(
          title: '🎬 নতুন প্রকৃতি ব্লগ প্রকাশিত: ${vlog.title}',
          body: vlog.snippet?.isNotEmpty == true
              ? vlog.snippet!
              : 'আরণ্যক নতুন নেচার ব্লগ বা ভিডিও চিত্র দেখুন।',
          data: {'type': 'vlog', 'id': vlog.id},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ব্লগ সফলভাবে প্রকাশিত হয়েছে! / Vlog published successfully!')),
          );
        }
      }
      _loadVlogs();
      widget.onUploadComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling publish: $e')),
        );
      }
    }
  }

  Future<void> _handleDelete(Vlog vlog) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('🗑 Delete Vlog Record', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${vlog.title}"?\n(আপনি কি নিশ্চিত যে প্রকৃতি ব্লগটি স্থায়ীভাবে মুছে ফেলতে চান?)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _vlogService.deleteVlog(vlog.id, storagePath: vlog.storagePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ব্লগটি স্থায়ীভাবে মুছে ফেলা হয়েছে / Vlog deleted.')),
        );
        _loadVlogs();
        widget.onUploadComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting vlog: $e')),
        );
      }
    }
  }

  void _showAddOrEditDialog({Vlog? existingItem}) {
    final isEditing = existingItem != null;
    final titleCtrl = TextEditingController(text: existingItem?.title ?? '');
    final snippetCtrl = TextEditingController(text: existingItem?.snippet ?? '');
    final descCtrl = TextEditingController(text: existingItem?.description ?? '');
    final videoUrlCtrl = TextEditingController(text: existingItem?.videoUrl ?? '');
    final durationCtrl = TextEditingController(text: existingItem?.durationSeconds?.toString() ?? '');
    final categoryCtrl = TextEditingController(text: existingItem?.category ?? 'Nature');
    int priority = existingItem?.editorialPriority ?? 10;
    bool isFeatured = existingItem?.isFeatured ?? false;
    bool isPublished = existingItem?.isPublished ?? false;

    PlatformFile? selectedThumbnail;
    PlatformFile? selectedVideo;
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
                isEditing ? '✏️ Edit Nature Vlog' : '🎬 Add New Nature Vlog',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Vlog Title (ব্লগের শিরোনাম) *',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: snippetCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Short Snippet (সংক্ষিপ্ত বিবরণ)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Full Description (বিস্তারিত বিবরণ)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: categoryCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: durationCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Duration (Seconds)',
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
                                labelText: 'Priority',
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

                      TextField(
                        controller: videoUrlCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'External Video URL (ইউটিউব/বাহ্যিক লিংক - ঐচ্ছিক)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Video Upload Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                        onPressed: isUploading
                            ? null
                            : () async {
                                final res = await FilePicker.platform.pickFiles(
                                  type: FileType.video,
                                  withData: true,
                                );
                                if (res != null && res.files.isNotEmpty) {
                                  setDialogState(() => selectedVideo = res.files.first);
                                }
                              },
                        icon: const Icon(Icons.videocam, color: Colors.white),
                        label: Text(
                          selectedVideo != null
                              ? 'Selected Video: ${selectedVideo!.name}'
                              : (isEditing ? 'Replace Uploaded Video' : 'Upload Video File (.mp4)'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Thumbnail Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
                        onPressed: isUploading
                            ? null
                            : () async {
                                final res = await FilePicker.platform.pickFiles(
                                  type: FileType.image,
                                  withData: true,
                                );
                                if (res != null && res.files.isNotEmpty) {
                                  setDialogState(() => selectedThumbnail = res.files.first);
                                }
                              },
                        icon: const Icon(Icons.image, color: Colors.white),
                        label: Text(
                          selectedThumbnail != null
                              ? 'Selected Thumbnail: ${selectedThumbnail!.name}'
                              : 'Select Thumbnail Image',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        value: isFeatured,
                        activeTrackColor: const Color(0xFF00E676),
                        title: const Text('Featured Vlog', style: TextStyle(color: Colors.white)),
                        onChanged: (val) => setDialogState(() => isFeatured = val),
                      ),

                      SwitchListTile(
                        value: isPublished,
                        activeTrackColor: const Color(0xFF00E676),
                        title: const Text('Publish Immediately', style: TextStyle(color: Colors.white)),
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
                                Text('Uploading files to vlogs storage...', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                              const SnackBar(content: Text('Please enter a vlog title')),
                            );
                            return;
                          }

                          setDialogState(() => isUploading = true);

                          try {
                            String? videoUrl = videoUrlCtrl.text.trim().isNotEmpty
                                ? videoUrlCtrl.text.trim()
                                : existingItem?.videoUrl;
                            String? storagePath = existingItem?.storagePath;
                            String? thumbnailUrl = existingItem?.thumbnailUrl;

                            if (selectedVideo != null) {
                              final uploadVideoRes = await _vlogService.uploadFile(
                                file: selectedVideo!,
                                subFolder: 'videos',
                                isVideo: true,
                              );
                              videoUrl = uploadVideoRes['publicUrl'];
                              storagePath = uploadVideoRes['storagePath'];
                            }

                            if (selectedThumbnail != null) {
                              final uploadThumbRes = await _vlogService.uploadFile(
                                file: selectedThumbnail!,
                                subFolder: 'thumbnails',
                                isVideo: false,
                              );
                              thumbnailUrl = uploadThumbRes['publicUrl'];
                            }

                            final durationSec = int.tryParse(durationCtrl.text.trim());

                            if (isEditing) {
                              await _vlogService.updateVlog(
                                id: existingItem.id,
                                title: titleCtrl.text.trim(),
                                description: descCtrl.text.trim(),
                                snippet: snippetCtrl.text.trim(),
                                thumbnailUrl: thumbnailUrl,
                                videoUrl: videoUrl,
                                storagePath: storagePath,
                                durationSeconds: durationSec,
                                category: categoryCtrl.text.trim(),
                                priority: priority,
                                isFeatured: isFeatured,
                                isPublished: isPublished,
                                oldStoragePath: existingItem.storagePath,
                              );
                            } else {
                              await _vlogService.createVlog(
                                title: titleCtrl.text.trim(),
                                description: descCtrl.text.trim(),
                                snippet: snippetCtrl.text.trim(),
                                thumbnailUrl: thumbnailUrl,
                                videoUrl: videoUrl,
                                storagePath: storagePath,
                                durationSeconds: durationSec,
                                category: categoryCtrl.text.trim(),
                                priority: priority,
                                isFeatured: isFeatured,
                                isPublished: isPublished,
                              );
                            }

                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadVlogs();
                            widget.onUploadComplete();
                          } catch (e) {
                            setDialogState(() => isUploading = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error saving vlog: $e')),
                              );
                            }
                          }
                        },
                  child: Text(
                    isEditing ? 'Update' : 'Save',
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

  void _showPreviewDialog(Vlog vlog) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: Text('🎬 ${vlog.title}', style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (vlog.thumbnailUrl != null && vlog.thumbnailUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: vlog.thumbnailUrl!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 12),
              if (vlog.snippet?.isNotEmpty == true)
                Text(vlog.snippet!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Text('Duration: ${vlog.formattedDuration}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (vlog.videoUrl != null) ...[
                const SizedBox(height: 8),
                SelectableText('Video Link: ${vlog.videoUrl}', style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
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
                Text('🎬 Nature Vlog Management — প্রকৃতি ভিডিও ব্লগ নিয়ন্ত্রণ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('(ভিডিও ব্লগ প্রকাশ, সম্পাদনা ও খসড়া নিয়ন্ত্রণ — Public UI Coming Soon in Phase 7C)',
                    style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
              tooltip: 'রিফ্রেশ করুন',
              onPressed: _loadVlogs,
            ),
          ],
        ),
        const SizedBox(height: 12),

        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onPressed: () => _showAddOrEditDialog(),
          icon: const Icon(Icons.add_to_queue, size: 18, color: Colors.white),
          label: const Text('➕ নতুন নেচার ব্লগ যোগ করুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                    if (val) {
                      setState(() => _filter = f['id']!);
                      _loadVlogs();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
        else if (_vlogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text('কোনো নেচার ব্লগ পাওয়া যায়নি।', style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _vlogs.length,
            itemBuilder: (context, index) {
              final item = _vlogs[index];
              final statusColor = item.isPublished ? const Color(0xFF00E676) : Colors.amber;
              final statusText = item.isPublished ? 'প্রকাশিত' : 'খসড়া (Draft)';

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
                      Container(
                        width: 80,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(imageUrl: item.thumbnailUrl!, fit: BoxFit.cover),
                              )
                            : const Icon(Icons.movie_rounded, color: Color(0xFF81C784), size: 36),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScientificText(
                              item.title,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            if (item.snippet?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(item.snippet!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: statusColor, width: 0.8),
                                  ),
                                  child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                                  child: Text(item.formattedDuration, style: const TextStyle(fontSize: 10, color: Colors.white70)),
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
                                  icon: const Icon(Icons.play_circle_fill, size: 16),
                                  label: const Text('প্রিভিউ'),
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
