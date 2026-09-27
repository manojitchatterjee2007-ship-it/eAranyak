import 'package:flutter/material.dart';

import '../models/content_protection_models.dart';
import '../models/wildlife_sighting.dart';
import '../services/citizen_science_service.dart';
import '../services/sound_service.dart';
import '../widgets/citizen_science/sighting_card.dart';
import '../widgets/protected_content.dart';
import '../widgets/protected_image.dart';
import '../widgets/protected_watermark.dart';
import '../widgets/scientific_text.dart';

/// Protected public detail view for a published sighting.
///
/// Imagery is rendered through the same protection stack as the Wildlife
/// Gallery: `ProtectedContent` (capture blocking + session watermark) and
/// `ProtectedImage` (120-second signed URLs on the private bucket).
class SightingDetailScreen extends StatefulWidget {
  final PublicWildlifeSighting sighting;

  const SightingDetailScreen({super.key, required this.sighting});

  @override
  State<SightingDetailScreen> createState() => _SightingDetailScreenState();
}

class _SightingDetailScreenState extends State<SightingDetailScreen> {
  final CitizenScienceService _service = CitizenScienceService();
  int _photoIndex = 0;
  bool _reporting = false;

  PublicWildlifeSighting get _sighting => widget.sighting;

  Future<void> _report() async {
    if (_reporting) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CitizenSciencePalette.surface,
        title: const Text('দর্শনটি রিপোর্ট করুন',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'কারণ লিখুন (যেমন: ভুল প্রজাতি, সন্দেহজনক তথ্য)',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('রিপোর্ট পাঠান',
                style: TextStyle(color: CitizenSciencePalette.accent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _reporting = true);
    try {
      await _service.reportSighting(_sighting.id, reason: reasonCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ধন্যবাদ — সম্পাদকমণ্ডলী বিষয়টি পর্যালোচনা করবেন।'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('রিপোর্ট পাঠানো যায়নি: $e')));
      }
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _sighting.photos;
    final cover =
        photos.isEmpty ? null : photos[_photoIndex.clamp(0, photos.length - 1)];

    return Scaffold(
      backgroundColor: CitizenSciencePalette.background,
      appBar: AppBar(
        backgroundColor: CitizenSciencePalette.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            SoundService.playButtonSound();
            Navigator.of(context).maybePop();
          },
        ),
        title: const Text('দর্শনের বিবরণ',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'রিপোর্ট করুন',
            onPressed: _reporting ? null : _report,
            icon: const Icon(Icons.flag_outlined, color: Colors.white54),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (cover != null)
            ProtectedContent(
              userIdentity: 'CITIZEN-SCIENCE-VIEWER',
              scope: ContentProtectionScope.gallery,
              contentId: _sighting.id,
              watermarkOpacity: 0.07,
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: ProtectedImage(
                  bucket: 'citizen_sightings',
                  storagePath: cover.storagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          if (photos.length > 1)
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => setState(() => _photoIndex = index),
                  child: Container(
                    width: 74,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: index == _photoIndex
                            ? CitizenSciencePalette.accent
                            : Colors.white12,
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ProtectedImage(
                      bucket: 'citizen_sightings',
                      storagePath: photos[index].storagePath,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScientificText(
                  _sighting.displaySpeciesName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
                if ((_sighting.scientificName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ScientificText(
                    _sighting.scientificName!,
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                        fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SightingVerificationChip(
                        verificationStatus: _sighting.verificationStatus),
                    if (_sighting.featured)
                      const SightingStatusChip(
                        status: 'published',
                        label: 'সম্পাদক নির্বাচিত',
                        icon: Icons.star_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _infoRow(Icons.place_outlined, 'প্রকাশ্য অবস্থান',
                    _sighting.displayLocation),
                _infoRow(Icons.event_outlined, 'দর্শনের তারিখ',
                    PublicSightingCard.formatBengaliDate(_sighting.observedAt)),
                if ((_sighting.observedTime ?? '').isNotEmpty)
                  _infoRow(Icons.schedule_outlined, 'আনুমানিক সময়',
                      _sighting.observedTime!),
                if ((_sighting.habitat ?? '').isNotEmpty)
                  _infoRow(Icons.forest_outlined, 'পরিবেশ', _sighting.habitat!),
                if (_sighting.individualCount != null)
                  _infoRow(Icons.numbers_rounded, 'সংখ্যা',
                      '${_sighting.individualCount}'),
                if ((_sighting.behaviour ?? '').isNotEmpty)
                  _infoRow(Icons.visibility_outlined, 'আচরণ', _sighting.behaviour!),
                if ((_sighting.contributorName ?? '').isNotEmpty)
                  _infoRow(Icons.person_outline_rounded, 'রিপোর্ট',
                      _sighting.contributorName!),
                if ((_sighting.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('পর্যবেক্ষণের বিবরণ',
                      style: TextStyle(
                          color: CitizenSciencePalette.accentSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_sighting.description!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13.5, height: 1.6)),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CitizenSciencePalette.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: const Text(
                    'এটি একটি নাগরিক বিজ্ঞান দর্শন। প্রজাতি শনাক্তকরণ প্রথমে দর্শনকারীর বর্ণনা; '
                    'সম্পাদকীয় বা বৈজ্ঞানিক যাচাই আলাদাভাবে উপরের ব্যাজে দেখানো হয়। '
                    'সঠিক অবস্থান গোপনীয়তার কারণে প্রকাশ করা হয় না।',
                    style:
                        TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: CitizenSciencePalette.accentSoft),
          const SizedBox(width: 8),
          SizedBox(
            width: 118,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
