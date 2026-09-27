/// Pure validation / formatting helpers for the Citizen Science sighting flow.
///
/// Everything in this file is side-effect free so the submission form, the
/// editorial review panel and the unit tests share exactly the same rules.
/// The server (PostgreSQL triggers + RLS) re-validates every value: this layer
/// exists to give citizens fast, friendly Bengali feedback.
class SightingValidation {
  SightingValidation._();

  // --- Limits (kept in sync with the SQL guard triggers) -------------------
  static const int maxPhotos = 8;
  static const int maxAudioClips = 2;
  static const int maxVideoClips = 2;
  static const int maxPhotoBytes = 15 * 1024 * 1024;
  static const int maxAudioBytes = 25 * 1024 * 1024;
  static const int maxVideoBytes = 100 * 1024 * 1024;
  static const int maxNameLength = 160;
  static const int maxDescriptionLength = 4000;
  static const int maxNotesLength = 2000;
  static const int maxIndividuals = 5000;

  static const List<String> allowedImageExtensions = <String>[
    'jpg', 'jpeg', 'png', 'webp'
  ];
  static const List<String> allowedAudioExtensions = <String>[
    'mp3', 'm4a', 'mp4', 'wav', 'ogg'
  ];
  static const List<String> allowedVideoExtensions = <String>[
    'mp4', 'mov', 'webm'
  ];

  // --- Status / verification vocabulary ------------------------------------
  static const List<String> statuses = <String>[
    'draft', 'submitted', 'under_review', 'needs_information',
    'approved', 'published', 'rejected', 'archived'
  ];

  static const List<String> verificationStatuses = <String>[
    'unverified', 'user_reported', 'ai_suggestion',
    'editor_verified', 'scientifically_verified'
  ];

  static const List<String> locationPrecisions = <String>[
    'precise_private', 'district', 'region', 'hidden'
  ];

  /// Statuses a contributor may still edit / resubmit.
  static const List<String> contributorEditableStatuses = <String>[
    'draft', 'submitted', 'needs_information'
  ];

