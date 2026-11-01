import 'dart:convert';

import '../core/config.dart';

class DailyWildlifeFeature {
  final String id;
  final DateTime featureDate;
  final String status;
  final String title;
  final String? titleBn;
  final String? commonName;
  final String? scientificName;
  final String? bengaliName;
  final String? speciesDescription;
  final String? descriptionBn;
  final String? habitat;
  final String? distribution;
  final String? diet;
  final String? behaviour;
  final String? ecologicalRole;
  final String? conservationStatus;
  final String? iucnStatus;
  final String? interestingFacts;
  final String? didYouKnow;
  final String? sourceUrls;
  final String? sourceAttributions;
  final String? originalImageUrl;
  final String? watercolourImageUrl;
  final String? watercolourPrompt;
  final String? imageGenerationStatus;
  final String? imageGenerationProvider;
  final String? imageGenerationError;
  final String? imageProvenance;
  final String? editorNotes;
  final String? animalType;
  final String? selectionReason;
  final String? regionalSignificance;
  final String? economicImportance;
  final String? habitatThreat;
  final String? educationalValue;
  final int sortOrder;
  final String? audioUrl;
  final String? audioProvider;
  final String? audioId;
  final String? audioRecordist;
  final String? audioLicense;
  final String? audioAttribution;
  final bool audioAvailable;
  final bool editorOverride;
  final bool isFeatured;
  final bool isPublished;
  final DateTime? scheduledPublishAt;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  DailyWildlifeFeature({
    required this.id,
    required this.featureDate,
    required this.status,
    required this.title,
    this.titleBn,
    this.commonName,
    this.scientificName,
    this.bengaliName,
    this.speciesDescription,
    this.descriptionBn,
    this.habitat,
    this.distribution,
    this.diet,
    this.behaviour,
    this.ecologicalRole,
    this.conservationStatus,
    this.iucnStatus,
    this.interestingFacts,
    this.didYouKnow,
    this.sourceUrls,
    this.sourceAttributions,
    this.originalImageUrl,
    this.watercolourImageUrl,
    this.watercolourPrompt,
    this.imageGenerationStatus,
    this.imageGenerationProvider,
    this.imageGenerationError,
    this.imageProvenance,
    this.editorNotes,
    this.animalType,
    this.selectionReason,
    this.regionalSignificance,
    this.economicImportance,
    this.habitatThreat,
    this.educationalValue,
    this.sortOrder = 0,
    this.audioUrl,
    this.audioProvider,
    this.audioId,
    this.audioRecordist,
    this.audioLicense,
    this.audioAttribution,
    this.audioAvailable = false,
    this.editorOverride = false,
    this.isFeatured = false,
    this.isPublished = false,
    this.scheduledPublishAt,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  /// Stable record and source-specific cache key to avoid cross-contamination.
  String get imageCacheKey {
    final srcHash =
        (displayImageUrl ?? originalImageUrl ?? watercolourImageUrl ?? '')
            .hashCode;
    return 'daily_wildlife_${id}_$srcHash';
  }

  /// Alias for the oil painting derivative / watercolour feature card image.
  String? get oilPaintingImageUrl => watercolourImageUrl;

  String? get processedFeatureImageUrl => watercolourImageUrl;

  /// Detects a likely cross-species mismatch for ANY scheduled species.
  /// Mirrors backend `isImageProvenanceValidForSpecies`: only flags when the
  /// stored FILE text itself carries latin taxonomy (e.g. Panthera_tigris)
  /// yet names neither the scheduled genus nor epithet. Numeric iNat photo
  /// IDs (…/348836961/square.jpg) or Supabase storage paths
  /// (daily_sources/<uuid>.jpg) must NEVER count as a mismatch — they carry
  /// no taxon words. Provider words (inaturalist/ebird/wikimedia) alone are
  /// not evidence either.
  bool get hasCrossSpeciesMismatch {
    final sciLower = (scientificName ?? '').toLowerCase().trim();
    if (sciLower.isEmpty) return false;

    final parts = sciLower.split(RegExp(r'\s+'));
    final genus = parts.isNotEmpty ? parts[0] : '';
    final epithet = parts.length > 1 ? parts[1] : '';
    if (genus.length <= 3 && epithet.length <= 3) return false;

    // Only the actual file/source URLs carry taxon evidence — never the raw
    // provenance JSON blob (it always contains provider words like
    // "inaturalist", which previously forced a false positive for every
    // numeric-ID photo).
    final fileText = _provenanceFileText().toLowerCase();
    final mentionsGenus = genus.length > 3 && fileText.contains(genus);
    final mentionsEpithet = epithet.length > 3 && fileText.contains(epithet);
    if (mentionsGenus || mentionsEpithet) return false;

    // Backend parity: enforce only when the filename carries latin taxonomy
    // (genus_epithet, genus epithet). Generic numeric/storage filenames pass.
    // NOTE: Supabase storage paths (daily_sources/uuid.jpg) and S3 numeric
    // IDs always contain underscores/numbers — exclude them explicitly so a
    // valid iNat photo like .../348836961/square.jpg is never flagged.
    final lowerFile = fileText.toLowerCase();
    final isStorageOrNumericPath = lowerFile.contains('daily_sources') ||
        lowerFile.contains('wildlife_gallery') ||
        lowerFile.contains('supabase') ||
        RegExp(r'/\d+/(square|small|thumb|medium|large|original)\.').hasMatch(lowerFile);
    if (isStorageOrNumericPath) return false;
    final carriesLatinTaxonomy =
        RegExp(r'[a-z]{4,}_[a-z]{4,}').hasMatch(fileText) ||
        (genus.length > 3 &&
            epithet.length > 3 &&
            fileText.contains('$genus $epithet')) ||
        (genus.length > 3 &&
            epithet.length > 3 &&
            fileText.contains('${genus}_$epithet'));
    return carriesLatinTaxonomy;
  }

  /// Verified original source photo that passed the species/image audit.
  /// Returns null for failed/mismatched art, so the UI can fall back to the
  /// oil derivative or a placeholder instead of showing the wrong species.
  String? get verifiedOriginalImageUrl {
    final raw = (originalImageUrl ?? '').trim();
    if (raw.isEmpty) return null;
    if (hasCrossSpeciesMismatch) return null;
    final err = (imageGenerationError ?? '').toLowerCase();
    if (err.contains('mismatch') ||
        err.contains('cross-species') ||
        err.contains('provenance failed')) {
      return null;
    }
    final prov = (imageProvenance ?? '').toLowerCase();
    if (prov.contains('mismatch') || prov.contains('invalid')) return null;
    return upgradeImageUrl(raw);
  }

  /// File/source-URL text used for the mismatch gate. Parses the provenance
  /// JSON and keeps ONLY `source_url` + `original_image_url` (+ the stored
  /// URL + source_urls) — never provider/creator/license words.
  String _provenanceFileText() {
    final parts = <String>[];
    if ((originalImageUrl ?? '').trim().isNotEmpty) {
      parts.add(originalImageUrl!.trim());
    }
    final prov = _provenanceMap();
    for (final key in ['source_url', 'original_image_url']) {
      final v = prov[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) parts.add(v);
    }
    // Nested `image` object inside source_attributions-style payloads.
    final nested = prov['image'];
    if (nested is Map) {
      for (final key in ['source_url', 'original_image_url']) {
        final v = nested[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) parts.add(v);
      }
    }
    if ((sourceUrls ?? '').trim().isNotEmpty) parts.add(sourceUrls!.trim());
    return parts.join(' ');
  }

  /// Parsed provenance JSON ({} when absent/unparseable).
  Map<String, dynamic> _provenanceMap() {
    final raw = (imageProvenance ?? '').trim();
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  /// Best display URL for the source photo. Prefers the full-size provenance
  /// `original_image_url` over the stored row URL (the backend uploads the
  /// iNat `large_url` into storage but your Pygmy Hog row points at the
  /// 75px `square.jpg` thumbnail — that is the editorial pixelation).
  /// Also upgrades any lingering iNat `square/small/thumb/medium` URLs to
  /// `large`/`original`.
  String? get displayImageUrl => upgradeImageUrl(
        _bestSourceUrl() ?? verifiedOriginalImageUrl,
      );

  String? _bestSourceUrl() {
    final prov = _provenanceMap();
    final direct = prov['original_image_url']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final nested = prov['image'];
    if (nested is Map) {
      final v = nested['original_image_url']?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// Upgrades known thumbnail-size image URLs to their full-size variant.
  /// iNaturalist pattern: https://inaturalist-open-data.s3.amazonaws.com/
  /// photos/348836961/square.jpg → .../large.jpg (or original.jpg).
  static String? upgradeImageUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    // iNaturalist size suffix swap.
    final inatSized = RegExp(r'/square\.(\w+)|/small\.(\w+)|/thumb\.(\w+)|/medium\.(\w+)\s*$');
    if (inatSized.hasMatch(trimmed)) {
      final ext = inatSized.firstMatch(trimmed)!.group(0)!.split('.').last;
      return trimmed.replaceAll(inatSized, '/large.$ext');
    }
    return trimmed;
  }

  /// Human-readable photo credit, e.g. "© kalyanvarma, CC BY — iNaturalist".
  /// Never dumps raw JSON (your screenshot's `Image Provenance: {...}` block).
  String? get formattedImageCredit {
    final prov = _provenanceMap();
    Map<String, dynamic> img = prov;
    if (prov['image'] is Map) {
      img = Map<String, dynamic>.from(prov['image'] as Map);
    }
    final attribution = (img['attribution'] ?? '').toString().trim();
    if (attribution.isNotEmpty &&
        !attribution.startsWith('{') &&
        attribution.length < 300) {
      return attribution;
    }
    final creator = (img['creator'] ?? '').toString().trim();
    final license = (img['license'] ?? '').toString().trim();
    final provider = (img['provider'] ?? '').toString().trim();
    final bits = <String>[];
    if (creator.isNotEmpty) bits.add('© $creator');
    if (license.isNotEmpty) bits.add(license);
    if (provider.isNotEmpty) bits.add(provider);
    if (bits.isNotEmpty) return bits.join(', ');
    return null;
  }

  /// Human-readable source references (eBird / iNat / Xeno-canto / photo URL),
  /// parsed from the JSON blob the backend stores in `source_attributions`.
  /// Falls back to `source_urls` CSV. Returns [] when nothing parseable.
  List<String> get formattedSourceRefs {
    final out = <String>[];
    final raw = (sourceAttributions ?? '').trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final m = Map<String, dynamic>.from(decoded);
          final ebird = m['ebird'];
          if (ebird is Map && (ebird['source_id'] ?? '').toString().isNotEmpty) {
            out.add('eBird: ${ebird['source_id']}');
          }
          final inat = m['inaturalist'];
          if (inat is Map && (inat['source_id'] ?? '').toString().isNotEmpty) {
            out.add('iNaturalist taxon ${inat['source_id']}');
          }
          final audio = m['audio'];
          if (audio is Map && (audio['url'] ?? '').toString().isNotEmpty) {
            out.add('Audio: ${audio['url']}');
          }
        }
      } catch (_) {}
    }
    if (out.isEmpty && (sourceUrls ?? '').trim().isNotEmpty) {
      out.addAll(
        sourceUrls!
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }
    final prov = _provenanceMap();
    final photoUrl = (prov['source_url'] ?? '').toString().trim();
    if (photoUrl.isNotEmpty && !out.contains(photoUrl)) out.add(photoUrl);
    return out;
  }

  static String? _resolveUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('/storage/v1/')) {
      return '$supabaseUrl$url';
    }
    return url;
  }

