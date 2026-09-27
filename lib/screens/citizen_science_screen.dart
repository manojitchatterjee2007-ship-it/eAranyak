import 'package:flutter/material.dart';

import '../models/wildlife_sighting.dart';
import '../services/citizen_science_service.dart';
import '../services/sound_service.dart';
import '../widgets/citizen_science/sighting_card.dart';
import 'contributor_profile_screen.dart';
import 'sighting_detail_screen.dart';
import 'sighting_submission_screen.dart';

/// Public "নাগরিক বিজ্ঞান — বন্যপ্রাণ দর্শন" experience.
///
/// Everything rendered here comes from the masked public view
/// (public.public_wildlife_sightings): no coordinates, no private notes and no
/// unpublished records can reach this screen.
class CitizenScienceScreen extends StatefulWidget {
  final String? initialSightingId;

  const CitizenScienceScreen({super.key, this.initialSightingId});

  @override
  State<CitizenScienceScreen> createState() => _CitizenScienceScreenState();
}

class _CitizenScienceScreenState extends State<CitizenScienceScreen> {
  final CitizenScienceService _service = CitizenScienceService();

  List<PublicWildlifeSighting> _all = <PublicWildlifeSighting>[];
  List<PublicWildlifeSighting> _filtered = <PublicWildlifeSighting>[];
  List<Map<String, dynamic>> _popularSpecies = <Map<String, dynamic>>[];

  bool _isLoading = true;
  bool _hasAnyContent = false;
  String? _myDistrict;

  final TextEditingController _searchCtrl = TextEditingController();
  String? _districtFilter;
  String? _habitatFilter;
  String _dateFilter = 'all'; // all | today | week | month
  bool _verifiedOnly = false;

