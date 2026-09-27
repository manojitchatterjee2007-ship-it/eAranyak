import 'package:flutter/material.dart';

import '../../models/wildlife_sighting.dart';
import '../keyboard_press_effect.dart';
import '../protected_image.dart';
import '../scientific_text.dart';
import '../../services/sound_service.dart';

/// Shared visual language for the Citizen Science module:
/// nature-journal palette, photographic cards and generous whitespace.
class CitizenSciencePalette {
  CitizenSciencePalette._();

  static const Color background = Color(0xFF0D1410);
  static const Color surface = Color(0xFF142419);
  static const Color surfaceAlt = Color(0xFF18221B);
  static const Color accent = Color(0xFF00E676);
  static const Color accentSoft = Color(0xFF81C784);
  static const Color earth = Color(0xFFC8B48A);
  static const Color earthDeep = Color(0xFF8D7A57);
  static const Color danger = Color(0xFFFF7A6B);
}

/// Status pill used across contributor, editorial and public views.
class SightingStatusChip extends StatelessWidget {
  final String status;
  final String label;
  final IconData? icon;

  const SightingStatusChip({
    super.key,
    required this.status,
    required this.label,
    this.icon,
  });

  Color get _color {
    switch (status) {
      case 'published':
        return CitizenSciencePalette.accent;
      case 'approved':
        return const Color(0xFF64B5F6);
      case 'needs_information':
        return CitizenSciencePalette.earth;
      case 'rejected':
        return CitizenSciencePalette.danger;
      case 'archived':
      case 'draft':
        return Colors.white54;
      case 'under_review':
        return const Color(0xFFFFD54F);
      default:
        return CitizenSciencePalette.accentSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: _color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Verification chip — makes the user-identification vs editorial-verification
/// distinction explicit (including clearly labelled AI suggestions).
class SightingVerificationChip extends StatelessWidget {
  final String verificationStatus;

  const SightingVerificationChip({super.key, required this.verificationStatus});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    Color color = CitizenSciencePalette.accentSoft;
    switch (verificationStatus) {
      case 'scientifically_verified':
        icon = Icons.verified_rounded;
        color = CitizenSciencePalette.accent;
        break;
      case 'editor_verified':
        icon = Icons.verified_user_rounded;
        color = const Color(0xFF64B5F6);
        break;
      case 'ai_suggestion':
        icon = Icons.auto_awesome_rounded;
        color = const Color(0xFFFFD54F);
        break;
      case 'unverified':
        icon = Icons.help_outline_rounded;
        color = Colors.white54;
        break;
      default:
        icon = Icons.person_outline_rounded;
    }

    final label = SightingStatusLabels.verification(verificationStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Photographic sighting card used by the public feed and the home entry point.
class PublicSightingCard extends StatelessWidget {
  final PublicWildlifeSighting sighting;
  final VoidCallback? onTap;
  final bool compact;
  final bool showContributor;

  const PublicSightingCard({
    super.key,
    required this.sighting,
    this.onTap,
    this.compact = false,
    this.showContributor = true,
  });

  static const List<String> _months = <String>[
    'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে'
  ];

  static String formatBengaliDate(DateTime? value) {
    if (value == null) return '—';
    return '${value.day} ${_months[value.month - 1]} ${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cover = sighting.coverStoragePath;
    final card = Container(
      decoration: BoxDecoration(
        color: CitizenSciencePalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: compact ? 132 : 190,
            child: cover == null || cover.isEmpty
                ? Container(
                    color: CitizenSciencePalette.surfaceAlt,
                    child: const Center(
                      child: Icon(Icons.photo_camera_back_outlined,
                          color: Colors.white24, size: 34),
                    ),
                  )
                : ProtectedImage(
                    bucket: 'citizen_sightings',
                    storagePath: cover,
                    fit: BoxFit.cover,
                  ),
          ),
          Padding(
            padding:
                EdgeInsets.fromLTRB(14, compact ? 10 : 14, 14, compact ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ScientificText(
                        sighting.displaySpeciesName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 14.5 : 17,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sighting.featured)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.star_rounded,
                            color: CitizenSciencePalette.earth, size: 16),
                      ),
                  ],
                ),
                if ((sighting.scientificName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  ScientificText(
                    sighting.scientificName!,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 13, color: CitizenSciencePalette.accentSoft),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sighting.displayLocation,
                        style: const TextStyle(
                            color: CitizenSciencePalette.accentSoft, fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 13, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      formatBengaliDate(sighting.observedAt),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const Spacer(),
                    Flexible(
                      child: SightingVerificationChip(
                          verificationStatus: sighting.verificationStatus),
                    ),
                  ],
                ),
                if (showContributor &&
                    (sighting.contributorName ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 13, color: Colors.white38),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'রিপোর্ট: ${sighting.contributorName}',
                          style:
                              const TextStyle(color: Colors.white38, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return KeyboardPressEffect(
      onTap: () {
        SoundService.playButtonSound();
        onTap!.call();
      },
      child: card,
    );
  }
}

/// Polished empty state shared by the public feed and contributor screens.
class CitizenScienceEmptyState extends StatelessWidget {
  final IconData icon;
  final String titleBn;
  final String subtitleBn;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CitizenScienceEmptyState({
    super.key,
    this.icon = Icons.travel_explore_rounded,
    required this.titleBn,
    required this.subtitleBn,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: CitizenSciencePalette.surface.withValues(alpha: 0.7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CitizenSciencePalette.accent.withValues(alpha: 0.08),
              border: Border.all(
                  color: CitizenSciencePalette.accent.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: CitizenSciencePalette.accent, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            titleBn,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitleBn,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white60, fontSize: 12.5, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CitizenSciencePalette.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: onAction,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}