  factory DailyWildlifeFeature.fromJson(Map<String, dynamic> json) {
    return DailyWildlifeFeature(
      id: json['id'].toString(),
      featureDate: DateTime.parse(json['feature_date'].toString()),
      status: json['status']?.toString() ?? 'draft',
      title: json['title'].toString(),
      titleBn: json['title_bn']?.toString(),
      commonName: json['common_name']?.toString(),
      scientificName: json['scientific_name']?.toString(),
      bengaliName: json['bengali_name']?.toString(),
      speciesDescription: json['species_description']?.toString(),
      descriptionBn: json['description_bn']?.toString(),
      habitat: json['habitat']?.toString(),
      distribution: json['distribution']?.toString(),
      diet: json['diet']?.toString(),
      behaviour: json['behaviour']?.toString(),
      ecologicalRole: json['ecological_role']?.toString(),
      conservationStatus: json['conservation_status']?.toString(),
      iucnStatus: json['iucn_status']?.toString(),
      interestingFacts: json['interesting_facts']?.toString(),
      didYouKnow: json['did_you_know']?.toString(),
      sourceUrls: json['source_urls']?.toString(),
      sourceAttributions: json['source_attributions']?.toString(),
      originalImageUrl: _resolveUrl(json['original_image_url']?.toString()),
      watercolourImageUrl: _resolveUrl(json['watercolour_image_url']?.toString()),
      watercolourPrompt: json['watercolour_prompt']?.toString(),
      imageGenerationStatus: json['image_generation_status']?.toString(),
      imageGenerationProvider: json['image_generation_provider']?.toString(),
      imageGenerationError: json['image_generation_error']?.toString(),
      imageProvenance: json['image_provenance']?.toString(),
      editorNotes: json['editor_notes']?.toString(),
      animalType: json['animal_type']?.toString(),
      selectionReason: json['selection_reason']?.toString(),
      regionalSignificance: json['regional_significance']?.toString(),
      economicImportance: json['economic_importance']?.toString(),
      habitatThreat: json['habitat_threat']?.toString(),
      educationalValue: json['educational_value']?.toString(),
      sortOrder: json['sort_order'] != null ? int.parse(json['sort_order'].toString()) : 0,
      audioUrl: _resolveUrl(json['audio_url']?.toString()),
      audioProvider: json['audio_provider']?.toString(),
      audioId: json['audio_id']?.toString(),
      audioRecordist: json['audio_recordist']?.toString(),
      audioLicense: json['audio_license']?.toString(),
      audioAttribution: json['audio_attribution']?.toString(),
      audioAvailable: json['audio_available'] == true ||
          (json['audio_url'] != null &&
              json['audio_url'].toString().trim().isNotEmpty),
      editorOverride: json['editor_override'] == true,
      isFeatured: json['is_featured'] == true,
      isPublished: json['is_published'] == true,
      scheduledPublishAt: json['scheduled_publish_at'] != null ? DateTime.parse(json['scheduled_publish_at'].toString()) : null,
      publishedAt: json['published_at'] != null ? DateTime.parse(json['published_at'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : null,
      createdBy: json['created_by']?.toString(),
      updatedBy: json['updated_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'feature_date': featureDate.toIso8601String().split('T')[0],
      'status': status,
      'title': title,
      if (titleBn != null) 'title_bn': titleBn,
      if (commonName != null) 'common_name': commonName,
      if (scientificName != null) 'scientific_name': scientificName,
      if (bengaliName != null) 'bengali_name': bengaliName,
      if (speciesDescription != null) 'species_description': speciesDescription,
      if (descriptionBn != null) 'description_bn': descriptionBn,
      if (habitat != null) 'habitat': habitat,
      if (distribution != null) 'distribution': distribution,
      if (diet != null) 'diet': diet,
      if (behaviour != null) 'behaviour': behaviour,
      if (ecologicalRole != null) 'ecological_role': ecologicalRole,
      if (conservationStatus != null) 'conservation_status': conservationStatus,
      if (iucnStatus != null) 'iucn_status': iucnStatus,
      if (interestingFacts != null) 'interesting_facts': interestingFacts,
      if (didYouKnow != null) 'did_you_know': didYouKnow,
      if (sourceUrls != null) 'source_urls': sourceUrls,
      if (sourceAttributions != null) 'source_attributions': sourceAttributions,
      if (originalImageUrl != null) 'original_image_url': originalImageUrl,
      if (watercolourImageUrl != null) 'watercolour_image_url': watercolourImageUrl,
      if (watercolourPrompt != null) 'watercolour_prompt': watercolourPrompt,
      if (imageGenerationStatus != null) 'image_generation_status': imageGenerationStatus,
      if (imageGenerationProvider != null) 'image_generation_provider': imageGenerationProvider,
      if (imageGenerationError != null) 'image_generation_error': imageGenerationError,
      if (imageProvenance != null) 'image_provenance': imageProvenance,
      if (editorNotes != null) 'editor_notes': editorNotes,
      if (animalType != null) 'animal_type': animalType,
      if (selectionReason != null) 'selection_reason': selectionReason,
      if (regionalSignificance != null) 'regional_significance': regionalSignificance,
      if (economicImportance != null) 'economic_importance': economicImportance,
      if (habitatThreat != null) 'habitat_threat': habitatThreat,
      if (educationalValue != null) 'educational_value': educationalValue,
      'sort_order': sortOrder,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (audioProvider != null) 'audio_provider': audioProvider,
      if (audioId != null) 'audio_id': audioId,
      if (audioRecordist != null) 'audio_recordist': audioRecordist,
      if (audioLicense != null) 'audio_license': audioLicense,
      if (audioAttribution != null) 'audio_attribution': audioAttribution,
      'editor_override': editorOverride,
      'is_featured': isFeatured,
      'is_published': isPublished,
      if (scheduledPublishAt != null) 'scheduled_publish_at': scheduledPublishAt!.toIso8601String(),
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
    };
  }
}
