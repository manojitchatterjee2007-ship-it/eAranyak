import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../widgets/magazine_cover_image.dart';

class LibraryScreen extends StatefulWidget {
  final String userEmail;
  const LibraryScreen({super.key, required this.userEmail});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _magazines = [];
  List<Map<String, dynamic>> _filteredMagazines = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();

  // magazineId -> 'none' | 'downloading' | 'downloaded'
  final Map<String, String> _downloadStates = {};

  @override
  void initState() {
    super.initState();
    _loadMagazines();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMagazines() async {
    setState(() => _loading = true);
    try {
      final magRes = await _supabase.from('magazines').select().order('created_at', ascending: false);
      final mags = List<Map<String, dynamic>>.from(magRes);

      final prefs = await SharedPreferences.getInstance();
      for (final mag in mags) {
        final id = mag['id'].toString();
        final downloaded = prefs.getBool('downloaded_mag_$id') ?? false;
        _downloadStates[id] = downloaded ? 'downloaded' : 'none';
      }

      if (mounted) {
        setState(() {
          _magazines = mags;
          _filteredMagazines = mags;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadMagazine(Map<String, dynamic> mag) async {
    final id = mag['id'].toString();
    setState(() {
      _downloadStates[id] = 'downloading';
    });

    try {
      final pages = await _supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', id)
          .limit(1);

      if (pages.isEmpty) {
        throw Exception('Magazine pages not found');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_mag_$id', true);

      List<String> downloadedIds = prefs.getStringList('downloaded_magazine_ids') ?? [];
      if (!downloadedIds.contains(id)) {
        downloadedIds.add(id);
        await prefs.setStringList('downloaded_magazine_ids', downloadedIds);
      }
      await prefs.setString('mag_meta_$id', jsonEncode(mag));

      if (mounted) {
        setState(() {
          _downloadStates[id] = 'downloaded';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ "${mag['title']}" সফলভাবে ডাউনলোড হয়েছে এবং আপনার বুকশেলফে যুক্ত হয়েছে!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadStates[id] = 'none';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ডাউনলোড ব্যর্থ হয়েছে: ${e.toString()}')),
        );
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredMagazines = _magazines;
      } else {
        _filteredMagazines = _magazines.where((m) {
          final title = (m['title'] ?? '').toLowerCase();
          final date = (m['issue_date'] ?? '').toLowerCase();
          return title.contains(query) || date.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<List<Map<String, dynamic>>> racks = [];
    for (int i = 0; i < _filteredMagazines.length; i += 2) {
      racks.add(
        _filteredMagazines.sublist(
            i, (i + 2 > _filteredMagazines.length) ? _filteredMagazines.length : i + 2),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: const Text('📚  Library - লাইব্রেরি', style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00E676)),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E2E23), Color(0xFF142419)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border(bottom: BorderSide(color: Color(0xFF00E676), width: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'প্রকৃতি ও বন্যপ্রাণ ডিজিটাল ম্যাগাজিন লাইব্রেরি',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'আপনার পছন্দের ম্যাগাজিন সংখ্যা ব্রাউজ করুন এবং ডাউনলোড করে বুকশেলফে রাখুন (শুধুমাত্র ডাউনলোড অপশন)।',
                  style: TextStyle(color: Color(0xFF81C784), fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'ম্যাগাজিনের নাম বা তারিখ দিয়ে খুঁজুন...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E676)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF101A13),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF00E676), width: 1.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF00E676),
              onRefresh: _loadMagazines,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                  : _filteredMagazines.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(28),
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF18221B),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(Icons.newspaper_rounded, size: 52, color: Color(0xFF81C784)),
                                    SizedBox(height: 14),
                                    Text(
                                      'কোনো ম্যাগাজিন পাওয়া যায়নি',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'অনুগ্রহ করে অন্য শব্দ দিয়ে খুঁজুন অথবা পরবর্তীতে আবার চেষ্টা করুন।',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          itemCount: racks.length,
                          itemBuilder: (context, rackIndex) {
                            final rackItems = racks[rackIndex];

                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: rackItems.map((mag) {
                                    final id = mag['id'].toString();
                                    final title = formatMagazineTitle(mag['title']?.toString());
                                    final issueDate = mag['issue_date']?.toString() ?? '';
                                    final totalPages = mag['total_pages']?.toString() ?? '';
                                    final downloadState = _downloadStates[id] ?? 'none';

                                    return Container(
                                      width: 155,
                                      margin: const EdgeInsets.only(bottom: 2),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.6),
                                            blurRadius: 10,
                                            offset: const Offset(3, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Container(
                                            height: 215,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF152018),
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                              border: Border.all(
                                                  color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  MagazineCoverImage(
                                                    magazineId: id,
                                                    fit: BoxFit.cover,
                                                  ),
                                                  Positioned(
                                                    top: 6,
                                                    left: 6,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withValues(alpha: 0.7),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                                                      ),
                                                      child: Text(
                                                        issueDate,
                                                        style: const TextStyle(
                                                          color: Color(0xFF00E676),
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    bottom: 0,
                                                    left: 0,
                                                    right: 0,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(8),
                                                      color: Colors.black87,
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            title,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            '$totalPages Pages',
                                                            style: const TextStyle(
                                                              color: Color(0xFF81C784),
                                                              fontSize: 9.5,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 6),
                                                          downloadState == 'downloaded'
                                                              ? Container(
                                                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                                                  alignment: Alignment.center,
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFF00E676).withValues(alpha: 0.2),
                                                                    borderRadius: BorderRadius.circular(6),
                                                                    border: Border.all(color: const Color(0xFF00E676)),
                                                                  ),
                                                                  child: const Row(
                                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                                    children: [
                                                                      Icon(Icons.check_rounded, color: Color(0xFF00E676), size: 14),
                                                                      SizedBox(width: 4),
                                                                      Text('ডাউনলোড করা', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
                                                                    ],
                                                                  ),
                                                                )
                                                              : downloadState == 'downloading'
                                                                  ? const Center(
                                                                      child: SizedBox(
                                                                        width: 20,
                                                                        height: 20,
                                                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)),
                                                                      ),
                                                                    )
                                                                  : ElevatedButton(
                                                                      style: ElevatedButton.styleFrom(
                                                                        backgroundColor: const Color(0xFF00E676),
                                                                        foregroundColor: Colors.black,
                                                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                                                        minimumSize: Size.zero,
                                                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                                      ),
                                                                      onPressed: () {
                                                                        SoundService.playButtonSound();
                                                                        _downloadMagazine(mag);
                                                                      },
                                                                      child: const Text('ডাউনলোড (Download)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                                                    ),
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
                                    );
                                  }).toList(),
                                ),
                                // Realistic Perforated Metal Rack Shelf
                                Container(
                                  height: 16,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF78909C),
                                        Color(0xFF455A64),
                                        Color(0xFF263238),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                                    border: Border.all(color: Colors.white24, width: 0.5),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: List.generate(24, (index) => Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF102027),
                                        shape: BoxShape.circle,
                                      ),
                                    )),
                                  ),
                                ),
                                const SizedBox(height: 30),
                              ],
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
