import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/writing_submission_service.dart';

class WritingSubmissionScreen extends StatefulWidget {
  const WritingSubmissionScreen({super.key});

  @override
  State<WritingSubmissionScreen> createState() => _WritingSubmissionScreenState();
}

class _WritingSubmissionScreenState extends State<WritingSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  final WritingSubmissionService _service = WritingSubmissionService();

  final List<PlatformFile> _selectedPhotos = [];

  /// file_picker 13.x removed `PlatformFile.bytes`; thumbnails are fed from the
  /// bytes read once at pick time instead of from the picker result.
  final Map<PlatformFile, Uint8List> _photoPreviewBytes = {};

  int _wordCount = 0;
  bool _isSubmitting = false;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _contentCtrl.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    setState(() {
      _wordCount = WritingSubmissionService.countWords(_contentCtrl.text);
    });
  }

  Future<void> _loadUserName() async {
    final name = await _service.getCurrentUserName();
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) {
          _authorCtrl.text = name;
        }
        _loadingProfile = false;
      });
    }
  }

  Future<void> _pickPhotos() async {
    try {
      // file_picker 13.x: `pickFiles()` returns the picked files directly
      // (multiple selection is the default); an empty list means cancelled.
      final picked = await FilePicker.pickFiles(type: FileType.image);

      if (picked.isEmpty) return;

      // Warm the thumbnail cache so the preview list does not re-read the file
      // bytes on every rebuild.
      for (final file in picked) {
        try {
          _photoPreviewBytes[file] = await file.readAsBytes();
        } catch (_) {
          // Preview falls back to the file path / placeholder icon.
        }
      }

      setState(() {
        _selectedPhotos.addAll(picked);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ছবি নির্বাচন করতে সমস্যা হয়েছে: $e')),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      final removed = _selectedPhotos.removeAt(index);
      _photoPreviewBytes.remove(removed);
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final title = _titleCtrl.text.trim();
    final author = _authorCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে লেখার শিরোনাম দিন')),
      );
      return;
    }

    if (author.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে লেখকের নাম দিন')),
      );
      return;
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে আপনার লেখাটি লিখুন')),
      );
      return;
    }

    if (_wordCount > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'লেখাটি ১,০০০ শব্দের সীমা অতিক্রম করেছে ($_wordCount / 1000)। অনুগ্রহ করে লেখাটি সংক্ষেপ করুন।',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _service.submitWriting(
        title: title,
        authorName: author,
        articleContent: content,
        photos: _selectedPhotos,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('লেখা জমা দিতে ব্যর্থ হয়েছে: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E281E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF81C784), width: 1.5),
        ),
        title: const Row(
          children: [
            Text('🌿 ', style: TextStyle(fontSize: 22)),
            Expanded(
              child: Text(
                'লেখা সফলভাবে গৃহীত হয়েছে!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'এখন আরণ্যক-এ আপনার লেখা পাঠাবার জন্য ধন্যবাদ।\n\n'
          'আমাদের সম্পাদকীয় দল লেখাটি পর্যালোচনা করার পর নির্বাচিত হলে অ্যাপে প্রকাশিত হবে।',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 14, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(); // Dismiss dialog
              Navigator.of(context).pop(); // Return to home screen
            },
            child: const Text('ধন্যবাদ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isExceeded = _wordCount > 1000;

    return Scaffold(
      backgroundColor: const Color(0xFF121B12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E281E),
        elevation: 2,
        title: const Text(
          '✍️ লেখার আবেদন জমা দিন',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loadingProfile
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF81C784)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E281E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF388E3C).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🌿 প্রকৃতি নিয়ে আপনার ভাবনা আমাদের সঙ্গে ভাগ করে নিন',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA5D6A7),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'প্রকৃতি, বন, বন্যপ্রাণী, পাখি বা পরিবেশ নিয়ে আপনার অভিজ্ঞতা এবং ভাবনা লিখে পাঠাতে পারেন। '
                            'নির্বাচিত লেখা ও নিজের তোলা ছবি প্রকাশিত হতে পারে এখন আরণ্যক App-এ।',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // FIELD 1: Title
                    const Text(
                      '১. লেখার শিরোনাম *',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'আপনার লেখা বা প্রবন্ধের নাম দিন',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1E281E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF81C784)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // FIELD 2: Author Name
                    const Text(
                      '২. লেখকের নাম *',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _authorCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'আপনার নাম দিন',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1E281E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF81C784)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // FIELD 3: Writing Area + Word Counter
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '৩. আপনার লেখা *',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isExceeded
                                ? Colors.red.withValues(alpha: 0.2)
                                : const Color(0xFF2E7D32).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isExceeded
                                  ? Colors.redAccent
                                  : const Color(0xFF81C784),
                            ),
                          ),
                          child: Text(
                            '$_wordCount / 1000 words',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isExceeded ? Colors.redAccent : const Color(0xFFA5D6A7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contentCtrl,
                      maxLines: 12,
                      style: const TextStyle(color: Colors.white, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'এখানে আপনার মূল প্রবন্ধ বা অভিজ্ঞতা লিখুন (এক হাজার শব্দের মধ্যে)...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1E281E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isExceeded ? Colors.redAccent : const Color(0xFF81C784),
                          ),
                        ),
                      ),
                    ),
                    if (isExceeded) ...[
                      const SizedBox(height: 6),
                      const Text(
                        '⚠️ আপনার লেখা ১,০০০ শব্দের সীমা অতিক্রম করেছে। অনুগ্রহ করে সামান্য সংক্ষেপ করুন।',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // FIELD 4: Photo Attachments
                    const Text(
                      '৪. আপনার তোলা ছবি (ঐচ্ছিক)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '📷 অনুগ্রহ করে নিশ্চিত করুন যে ছবিটি আপনার নিজের তোলা।',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 10),

                    if (_selectedPhotos.isNotEmpty) ...[
                      SizedBox(
                        height: 90,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedPhotos.length,
                          itemBuilder: (context, index) {
                            final file = _selectedPhotos[index];
                            final previewBytes = _photoPreviewBytes[file];
                            return Stack(
                              children: [
                                Container(
                                  width: 90,
                                  height: 90,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF81C784),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: previewBytes != null
                                        ? Image.memory(
                                            previewBytes,
                                            fit: BoxFit.cover,
                                          )
                                        : (file.path != null
                                            ? Image.file(
                                                File(file.path!),
                                                fit: BoxFit.cover,
                                              )
                                            : const Icon(
                                                Icons.image,
                                                color: Colors.white54,
                                              )),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 16,
                                  child: GestureDetector(
                                    onTap: () => _removePhoto(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA5D6A7),
                        side: const BorderSide(color: Color(0xFF388E3C)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _pickPhotos,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(
                        _selectedPhotos.isEmpty
                            ? 'ছবি যোগ করুন'
                            : 'আরও ছবি যোগ করুন (${_selectedPhotos.length})',
                      ),
                    ),
                    const SizedBox(height: 32),

                    // SUBMIT BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: (_isSubmitting || isExceeded) ? null : _submit,
                        child: _isSubmitting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'লেখা পাঠানো হচ্ছে...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                '📤 লেখা পাঠান',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }
}
