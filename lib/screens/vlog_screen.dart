import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/vlog.dart';
import '../services/vlog_service.dart';
import '../services/sound_service.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/nature_background.dart';
import '../widgets/scientific_text.dart';
import 'vlog_detail_screen.dart';

class VlogScreen extends StatefulWidget {
  final String? initialVlogId;
  const VlogScreen({super.key, this.initialVlogId});

  @override
  State<VlogScreen> createState() => _VlogScreenState();
}

class _VlogScreenState extends State<VlogScreen> {
  final VlogService _vlogService = VlogService();
  List<Vlog> _vlogs = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _loadVlogs();
  }

  Future<void> _loadVlogs() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final list = await _vlogService.fetchPublishedVlogs();
      if (mounted) {
        setState(() {
          _vlogs = list;
          _isLoading = false;
        });

        // Handle initial vlog deep link routing if provided
        if (widget.initialVlogId != null && widget.initialVlogId!.isNotEmpty) {
          _handleInitialVlog(widget.initialVlogId!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'ভিডিও ব্লক লোড করতে সমস্যা হয়েছে (Error loading vlogs)';
        });
      }
    }
  }

  Future<void> _handleInitialVlog(String id) async {
    final existing = _vlogs.where((v) => v.id == id).firstOrNull;
    if (existing != null) {
      _openDetail(existing);
    } else {
      final fetched = await _vlogService.fetchVlogById(id);
      if (fetched != null && mounted) {
        _openDetail(fetched);
      }
    }
  }

  void _openDetail(Vlog vlog) {
    SoundService.playButtonSound();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VlogDetailScreen(vlog: vlog),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  List<String> get _categories {
    final set = <String>{'All'};
    for (var v in _vlogs) {
      if (v.category != null && v.category!.trim().isNotEmpty) {
        set.add(v.category!.trim());
      }
    }
    return set.toList();
  }

  List<Vlog> get _filteredVlogs {
    if (_selectedCategory == 'All') return _vlogs;
    return _vlogs.where((v) => v.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Nature Vlogs / প্রকৃতির দর্পণ',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E676)),
            tooltip: 'রিফ্রেশ / Refresh',
            onPressed: () {
              SoundService.playButtonSound();
              _loadVlogs();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: NatureBackgroundSwitcher(),
            ),
          ),
          SafeArea(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E676)),
            SizedBox(height: 16),
            Text(
              'ভিডিও ব্লক লোড হচ্ছে... (Loading Vlogs)',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'ভিডিও তথ্য লোড করা যায়নি',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              KeyboardPressEffect(
                onTap: _loadVlogs,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'পুনরায় চেষ্টা করুন (Retry)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_vlogs.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon Badge
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF142419),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.25),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/nature_log.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 52,
                      color: Color(0xFF00E676),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              const Text(
                'প্রকৃতির দর্পণ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nature Vlogs Series',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF81C784),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 20),

              // Bengali Empty Description
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF18221B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  'সুন্দরবন ও বনাঞ্চলের প্রকৃতির ভিডিওচিত্র ও নেচার ব্লগ শীঘ্রই আসছে। নতুন পর্ব প্রকাশের পর আপনি এখানে তা দেখতে পাবেন। সাথে থাকুন।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // "Coming Soon" Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E676)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: Color(0xFF00E676),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'শীঘ্রই আসছে... (Coming Soon)',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredVlogs;
    final categories = _categories;

    return Column(
      children: [
        // Category Filter Chips if multiple categories exist
        if (categories.length > 2)
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      cat == 'All' ? 'সব ভিডিও (All)' : cat,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00E676),
                    backgroundColor: const Color(0xFF18221B),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF00E676) : Colors.white12,
                    ),
                    onSelected: (val) {
                      if (val) {
                        SoundService.playButtonSound();
                        setState(() => _selectedCategory = cat);
                      }
                    },
                  ),
                );
              },
            ),
          ),

        // Vlog Item Vertical List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final item = filtered[index];
              return _buildVlogCard(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVlogCard(Vlog item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF18221B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isFeatured
              ? const Color(0xFF00E676).withValues(alpha: 0.5)
              : Colors.white12,
          width: item.isFeatured ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail with Play overlay
                Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF142419),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.thumbnailUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF00E676),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Image.asset(
                                  'assets/images/nature_log.png',
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Image.asset(
                                'assets/images/nature_log.png',
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Details Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badges
                      Row(
                        children: [
                          if (item.isFeatured) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFFD54F), width: 0.8),
                              ),
                              child: const Text(
                                '★ বিশেষ',
                                style: TextStyle(
                                  color: Color(0xFFFFD54F),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (item.category != null && item.category!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF00E676), width: 0.8),
                              ),
                              child: Text(
                                item.category!,
                                style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Title
                      ScientificText(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Snippet / Excerpt
                      if ((item.snippet != null && item.snippet!.isNotEmpty) ||
                          (item.description != null && item.description!.isNotEmpty))
                        ScientificText(
                          item.snippet?.isNotEmpty == true
                              ? item.snippet!
                              : item.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      const SizedBox(height: 10),

                      // Duration & Date
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF81C784)),
                              const SizedBox(width: 4),
                              Text(
                                item.formattedDuration,
                                style: const TextStyle(
                                  color: Color(0xFF81C784),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            _formatDate(item.publishedAt ?? item.createdAt),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
