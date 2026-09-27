/// Models for Phase 5 Citizen Science / Wildlife Sightings.
///
/// [WildlifeSighting] mirrors public.wildlife_sightings (owner + editorial view,
/// includes precise coordinates — never rendered publicly).
/// [PublicWildlifeSighting] mirrors the masked public view
/// public.public_wildlife_sightings, which has no coordinate columns at all.
library;

class SightingStatusLabels {
  SightingStatusLabels._();

  static const Map<String, String> bengali = <String, String>{
    'draft': 'খসড়া',
    'submitted': 'জমা দেওয়া হয়েছে',
    'under_review': 'পর্যালোচনাধীন',
    'needs_information': 'আরও তথ্য প্রয়োজন',
    'approved': 'যাচাই হয়েছে',
    'published': 'প্রকাশিত',
    'rejected': 'প্রকাশিত হয়নি',
    'archived': 'সংরক্ষণাগারে',
  };

  static const Map<String, String> verificationBengali = <String, String>{
    'unverified': 'যাচাই হয়নি',
    'user_reported': 'দর্শনকারীর বর্ণনা',
    'ai_suggestion': 'AI প্রস্তাব (যাচাই হয়নি)',
    'editor_verified': 'সম্পাদক যাচাই করেছেন',
    'scientifically_verified': 'বৈজ্ঞানিকভাবে যাচাইকৃত',
  };

  static const Map<String, String> precisionBengali = <String, String>{
    'precise_private': 'সঠিক অবস্থান (গোপন রাখা হবে)',
    'district': 'জেলা পর্যন্ত',
    'region': 'জেলার কাছাকাছি',
    'hidden': 'শুধু রাজ্য',
  };

  static const Map<String, String> sensitivityBengali = <String, String>{
    'normal': 'সাধারণ',
    'elevated': 'সতর্কতা প্রয়োজন',
    'high': 'সংবেদনশীল প্রজাতি',
    'critical': 'অতি সংবেদনশীল (বাসা/প্রজননস্থল)',
  };

  static const Map<String, String> notificationBengali = <String, String>{
    'submission_received': 'জমা গৃহীত',
    'info_requested': 'তথ্য প্রয়োজন',
    'approved': 'যাচাই সম্পূর্ণ',
    'published': 'প্রকাশিত',
    'rejected': 'প্রকাশ হয়নি',
    'archived': 'সংরক্ষণাগারে',
    'editor_note': 'সম্পাদকের নোট',
    'flagged': 'পর্যালোচনার জন্য চিহ্নিত',
  };

  static String status(String? value) =>
      bengali[value ?? ''] ?? (value ?? 'অজানা');

  static String verification(String? value) =>
      verificationBengali[value ?? ''] ?? 'দর্শনকারীর বর্ণনা';

  static String precision(String? value) =>
      precisionBengali[value ?? ''] ?? 'জেলা পর্যন্ত';

  static String sensitivity(String? value) =>
      sensitivityBengali[value ?? ''] ?? 'সাধারণ';

  static String notification(String? value) =>
      notificationBengali[value ?? ''] ?? 'আপডেট';
}

class WildlifeSightingMedia {
  final String id;
  final String sightingId;
  final String mediaType; // photo | audio | video
  final String bucketId;
  final String storagePath;
  final String? mimeType;
  final int? fileSizeBytes;
  final String? caption;
  final int displayOrder;
  final bool isPublic;
  final DateTime? createdAt;

  const WildlifeSightingMedia({
    required this.id,
    required this.sightingId,
    this.mediaType = 'photo',
    this.bucketId = 'citizen_sightings',
    required this.storagePath,
    this.mimeType,
    this.fileSizeBytes,
    this.caption,
    this.displayOrder = 0,
    this.isPublic = false,
    this.createdAt,
  });

  bool get isPhoto => mediaType == 'photo';
  bool get isAudio => mediaType == 'audio';
  bool get isVideo => mediaType == 'video';