  static const List<String> _habitatOptions = <String>[
    'বন', 'জলাশয়', 'নদী', 'ঘাসজমি', 'পাহাড়', 'বাগান', 'কৃষিজমি', 'অন্যান্য',
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyLocalFilters);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyLocalFilters);
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.trim().isNotEmpty ||
      _districtFilter != null ||
      _habitatFilter != null ||
      _dateFilter != 'all' ||
      _verifiedOnly;

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);

    final profile = await _service.fetchContributorProfile();
    final popular = await _service.fetchPopularSpecies();

    final sightings = await _service.fetchPublicSightings(limit: 120);
    final hasContent = sightings.isNotEmpty ||
        await _service.hasAnyPublishedSightings();

    if (!mounted) return;
    setState(() {
      _myDistrict = (profile?.district ?? '').trim().isEmpty
          ? null
          : profile!.district!.trim();
      _popularSpecies = popular;
      _all = sightings;
      _hasAnyContent = hasContent;
      _isLoading = false;
    });
    _applyLocalFilters();

    final targetId = widget.initialSightingId;
    if (targetId != null && targetId.isNotEmpty) {
      final matches =
          sightings.where((s) => s.id == targetId).toList(growable: false);
      if (matches.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openDetail(matches.first);
        });
      }
    }
  }

  DateTime? _dateFromFilter() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return now.subtract(const Duration(days: 30));
      default:
        return null;
    }
  }

  void _applyLocalFilters() {
    if (!mounted) return;
    final query = _searchCtrl.text.trim().toLowerCase();
    final from = _dateFromFilter();

    setState(() {
      _filtered = _all.where((s) {
        if (query.isNotEmpty) {
          final haystack = <String>[
            s.commonName,
            s.bengaliName ?? '',
            s.scientificName ?? '',
          ].join(' ').toLowerCase();
          if (!haystack.contains(query)) return false;
        }
        if (_districtFilter != null && s.district != _districtFilter) return false;
        if (_habitatFilter != null && s.habitat != _habitatFilter) return false;
        if (_verifiedOnly && !s.hasVerifiedIdentification) return false;
        if (from != null) {
          final observed = s.observedAt;
          if (observed == null || observed.isBefore(from)) return false;
        }
        return true;
      }).toList();
    });
  }

  List<PublicWildlifeSighting> get _todaySightings {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _all
        .where((s) => s.observedAt != null && !s.observedAt!.isBefore(start))
        .toList();
  }

  List<PublicWildlifeSighting> get _weekSightings {
    final from = DateTime.now().subtract(const Duration(days: 7));
    return _all
        .where((s) => s.observedAt != null && s.observedAt!.isAfter(from))
        .toList();
  }

  List<PublicWildlifeSighting> get _featuredSightings =>
      _all.where((s) => s.featured).toList();

  List<PublicWildlifeSighting> get _myAreaSightings {
    final district = _myDistrict;
    if (district == null) return const <PublicWildlifeSighting>[];
    return _all
        .where((s) =>
            (s.district ?? '').trim().toLowerCase() == district.toLowerCase())
        .toList();
  }

  void _openDetail(PublicWildlifeSighting sighting) {
    SoundService.playButtonSound();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SightingDetailScreen(sighting: sighting),
    ));
  }

  void _openSubmission() {
    SoundService.playButtonSound();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SightingSubmissionScreen()))
        .then((_) => _load());
  }

  void _openContributorArea() {
    SoundService.playButtonSound();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ContributorProfileScreen()))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CitizenSciencePalette.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF10251A), Color(0xFF0D1410)],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: CitizenSciencePalette.accent,
            backgroundColor: CitizenSciencePalette.surface,
            onRefresh: _load,
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: CitizenSciencePalette.accent))
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.only(bottom: 40),
                    children: _buildContent(),
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    final widgets = <Widget>[
      _buildHeader(),
      _buildHeroCard(),
    ];

    if (_popularSpecies.isNotEmpty) {
      widgets.add(_buildPopularSpecies());
    }

    widgets.add(_buildFilterBar());
    widgets.add(const SizedBox(height: 4));

    if (_filtered.isEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: CitizenScienceEmptyState(
          icon: _hasAnyContent ? Icons.filter_alt_off_outlined : Icons.forest_outlined,
          titleBn: _hasAnyContent
              ? 'এই ছাঁকনিতে কোনো দর্শন পাওয়া যায়নি'
              : 'এখনও কোনো দর্শন প্রকাশিত হয়নি',
          subtitleBn: _hasAnyContent
              ? 'অন্য তারিখ, জেলা বা প্রজাতি দিয়ে খুঁজে দেখুন — অথবা নিজের একটি দর্শন জানান।'
              : 'প্রথম নাগরিক বিজ্ঞানী হোন — আপনার দেখা বন্যপ্রাণের ছবি ও বিবরণ পাঠান। সম্পাদক যাচাই করে প্রকাশ করবেন।',
          actionLabel: 'দর্শন রিপোর্ট করুন',
          onAction: _openSubmission,
        ),
      ));
    } else {
      widgets.addAll(_buildCuratedSections());
      widgets.add(_buildDatabaseList());
    }

    widgets.add(const SizedBox(height: 20));
    widgets.add(_buildPrivacyNote());
    return widgets;
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () {
              SoundService.playButtonSound();
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'নাগরিক বিজ্ঞান',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2),
                ),
                SizedBox(height: 2),
                Text(
                  'বন্যপ্রাণ দর্শন — আপনার চোখে দেখা প্রকৃতি',
                  style:
                      TextStyle(color: CitizenSciencePalette.accentSoft, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'আমার দর্শন ও বার্তা',
            onPressed: _openContributorArea,
            icon: const Icon(Icons.person_pin_circle_outlined,
                color: CitizenSciencePalette.accentSoft),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF1B3322), Color(0xFF14251A)],
          ),
          border: Border.all(
              color: CitizenSciencePalette.accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/images/gallery.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.travel_explore_rounded,
                        color: CitizenSciencePalette.accent,
                        size: 30)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'আপনি কী দেখেছেন?',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'পাখি, প্রজাপতি, স্তন্যপায়ী, সরীসৃপ বা গাছ — যা-ই দেখুন, ছবি ও বিবরণ পাঠান। '
              'বৈজ্ঞানিক নাম না জানলেও চলবে; সম্পাদক ও বিশেষজ্ঞরা যাচাই করে প্রজাতি নিশ্চিত করবেন।',
              style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.55),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CitizenSciencePalette.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _openSubmission,
                icon: const Icon(Icons.add_a_photo_outlined, size: 19),
                label: const Text('📸 দর্শন রিপোর্ট করুন',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularSpecies() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(Icons.trending_up_rounded, 'জনপ্রিয় প্রজাতি',
              subtitle: 'গত ৯০ দিনের প্রকাশিত দর্শন'),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: _popularSpecies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _popularSpecies[index];
                final species = (item['species'] ?? '').toString();
                final count = (item['sighting_count'] as num?)?.toInt() ?? 0;
                return KeyboardPressEffect(
                  onTap: () {
                    SoundService.playButtonSound();
                    _searchCtrl.text = species;
                    _applyLocalFilters();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: CitizenSciencePalette.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: CitizenSciencePalette.accent.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_florist_rounded,
                            size: 13, color: CitizenSciencePalette.accent),
                        const SizedBox(width: 6),
                        Text(species,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12.5)),
                        const SizedBox(width: 6),
                        Text('($count)',
                            style: const TextStyle(
                                color: CitizenSciencePalette.accentSoft,
                                fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CitizenSciencePalette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSection(
    String title,
    List<PublicWildlifeSighting> items, {
    IconData icon = Icons.landscape_rounded,
    String? subtitle,
    bool compact = true,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(icon, title, subtitle: subtitle),
        SizedBox(
          height: compact ? 268 : 330,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: compact ? 214 : 258,
              child: PublicSightingCard(
                sighting: items[index],
                compact: compact,
                onTap: () => _openDetail(items[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCuratedSections() {
    if (_hasActiveFilters) {
      return <Widget>[
        _buildSectionTitle(Icons.search_rounded, 'অনুসন্ধানের ফলাফল',
            subtitle: '${_filtered.length}টি দর্শন পাওয়া গেছে'),
      ];
    }

    return <Widget>[
      _buildHorizontalSection('আজকের দর্শন', _todaySightings,
          icon: Icons.wb_twilight_rounded, subtitle: 'আজ চিহ্নিত পর্যবেক্ষণ'),
      _buildHorizontalSection('সম্পাদক নির্বাচিত দর্শন', _featuredSightings,
          icon: Icons.star_rounded, subtitle: 'সম্পাদকমণ্ডলীর বাছাই'),
      _buildHorizontalSection('এই সপ্তাহের দর্শন', _weekSightings,
          icon: Icons.calendar_view_week_rounded, subtitle: 'সর্বশেষ সাত দিন'),
      if (_myDistrict != null)
        _buildHorizontalSection('আপনার এলাকার দর্শন', _myAreaSightings,
            icon: Icons.my_location_rounded,
            subtitle: '${_myDistrict!}-এর কাছাকাছি'),
    ];
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'প্রজাতির নাম খুঁজুন (বাংলা বা ইংরেজি)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: CitizenSciencePalette.accentSoft, size: 19),
              suffixIcon: _searchCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white38, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _applyLocalFilters();
                      },
                    ),
              filled: true,
              fillColor: CitizenSciencePalette.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: CitizenSciencePalette.accent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  label: 'সব',
                  selected: !_hasActiveFilters,
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() {
                      _dateFilter = 'all';
                      _verifiedOnly = false;
                      _districtFilter = null;
                      _habitatFilter = null;
                    });
                    _applyLocalFilters();
                  },
                ),
                _filterChip(
                  label: 'আজ',
                  selected: _dateFilter == 'today',
                  onTap: () {
                    setState(() => _dateFilter = 'today');
                    _applyLocalFilters();
                  },
                ),
                _filterChip(
                  label: 'এই সপ্তাহ',
                  selected: _dateFilter == 'week',
                  onTap: () {
                    setState(() => _dateFilter = 'week');
                    _applyLocalFilters();
                  },
                ),
                _filterChip(
                  label: 'এই মাস',
                  selected: _dateFilter == 'month',
                  onTap: () {
                    setState(() => _dateFilter = 'month');
                    _applyLocalFilters();
                  },
                ),
                _filterChip(
                  label: '✔ যাচাইকৃত',
                  selected: _verifiedOnly,
                  onTap: () {
                    setState(() => _verifiedOnly = !_verifiedOnly);
                    _applyLocalFilters();
                  },
                ),
                ..._buildDistrictChips(),
                ..._habitatOptions.take(4).map((h) => _filterChip(
                      label: h,
                      selected: _habitatFilter == h,
                      onTap: () {
                        setState(() =>
                            _habitatFilter = _habitatFilter == h ? null : h);
                        _applyLocalFilters();
                      },
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDistrictChips() {
    final districts = <String>{};
    for (final s in _all) {
      final d = (s.district ?? '').trim();
      if (d.isNotEmpty) districts.add(d);
    }
    final list = districts.toList()..sort();
    return list.take(6).map((d) {
      return _filterChip(
        label: d,
        selected: _districtFilter == d,
        onTap: () {
          setState(() => _districtFilter = _districtFilter == d ? null : d);
          _applyLocalFilters();
        },
      );
    }).toList();
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: CitizenSciencePalette.accent,
        backgroundColor: CitizenSciencePalette.surface,
        labelStyle: TextStyle(
          color: selected ? Colors.black : Colors.white70,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: selected
                  ? CitizenSciencePalette.accent
                  : Colors.white.withValues(alpha: 0.12)),
        ),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildDatabaseList() {
    final items = _hasActiveFilters ? _filtered : _all;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(Icons.public_rounded, 'সাম্প্রতিক দর্শন',
            subtitle: 'নাগরিক বিজ্ঞান ডেটাবেস — ${items.length}টি প্রকাশিত দর্শন'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : (constraints.maxWidth >= 620 ? 2 : 1);
              const spacing = 14.0;
              final width =
                  (constraints.maxWidth - (columns - 1) * spacing) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: 16,
                children: items
                    .map((s) => SizedBox(
                          width: width,
                          child: PublicSightingCard(
                            sighting: s,
                            compact: columns > 1,
                            onTap: () => _openDetail(s),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CitizenSciencePalette.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.privacy_tip_outlined,
                color: CitizenSciencePalette.earth, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'গোপনীয়তা রক্ষা: সঠিক জিপিএস অবস্থান কখনও প্রকাশ্যে দেখানো হয় না। '
                'সাধারণ দর্শনে জেলা-পর্যন্ত এবং সংবেদনশীল বা বিলুপ্তপ্রায় প্রজাতিতে আরও বিস্তৃতভাবে '
                'অবস্থান লুকানো হয়। বাসা, গর্ত বা প্রজননস্থলের স্থান কখনও প্রকাশ করা হয় না।',
                style: TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
