import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/sound_service.dart';
import '../widgets/keyboard_press_effect.dart';
import 'magazine_reader_screen.dart';
import 'library_screen.dart';

class UserBookshelfScreen extends StatefulWidget {
  final String userEmail;
  const UserBookshelfScreen({super.key, required this.userEmail});

  @override
  State<UserBookshelfScreen> createState() => UserBookshelfScreenState();
}

class UserBookshelfScreenState extends State<UserBookshelfScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _downloadedMagazines = [];
  Map<String, double> _progressMap = {};
  bool _loading = true;

  void loadMagazines() {
    _loadUserBookshelf();
  }

  @override
  void initState() {
    super.initState();
    _loadUserBookshelf();
  }

  Future<void> _loadUserBookshelf() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final downloadedIds = prefs.getStringList('downloaded_magazine_ids') ?? [];
    List<Map<String, dynamic>> mags = [];
    for (final id in downloadedIds) {
      final raw = prefs.getString('mag_meta_$id');
      if (raw != null) {
        try {
          mags.add(jsonDecode(raw));
        } catch (_) {}
      }
    }

    if (mags.isEmpty && downloadedIds.isEmpty) {
      try {
        final allMags = await _supabase.from('magazines').select();
        for (final m in allMags) {
          final id = m['id'].toString();
          if (prefs.getBool('downloaded_mag_$id') == true) {
            mags.add(m);
            if (!downloadedIds.contains(id)) downloadedIds.add(id);
          }
        }
        await prefs.setStringList('downloaded_magazine_ids', downloadedIds);
      } catch (_) {}
    }

    final Map<String, double> newProgress = {};
    for (final mag in mags) {
      final String magId = mag['id'].toString();
      final double p = prefs.getDouble('progress_$magId') ?? 0.0;
      newProgress[magId] = p;
    }

    if (mounted) {
      setState(() {
        _downloadedMagazines = mags;
        _progressMap = newProgress;
        _loading = false;
      });
    }
  }

  Future<void> _confirmRemoveMagazine(Map<String, dynamic> mag) async {
    SoundService.playButtonSound();
    final id = mag['id'].toString();
    final title = mag['title']?.toString() ?? 'ম্যাগাজিন';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('বুকশেলফ থেকে মুছবেন?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('"$title" ম্যাগাজিনটি আপনার বুকশেলফ থেকে সরিয়ে নেওয়া হবে।',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('সরিয়ে নিন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('downloaded_mag_$id');
      await prefs.remove('mag_meta_$id');
      List<String> downloadedIds = prefs.getStringList('downloaded_magazine_ids') ?? [];
      downloadedIds.remove(id);
      await prefs.setStringList('downloaded_magazine_ids', downloadedIds);

      _loadUserBookshelf();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('বুকশেলফ থেকে ম্যাগাজিনটি সরিয়ে নেওয়া হয়েছে।')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<List<Map<String, dynamic>>> shelves = [];
    for (int i = 0; i < _downloadedMagazines.length; i += 2) {
      shelves.add(
        _downloadedMagazines.sublist(
            i, (i + 2 > _downloadedMagazines.length) ? _downloadedMagazines.length : i + 2),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: const Text('📖  My Bookshelf - আমার বইয়ের তাক', style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00E676)),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF00E676),
        onRefresh: _loadUserBookshelf,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
            : _downloadedMagazines.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF18221B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.newspaper_rounded, size: 56, color: Color(0xFF00E676)),
                              const SizedBox(height: 16),
                              const Text(
                                'আপনার বুকশেলফে কোনো ম্যাগাজিন নেই',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'লাইব্রেরি থেকে আপনার পছন্দের ম্যাগাজিনগুলো ডাউনলোড করুন এবং যেকোনো সময় সহজে পড়ুন।',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.5),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E676),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  SoundService.playButtonSound();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LibraryScreen(userEmail: widget.userEmail),
                                    ),
                                  ).then((_) => _loadUserBookshelf());
                                },
                                icon: const Icon(Icons.library_books_rounded),
                                label: const Text('📚 লাইব্রেরি ব্রাউজ করুন', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: shelves.length,
                    itemBuilder: (context, shelfIndex) {
                      final shelfItems = shelves[shelfIndex];

                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: shelfItems.map((mag) {
                              final id = mag['id'].toString();
                              final title = mag['title']?.toString() ?? 'Untitled';
                              final issueDate = mag['issue_date']?.toString() ?? '';
                              final totalPages = mag['total_pages']?.toString() ?? '';
                              final coverUrl = _supabase.storage
                                  .from('magazine_pages')
                                  .getPublicUrl('$id/page_1.jpg');
                              final progress = _progressMap[id] ?? 0.0;

                              return KeyboardPressEffect(
                                onTap: () {
                                  SoundService.playButtonSound();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProtectedReaderScreen(
                                        magazineId: id,
                                        title: title,
                                        userEmail: widget.userEmail,
                                      ),
                                    ),
                                  ).then((_) => _loadUserBookshelf());
                                },
                                child: Container(
                                  width: 155,
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        blurRadius: 12,
                                        offset: const Offset(4, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        height: 215,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF142419),
                                          borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(6)),
                                          border: Border.all(
                                              color: const Color(0xFF00E676)
                                                  .withValues(alpha: 0.35)),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(5)),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              CachedNetworkImage(
                                                imageUrl: coverUrl,
                                                fit: BoxFit.cover,
                                                placeholder: (c, u) => const Center(
                                                  child: SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Color(0xFF00E676),
                                                    ),
                                                  ),
                                                ),
                                                errorWidget: (c, u, e) => const Icon(
                                                    Icons.menu_book_rounded,
                                                    color: Color(0xFF00E676),
                                                    size: 36),
                                              ),
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: InkWell(
                                                  onTap: () => _confirmRemoveMagazine(mag),
                                                  child: Container(
                                                    padding: const EdgeInsets.all(4),
                                                    decoration: const BoxDecoration(
                                                      color: Colors.black54,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.delete_outline_rounded,
                                                        color: Colors.redAccent, size: 16),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 0,
                                                left: 0,
                                                right: 0,
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  color: Colors.black87,
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.bold),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '$issueDate • $totalPages Pages',
                                                        textAlign: TextAlign.center,
                                                        style: const TextStyle(
                                                            fontSize: 9,
                                                            color: Color(0xFF81C784)),
                                                      ),
                                                      if (progress > 0.01) ...[
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                BorderRadius.circular(
                                                                    2),
                                                                child:
                                                                LinearProgressIndicator(
                                                                  value: progress,
                                                                  minHeight: 3,
                                                                  backgroundColor:
                                                                  Colors.white12,
                                                                  color: const Color(
                                                                      0xFF00E676),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 5),
                                                            Text(
                                                              '${(progress * 100).round()}%',
                                                              style: const TextStyle(
                                                                fontSize: 8,
                                                                color: Color(0xFF00E676),
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          // Realistic Wooden Shelf Plank
                          Container(
                            height: 18,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF8D5B34),
                                  Color(0xFF5A381E),
                                  Color(0xFF3B2211)
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.all(Radius.circular(4)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}
