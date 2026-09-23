import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/forest_ambience_service.dart';
import '../services/forest_scene_manager.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/magazine_cover_image.dart';
import '../widgets/realistic_rack_widget.dart';
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
  int _sceneIndex = 0;

  void loadMagazines() {
    _loadUserBookshelf();
  }

  @override
  void initState() {
    super.initState();
    _loadSceneIndex();
    _loadUserBookshelf();
    ForestAmbienceService.startAmbience();
  }

  Future<void> _loadSceneIndex() async {
    final idx = await ForestSceneManager.pickFor('bookshelf');
    if (mounted) {
      setState(() {
        _sceneIndex = idx;
      });
    }
  }

  @override
  void dispose() {
    ForestAmbienceService.stopAmbience();
    super.dispose();
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
    final bookshelfCards = _downloadedMagazines.map((mag) {
      final id = mag['id'].toString();
      final title = formatMagazineTitle(mag['title']?.toString());
      final issueDate = mag['issue_date']?.toString() ?? '';
      final progress = _progressMap[id] ?? 0.0;

      return KeyboardPressEffect(
        onTap: () {
          SoundService.playButtonSound();
          // FIX: Stop ambience before launching reader
          ForestAmbienceService.stopAmbience();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProtectedReaderScreen(
                magazineId: id,
                title: title,
                userEmail: widget.userEmail,
              ),
            ),
          ).then((_) {
            _loadUserBookshelf();
            // FIX: Restart ambience when returning to Bookshelf
            ForestAmbienceService.startAmbience();
          });
        },
        child: Container(
          width: 170,
          height: 235,
          decoration: BoxDecoration(
            color: const Color(0xFF142419),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MagazineCoverImage(
                  magazineId: id,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 170 - 16),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      issueDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: InkWell(
                    onTap: () => _confirmRemoveMagazine(mag),
                    child: Container(
                      padding: const EdgeInsets.all(5),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    color: Colors.black.withValues(alpha: 0.88),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        if (progress > 0.01) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3.5,
                                    backgroundColor: Colors.white12,
                                    color: const Color(0xFF00E676),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${(progress * 100).round()}%',
                                style: const TextStyle(
                                  fontSize: 9.5,
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
      );
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.85),
        title: const Text('📖  My Bookshelf - আমার বইয়ের তাক', style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00E676)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              ForestSceneManager.assetPath(_sceneIndex),
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(80),
                            child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                          )
                        : _downloadedMagazines.isEmpty
                            ? Center(
                                child: Container(
                                  padding: const EdgeInsets.all(32),
                                  margin: const EdgeInsets.symmetric(horizontal: 24),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF142018).withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
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
                                          // FIX: Stop ambience before navigating away
                                          ForestAmbienceService.stopAmbience();
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => LibraryScreen(userEmail: widget.userEmail),
                                            ),
                                          ).then((_) {
                                            _loadUserBookshelf();
                                            // FIX: Restart ambience when returning to Bookshelf
                                            ForestAmbienceService.startAmbience();
                                          });
                                        },
                                        icon: const Icon(Icons.library_books_rounded),
                                        label: const Text('📚 লাইব্রেরি ব্রাউজ করুন', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : RealisticRackWidget(
                                isWooden: true,
                                children: bookshelfCards,
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}