  // --- Text -----------------------------------------------------------------
  /// Trims, strips control characters and caps length.
  static String normalizeText(String? value, {int maxLength = maxDescriptionLength}) {
    if (value == null) return '';
    final cleaned = value
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '')
        .trim();
    if (cleaned.length <= maxLength) return cleaned;
    return cleaned.substring(0, maxLength);
  }

  static bool containsBengali(String value) =>
      RegExp(r'[\u0980-\u09FF]').hasMatch(value);

  static String? validateSpeciesName(String? value) {
    final cleaned = normalizeText(value, maxLength: maxNameLength);
    if (cleaned.isEmpty) {
      return 'আপনি কী দেখেছেন তা লিখুন (বাংলা বা ইংরেজি নাম)';
    }
    if (cleaned.length < 2) {
      return 'নামটি খুব ছোট — অন্তত দুটি অক্ষর দিন';
    }
    return null;
  }

  static String? validateDescription(String? value) {
    // Description is optional — editors can always request more information.
    return null;
  }

  static String? validateIndividualCount(String? value) {
    final cleaned = normalizeText(value, maxLength: 12);
    if (cleaned.isEmpty) return null;
    final parsed = int.tryParse(cleaned);
    if (parsed == null) return 'সংখ্যাটি অঙ্কে লিখুন (যেমন ২ বা 2)';
    if (parsed < 1 || parsed > maxIndividuals) {
      return '১ থেকে $maxIndividuals-এর মধ্যে একটি সংখ্যা দিন';
    }
    return null;
  }

  static const Map<String, String> _bengaliDigits = <String, String>{
    '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
    '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
  };

  /// Accepts Bengali or Western digits and returns the parsed int.
  static int parseCount(String? value, {int fallback = 1}) {
    final cleaned = normalizeText(value, maxLength: 12);
    if (cleaned.isEmpty) return fallback;
    final western = cleaned.split('').map((ch) => _bengaliDigits[ch] ?? ch).join();
    return int.tryParse(western) ?? fallback;
  }

  // --- Files ---------------------------------------------------------------
  /// Safe, collision-resistant storage file name (anti path-traversal).
  static String sanitizeFileName(
    String rawName, {
    required String userId,
    required String sightingId,
    int index = 0,
  }) {
    final base = rawName.replaceAll('\\', '/').split('/').last;
    var ext = base.contains('.') ? base.split('.').last.toLowerCase() : '';
    ext = ext.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (ext.isEmpty) ext = 'jpg';
    if (ext.length > 5) ext = ext.substring(0, 5);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeUser = userId.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
    final safeSighting = sightingId.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
    return '$safeUser/$safeSighting/${stamp}_$index.$ext';
  }

  static bool isAllowedExtension(String kind, String? extension) {
    final ext = (extension ?? '').toLowerCase();
    switch (kind) {
      case 'audio':
        return allowedAudioExtensions.contains(ext);
      case 'video':
        return allowedVideoExtensions.contains(ext);
      case 'photo':
      default:
        return allowedImageExtensions.contains(ext);
    }
  }

  static int maxBytesForKind(String kind) {
    switch (kind) {
      case 'audio':
        return maxAudioBytes;
      case 'video':
        return maxVideoBytes;
      case 'photo':
      default:
        return maxPhotoBytes;
    }
  }

  static int maxCountForKind(String kind) {
    switch (kind) {
      case 'audio':
        return maxAudioClips;
      case 'video':
        return maxVideoClips;
      case 'photo':
      default:
        return maxPhotos;
    }
  }

  static String? validateFileSize(String kind, int sizeBytes) {
    if (sizeBytes <= 0) return 'ফাইলটি খালি বলে মনে হচ্ছে';
    final limit = maxBytesForKind(kind);
    if (sizeBytes > limit) {
      final mb = (limit / (1024 * 1024)).toStringAsFixed(0);
      return 'ফাইলটি অনেক বড় — সর্বোচ্চ ${mb}MB গ্রহণ করা হয়';
    }
    return null;
  }

  static String contentTypeForExtension(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  // --- Coordinates ---------------------------------------------------------
  static double? parseCoordinate(String? value, {required bool isLatitude}) {
    final cleaned = normalizeText(value, maxLength: 24);
    if (cleaned.isEmpty) return null;
    final western = cleaned.split('').map((ch) => _bengaliDigits[ch] ?? ch).join();
    final parsed = double.tryParse(western);
    if (parsed == null) return null;
    final limit = isLatitude ? 90.0 : 180.0;
    if (parsed < -limit || parsed > limit) return null;
    return parsed;
  }

  // --- IUCN / masking (mirrors the SQL helper functions) -------------------
  static const Set<String> threatCategories = <String>{
    'cr', 'en', 'vu', 'nt', 'critically endangered', 'endangered',
    'vulnerable', 'near threatened'
  };

  static String sensitivityFromIucn(String? iucn, {String current = 'normal'}) {
    if (current == 'critical') return 'critical';
    final value = normalizeText(iucn, maxLength: 60).toLowerCase();
    if (threatCategories.contains(value)) return 'high';
    if (current == 'high') return 'high';
    if (current == 'elevated') return 'elevated';
    return 'normal';
  }

  static String effectivePrecision(String precision, String sensitivity) {
    final p = locationPrecisions.contains(precision) ? precision : 'district';
    if (sensitivity == 'critical') return 'hidden';
    if (sensitivity == 'high' && (p == 'precise_private' || p == 'district')) {
      return 'region';
    }
    return p;
  }

  /// Bengali-first public label preview — identical output to the SQL
  /// `build_public_location_label()` function, so what the citizen sees here is
  /// exactly what becomes public.
  static String previewPublicLocation({
    String? district,
    String? state,
    String? country,
    String precision = 'district',
    String sensitivity = 'normal',
  }) {
    final d = normalizeText(district, maxLength: 120);
    final s = normalizeText(state, maxLength: 120);
    final c = normalizeText(country, maxLength: 120);
    if (d.isEmpty && s.isEmpty && c.isEmpty) return '';
    final fallback = s.isNotEmpty ? s : (c.isNotEmpty ? c : 'ভারত');
    final effective = effectivePrecision(precision, sensitivity);
    if (effective == 'hidden' || d.isEmpty) return fallback;
    if (effective == 'region') return '$d-এর কাছে, $fallback';
    return '$d জেলা, $fallback';
  }

  /// Whether precise coordinates may be attached for the given sensitivity.
  static bool allowsPreciseCoordinates(String sensitivity) =>
      sensitivity == 'normal' || sensitivity == 'elevated';
}