  factory WildlifeSightingMedia.fromJson(Map<String, dynamic> json) {
    return WildlifeSightingMedia(
      id: (json['id'] ?? '').toString(),
      sightingId: (json['sighting_id'] ?? '').toString(),
      mediaType: (json['media_type'] ?? 'photo').toString(),
      bucketId: (json['bucket_id'] ?? 'citizen_sightings').toString(),
      storagePath: (json['storage_path'] ?? '').toString(),
      mimeType: json['mime_type']?.toString(),
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
      caption: json['caption']?.toString(),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isPublic: json['is_public'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sighting_id': sightingId,
        'media_type': mediaType,
        'bucket_id': bucketId,
        'storage_path': storagePath,
        if (mimeType != null) 'mime_type': mimeType,
        if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
        if (caption != null) 'caption': caption,
        'display_order': displayOrder,
      };
}

/// Owner / editorial projection (includes private precise coordinates).
class WildlifeSighting {
  final String id;
  final String? userId;
  final String status;
  final DateTime submittedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String commonName;
  final String? bengaliName;
  final String? scientificName;
  final String? description;
  final String? observationNotes;
  final String? iucnStatus;

  final DateTime? observedAt;
  final String? observedTime;
  final String? habitat;
  final int? individualCount;
  final String? behaviour;

  final String? district;
  final String? state;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String locationPrecision;
  final String publicLocationPrecision;
  final String? publicLocationLabel;
  final String sensitivityLevel;
  final String? sensitivitySource;
  final bool breedingSite;

  final String verificationStatus;
  final String? aiSuggestedSpecies;
  final String? aiSuggestionNote;
  final String? editorNotes;
  final String? rejectionReason;
  final String? infoRequestMessage;

  final bool featured;
  final int editorialPriority;
  final bool isPublished;
  final DateTime? publishedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  final String? contributorDisplayName;
  final String contributorPrivacy;

  final bool isFlagged;
  final String? flagReason;
  final String? duplicateOf;

  final List<WildlifeSightingMedia> media;

  const WildlifeSighting({
    required this.id,
    this.userId,
    this.status = 'submitted',
    required this.submittedAt,
    this.createdAt,
    this.updatedAt,
    required this.commonName,
    this.bengaliName,
    this.scientificName,
    this.description,
    this.observationNotes,
    this.iucnStatus,
    this.observedAt,
    this.observedTime,
    this.habitat,
    this.individualCount,
    this.behaviour,
    this.district,
    this.state,
    this.country,
    this.latitude,
    this.longitude,
    this.locationPrecision = 'district',
    this.publicLocationPrecision = 'district',
    this.publicLocationLabel,
    this.sensitivityLevel = 'normal',
    this.sensitivitySource,
    this.breedingSite = false,
    this.verificationStatus = 'user_reported',
    this.aiSuggestedSpecies,
    this.aiSuggestionNote,
    this.editorNotes,
    this.rejectionReason,
    this.infoRequestMessage,
    this.featured = false,
    this.editorialPriority = 10,
    this.isPublished = false,
    this.publishedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.contributorDisplayName,
    this.contributorPrivacy = 'named',
    this.isFlagged = false,
    this.flagReason,
    this.duplicateOf,
    this.media = const <WildlifeSightingMedia>[],
  });

  factory WildlifeSighting.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['wildlife_sighting_media'];
    final media = rawMedia is List
        ? rawMedia
            .whereType<Map>()
            .map((e) => WildlifeSightingMedia.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <WildlifeSightingMedia>[];

    return WildlifeSighting(
      id: (json['id'] ?? '').toString(),
      userId: json['user_id']?.toString(),
      status: (json['status'] ?? 'submitted').toString(),
      submittedAt: _parseDate(json['submitted_at']) ?? DateTime.now(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      commonName: (json['common_name'] ?? '').toString(),
      bengaliName: json['bengali_name']?.toString(),
      scientificName: json['scientific_name']?.toString(),
      description: json['description']?.toString(),
      observationNotes: json['observation_notes']?.toString(),
      iucnStatus: json['iucn_status']?.toString(),
      observedAt: _parseDate(json['observed_at']),
      observedTime: json['observed_time']?.toString(),
      habitat: json['habitat']?.toString(),
      individualCount: (json['individual_count'] as num?)?.toInt(),
      behaviour: json['behaviour']?.toString(),
      district: json['district']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      locationPrecision: (json['location_precision'] ?? 'district').toString(),
      publicLocationPrecision:
          (json['public_location_precision'] ?? 'district').toString(),
      publicLocationLabel: json['public_location_label']?.toString(),
      sensitivityLevel: (json['sensitivity_level'] ?? 'normal').toString(),
      sensitivitySource: json['sensitivity_source']?.toString(),
      breedingSite: json['breeding_site'] == true,
      verificationStatus:
          (json['verification_status'] ?? 'user_reported').toString(),
      aiSuggestedSpecies: json['ai_suggested_species']?.toString(),
      aiSuggestionNote: json['ai_suggestion_note']?.toString(),
      editorNotes: json['editor_notes']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      infoRequestMessage: json['info_request_message']?.toString(),
      featured: json['featured'] == true,
      editorialPriority: (json['editorial_priority'] as num?)?.toInt() ?? 10,
      isPublished: json['is_published'] == true,
      publishedAt: _parseDate(json['published_at']),
      reviewedBy: json['reviewed_by']?.toString(),
      reviewedAt: _parseDate(json['reviewed_at']),
      contributorDisplayName: json['contributor_display_name']?.toString(),
      contributorPrivacy: (json['contributor_privacy'] ?? 'named').toString(),
      isFlagged: json['is_flagged'] == true,
      flagReason: json['flag_reason']?.toString(),
      duplicateOf: json['duplicate_of']?.toString(),
      media: media,
    );
  }

  String get displaySpeciesName {
    final bn = (bengaliName ?? '').trim();
    if (bn.isNotEmpty) return bn;
    return commonName;
  }

  List<WildlifeSightingMedia> get photos =>
      media.where((m) => m.isPhoto).toList()..sort(_byOrder);
  List<WildlifeSightingMedia> get audioClips =>
      media.where((m) => m.isAudio).toList()..sort(_byOrder);
  List<WildlifeSightingMedia> get videoClips =>
      media.where((m) => m.isVideo).toList()..sort(_byOrder);

  String? get coverStoragePath => photos.isEmpty ? null : photos.first.storagePath;

  bool get isEditableByContributor =>
      const <String>['draft', 'submitted', 'needs_information'].contains(status);

  String get statusLabelBn => SightingStatusLabels.status(status);
  String get verificationLabelBn =>
      SightingStatusLabels.verification(verificationStatus);

  /// Two decimal places is plenty for an editor preview — the precise values are
  /// never sent to public screens.
  String get privateCoordinateLabel {
    if (latitude == null || longitude == null) return '—';
    return '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
  }

  static int _byOrder(WildlifeSightingMedia a, WildlifeSightingMedia b) =>
      a.displayOrder.compareTo(b.displayOrder);

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  static double? _parseDouble(dynamic value) =>
      value == null ? null : double.tryParse(value.toString());
}

/// Masked public projection (public.public_wildlife_sightings).
/// Contains no coordinates and no private/editorial fields by construction.
class PublicWildlifeSighting {
  final String id;
  final String commonName;
  final String? bengaliName;
  final String? scientificName;
  final String? description;
  final DateTime? observedAt;
  final String? observedTime;
  final String? habitat;
  final int? individualCount;
  final String? behaviour;
  final String? iucnStatus;
  final String? district;
  final String? state;
  final String? country;
  final String? publicLocationLabel;
  final String publicLocationPrecision;
  final String sensitivityLevel;
  final String verificationStatus;
  final bool featured;
  final int editorialPriority;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final String? contributorName;
  final bool contributorPublic;
  final List<WildlifeSightingMedia> media;

  const PublicWildlifeSighting({
    required this.id,
    required this.commonName,
    this.bengaliName,
    this.scientificName,
    this.description,
    this.observedAt,
    this.observedTime,
    this.habitat,
    this.individualCount,
    this.behaviour,
    this.iucnStatus,
    this.district,
    this.state,
    this.country,
    this.publicLocationLabel,
    this.publicLocationPrecision = 'district',
    this.sensitivityLevel = 'normal',
    this.verificationStatus = 'user_reported',
    this.featured = false,
    this.editorialPriority = 10,
    this.publishedAt,
    this.createdAt,
    this.contributorName,
    this.contributorPublic = true,
    this.media = const <WildlifeSightingMedia>[],
  });

  factory PublicWildlifeSighting.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['public_sighting_media'];
    final media = rawMedia is List
        ? rawMedia
            .whereType<Map>()
            .map((e) => WildlifeSightingMedia.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <WildlifeSightingMedia>[];

    return PublicWildlifeSighting(
      id: (json['id'] ?? '').toString(),
      commonName: (json['common_name'] ?? '').toString(),
      bengaliName: json['bengali_name']?.toString(),
      scientificName: json['scientific_name']?.toString(),
      description: json['description']?.toString(),
      observedAt: _parseDate(json['observed_at']),
      observedTime: json['observed_time']?.toString(),
      habitat: json['habitat']?.toString(),
      individualCount: (json['individual_count'] as num?)?.toInt(),
      behaviour: json['behaviour']?.toString(),
      iucnStatus: json['iucn_status']?.toString(),
      district: json['district']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString(),
      publicLocationLabel: json['public_location_label']?.toString(),
      publicLocationPrecision:
          (json['public_location_precision'] ?? 'district').toString(),
      sensitivityLevel: (json['sensitivity_level'] ?? 'normal').toString(),
      verificationStatus:
          (json['verification_status'] ?? 'user_reported').toString(),
      featured: json['featured'] == true,
      editorialPriority: (json['editorial_priority'] as num?)?.toInt() ?? 10,
      publishedAt: _parseDate(json['published_at']),
      createdAt: _parseDate(json['created_at']),
      contributorName: json['contributor_name']?.toString(),
      contributorPublic: json['contributor_public'] != false,
      media: media,
    );
  }

  String get displaySpeciesName {
    final bn = (bengaliName ?? '').trim();
    if (bn.isNotEmpty) return bn;
    return commonName;
  }

  /// Public screens never fall back to raw coordinates: the server-built label
  /// is the only location shown, with a district/state fallback if it is absent.
  String get displayLocation {
    final label = (publicLocationLabel ?? '').trim();
    if (label.isNotEmpty) return label;
    final d = (district ?? '').trim();
    final s = (state ?? '').trim();
    if (d.isNotEmpty && s.isNotEmpty) return '$d জেলা, $s';
    if (s.isNotEmpty) return s;
    final c = (country ?? '').trim();
    return c.isNotEmpty ? c : 'ভারত';
  }

  List<WildlifeSightingMedia> get photos =>
      media.where((m) => m.isPhoto).toList()..sort(_byOrder);
  List<WildlifeSightingMedia> get audioClips =>
      media.where((m) => m.isAudio).toList()..sort(_byOrder);
  List<WildlifeSightingMedia> get videoClips =>
      media.where((m) => m.isVideo).toList()..sort(_byOrder);

  String? get coverStoragePath => photos.isEmpty ? null : photos.first.storagePath;

  bool get hasVerifiedIdentification =>
      verificationStatus == 'editor_verified' ||
      verificationStatus == 'scientifically_verified';

  String get verificationLabelBn =>
      SightingStatusLabels.verification(verificationStatus);

  static int _byOrder(WildlifeSightingMedia a, WildlifeSightingMedia b) =>
      a.displayOrder.compareTo(b.displayOrder);

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}

/// Contributor inbox entry (public.sighting_notifications).
/// Rows are generated by database triggers on editorial state changes, so the
/// client can read and mark them read but can never fabricate them.
class SightingNotificationItem {
  final String id;
  final String? sightingId;
  final String kind;
  final String titleBn;
  final String bodyBn;
  final bool isRead;
  final DateTime? createdAt;

  const SightingNotificationItem({
    required this.id,
    this.sightingId,
    required this.kind,
    required this.titleBn,
    this.bodyBn = '',
    this.isRead = false,
    this.createdAt,
  });

  factory SightingNotificationItem.fromJson(Map<String, dynamic> json) {
    return SightingNotificationItem(
      id: (json['id'] ?? '').toString(),
      sightingId: json['sighting_id']?.toString(),
      kind: (json['kind'] ?? 'editor_note').toString(),
      titleBn: (json['title_bn'] ?? '').toString(),
      bodyBn: (json['body_bn'] ?? '').toString(),
      isRead: json['is_read'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  String get kindLabelBn => SightingStatusLabels.notification(kind);

  bool get needsContributorAction => kind == 'info_requested';
}

/// Lightweight contributor identity + privacy preferences
/// (public.wildlife_contributor_profiles). Never stores email or phone.
class ContributorProfile {
  final String userId;
  final String displayName;
  final String privacy; // named | anonymous
  final String? district;
  final String? state;
  final String? bioBn;
  final DateTime? updatedAt;

  const ContributorProfile({
    required this.userId,
    this.displayName = '',
    this.privacy = 'named',
    this.district,
    this.state,
    this.bioBn,
    this.updatedAt,
  });

  factory ContributorProfile.fromJson(Map<String, dynamic> json) {
    return ContributorProfile(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      privacy: (json['privacy'] ?? 'named').toString(),
      district: json['district']?.toString(),
      state: json['state']?.toString(),
      bioBn: json['bio_bn']?.toString(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  bool get isAnonymous => privacy == 'anonymous';

  /// Public attribution label — anonymous contributors are never named.
  String get attributionLabel {
    if (isAnonymous) return 'নাম প্রকাশে অনিচ্ছুক';
    final name = displayName.trim();
    return name.isEmpty ? 'নাগরিক বিজ্ঞানী' : name;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user_id': userId,
        'display_name': displayName.trim().isEmpty ? null : displayName.trim(),
        'privacy': privacy,
        'district': district,
        'state': state,
        'bio_bn': bioBn,
      };
}
