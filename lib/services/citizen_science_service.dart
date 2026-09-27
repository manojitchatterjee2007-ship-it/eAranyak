import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wildlife_sighting.dart';
import 'sighting_validation.dart';

/// Raised when a citizen submission cannot be completed; the message is always
/// safe to show to the contributor.
class SightingSubmissionException implements Exception {
  final String message;
  const SightingSubmissionException(this.message);

  @override
  String toString() => message;
}

/// Citizen-facing service for submitting and reading wildlife sightings.
///
/// Security model (see supabase/migrations/20260927120000_phase5_*):
///  * rows are owned by the authenticated contributor and readable only by the
///    owner or an editor;
///  * media lives in the private `citizen_sightings` bucket and is rendered
///    through ProtectedImage (120s signed URLs) — never a public URL;
///  * publication state, masking and notifications are computed server-side.
class CitizenScienceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String mediaBucket = 'citizen_sightings';
  static const String publicView = 'public_wildlife_sightings';
  static const String publicMediaView = 'public_sighting_media';

  // Client-side throttle: the database enforces the hard limits, this simply
  // avoids pointless round-trips for accidental double taps.
  static final List<DateTime> _submitTimestamps = <DateTime>[];
  static const int _maxSubmitsPerMinute = 6;

  bool _withinClientRateLimit() {
    final now = DateTime.now();
    _submitTimestamps.removeWhere(
        (ts) => now.difference(ts) > const Duration(minutes: 1));
    if (_submitTimestamps.length >= _maxSubmitsPerMinute) return false;
    _submitTimestamps.add(now);
    return true;
  }

  String? get currentUserId => _supabase.auth.currentUser?.id;

  static String _dateOnly(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();

  String _friendlyServerError(String raw) {
    final message = raw.trim();
    if (message.contains('Daily submission limit')) return message;
    if (message.contains('Please try again')) return message;
    if (message.contains('Species name is required')) {
      return 'প্রজাতির নাম আবশ্যক';
    }
    if (message.contains('row-level security')) {
      return 'এই কাজটি করার অনুমতি নেই';
    }
    return message.isEmpty ? 'অজানা সমস্যা হয়েছে' : message;
  }

  // ---------------------------------------------------------------------------
  // Submission
  // ---------------------------------------------------------------------------

  /// Creates the sighting row and uploads its media.
  ///
  /// Returns the created [WildlifeSighting]. Throws
  /// [SightingSubmissionException] with a Bengali message when validation or the
  /// server refuses the write.
  Future<WildlifeSighting> submitSighting({
    required String commonName,
    String? bengaliName,
    String? scientificName,
    String? description,
    String? observationNotes,
    String? iucnStatus,
    required DateTime observedAt,
    String? observedTime,
    String? habitat,
    int? individualCount,
    String? behaviour,
    String? district,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    String locationPrecision = 'district',
    bool breedingSite = false,
    String contributorPrivacy = 'named',
    String? contributorDisplayName,
    String status = 'submitted',
    List<PlatformFile> photos = const <PlatformFile>[],
    List<PlatformFile> audioClips = const <PlatformFile>[],
    List<PlatformFile> videoClips = const <PlatformFile>[],
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const SightingSubmissionException('দর্শন জমা দিতে লগইন করুন');
    }

    final nameError = SightingValidation.validateSpeciesName(commonName);
    if (nameError != null) throw SightingSubmissionException(nameError);

    if (!_withinClientRateLimit()) {
      throw const SightingSubmissionException(
          'এক মিনিটে অনেকবার চেষ্টা হয়েছে — অনুগ্রহ করে একটু অপেক্ষা করুন।');
    }

    if (photos.length > SightingValidation.maxPhotos) {
      throw SightingSubmissionException(
          'সর্বোচ্চ ${SightingValidation.maxPhotos}টি ছবি যোগ করা যায়');
    }

    final safeDistrict =
        SightingValidation.normalizeText(district, maxLength: 120);
    final safeState = SightingValidation.normalizeText(state, maxLength: 120);
    final safeCountry = SightingValidation.normalizeText(country, maxLength: 120);

    final payload = <String, dynamic>{
      'user_id': userId,
      'status': status == 'draft' ? 'draft' : 'submitted',
      'common_name': SightingValidation.normalizeText(commonName,
          maxLength: SightingValidation.maxNameLength),
      'bengali_name': _nullable(SightingValidation.normalizeText(bengaliName,
          maxLength: SightingValidation.maxNameLength)),
      'scientific_name': _nullable(SightingValidation.normalizeText(scientificName,
          maxLength: SightingValidation.maxNameLength)),
      'description': _nullable(SightingValidation.normalizeText(description)),
      'observation_notes': _nullable(SightingValidation.normalizeText(
          observationNotes,
          maxLength: SightingValidation.maxNotesLength)),
      'iucn_status': _nullable(
          SightingValidation.normalizeText(iucnStatus, maxLength: 60)),
      'observed_at': _dateOnly(observedAt),
      'observed_time': _nullable(
          SightingValidation.normalizeText(observedTime, maxLength: 40)),
      'habitat':
          _nullable(SightingValidation.normalizeText(habitat, maxLength: 160)),
      'individual_count': individualCount,
      'behaviour': _nullable(
          SightingValidation.normalizeText(behaviour, maxLength: 400)),
      'district': _nullable(safeDistrict),
      'state': _nullable(safeState),
      'country': safeCountry.isEmpty ? 'India' : safeCountry,
      'location_precision':
          SightingValidation.locationPrecisions.contains(locationPrecision)
              ? locationPrecision
              : 'district',
      'breeding_site': breedingSite,
      'contributor_privacy':
          contributorPrivacy == 'anonymous' ? 'anonymous' : 'named',
      'contributor_display_name': contributorPrivacy == 'anonymous'
          ? null
          : _nullable(SightingValidation.normalizeText(contributorDisplayName,
              maxLength: SightingValidation.maxNameLength)),
      'submission_source': 'app',
    };

    // Sensitive species: coordinates are only sent when masking allows them.
    final sensitivity = SightingValidation.sensitivityFromIucn(
      iucnStatus,
      current: breedingSite ? 'critical' : 'normal',
    );
    if (SightingValidation.allowsPreciseCoordinates(sensitivity) &&
        latitude != null &&
        longitude != null) {
      payload['latitude'] = latitude;
      payload['longitude'] = longitude;
    }

    Map<String, dynamic> created;
    try {
      created = await _supabase
          .from('wildlife_sightings')
          .insert(payload)
          .select()
          .single();
    } on PostgrestException catch (e) {
      throw SightingSubmissionException(_friendlyServerError(e.message));
    } catch (e) {
      throw SightingSubmissionException('দর্শন জমা দেওয়া যায়নি: $e');
    }

    final sightingId = (created['id'] ?? '').toString();
    if (sightingId.isEmpty) {
      throw const SightingSubmissionException('দর্শন সংরক্ষণ করা যায়নি');
    }

    final media = <WildlifeSightingMedia>[];
    media.addAll(await _uploadAll(
        userId: userId, sightingId: sightingId, kind: 'photo', files: photos));
    media.addAll(await _uploadAll(
        userId: userId,
        sightingId: sightingId,
        kind: 'audio',
        files: audioClips,
        startIndex: 100));
    media.addAll(await _uploadAll(
        userId: userId,
        sightingId: sightingId,
        kind: 'video',
        files: videoClips,
        startIndex: 200));

    return WildlifeSighting.fromJson(<String, dynamic>{
      ...created,
      'wildlife_sighting_media': media.map((m) => m.toJson()).toList(),
    });
  }

  /// Updates an own draft / returned sighting. Editorial columns are restored
  /// server-side for non-editors, so this can never bypass review.
  Future<void> updateSighting({
    required String sightingId,
    String? commonName,
    String? bengaliName,
    String? scientificName,
    String? description,
    String? observationNotes,
    DateTime? observedAt,
    String? observedTime,
    String? habitat,
    int? individualCount,
    String? behaviour,
    String? district,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    String? locationPrecision,
    bool? breedingSite,
    String? contributorPrivacy,
    String? contributorDisplayName,
    String? status,
  }) async {
    final payload = <String, dynamic>{};
    void put(String key, String? value, {int? maxLength}) {
      if (value == null) return;
      payload[key] = _nullable(SightingValidation.normalizeText(
          value,
          maxLength: maxLength ?? SightingValidation.maxDescriptionLength));
    }

    put('common_name', commonName, maxLength: SightingValidation.maxNameLength);
    put('bengali_name', bengaliName, maxLength: SightingValidation.maxNameLength);
    put('scientific_name', scientificName,
        maxLength: SightingValidation.maxNameLength);
    put('description', description);
    put('observation_notes', observationNotes,
        maxLength: SightingValidation.maxNotesLength);
    put('observed_time', observedTime, maxLength: 40);
    put('habitat', habitat, maxLength: 160);
    put('behaviour', behaviour, maxLength: 400);
    put('district', district, maxLength: 120);
    put('state', state, maxLength: 120);
    put('country', country, maxLength: 120);
    if (observedAt != null) payload['observed_at'] = _dateOnly(observedAt);
    if (individualCount != null) payload['individual_count'] = individualCount;
    if (breedingSite != null) payload['breeding_site'] = breedingSite;
    if (locationPrecision != null &&
        SightingValidation.locationPrecisions.contains(locationPrecision)) {
      payload['location_precision'] = locationPrecision;
    }
    if (latitude != null && longitude != null) {
      payload['latitude'] = latitude;
      payload['longitude'] = longitude;
    }
    if (contributorPrivacy != null) {
      payload['contributor_privacy'] =
          contributorPrivacy == 'anonymous' ? 'anonymous' : 'named';
    }
    if (contributorDisplayName != null) {
      payload['contributor_display_name'] = _nullable(
          SightingValidation.normalizeText(contributorDisplayName,
              maxLength: SightingValidation.maxNameLength));
    }
    if (status != null && const <String>['draft', 'submitted'].contains(status)) {
      payload['status'] = status;
    }

    if (payload.isEmpty) return;

    try {
      await _supabase
          .from('wildlife_sightings')
          .update(payload)
          .eq('id', sightingId);
    } on PostgrestException catch (e) {
      throw SightingSubmissionException(_friendlyServerError(e.message));
    }
  }

  /// Withdraws an unreviewed submission (storage objects are cleaned up too).
  Future<void> deleteSighting(String sightingId) async {
    List<String> paths = const <String>[];
    try {
      final rows = await _supabase
          .from('wildlife_sighting_media')
          .select('storage_path')
          .eq('sighting_id', sightingId);
      paths = (rows as List)
          .map((e) => (e['storage_path'] ?? '').toString())
          .where((p) => p.isNotEmpty)
          .toList();
    } catch (_) {}

    await _supabase.from('wildlife_sightings').delete().eq('id', sightingId);

    if (paths.isNotEmpty) {
      try {
        await _supabase.storage.from(mediaBucket).remove(paths);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Contributor reads
  // ---------------------------------------------------------------------------

  /// All sightings of the signed-in contributor (drafts included).
  Future<List<WildlifeSighting>> fetchMySightings() async {
    final userId = currentUserId;
    if (userId == null) return const <WildlifeSighting>[];
    try {
      final rows = await _supabase
          .from('wildlife_sightings')
          .select('*, wildlife_sighting_media(*)')
          .eq('user_id', userId)
          .order('submitted_at', ascending: false);
      return (rows as List)
          .whereType<Map>()
          .map((e) => WildlifeSighting.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const <WildlifeSighting>[];
    }
  }

  Future<WildlifeSighting?> fetchMySightingById(String id) async {
    try {
      final row = await _supabase
          .from('wildlife_sightings')
          .select('*, wildlife_sighting_media(*)')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return WildlifeSighting.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> fetchMyStats() async {
    final empty = <String, int>{
      'submitted': 0,
      'published': 0,
      'verified': 0,
      'pending': 0,
      'needs_information': 0,
    };
    try {
      final res = await _supabase.rpc('my_sighting_stats');
      if (res is Map) {
        return res.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
      }
    } catch (_) {}
    return empty;
  }

  /// Soft duplicate warning used on the submission form (never blocks).
  Future<Map<String, dynamic>?> findDuplicate({
    required String commonName,
    required DateTime observedAt,
    String? district,
  }) async {
    try {
      final res = await _supabase.rpc('check_sighting_duplicate', params: {
        'p_common_name': commonName,
        'p_observed_at': _dateOnly(observedAt),
        'p_district': (district == null || district.trim().isEmpty)
            ? null
            : district.trim(),
      });
      if (res is Map && res['sighting_id'] != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  Future<List<SightingNotificationItem>> fetchNotifications({int limit = 40}) async {
    final userId = currentUserId;
    if (userId == null) return const <SightingNotificationItem>[];
    try {
      final rows = await _supabase
          .from('sighting_notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .whereType<Map>()
          .map((e) =>
              SightingNotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const <SightingNotificationItem>[];
    }
  }

  Future<void> markNotificationRead(String id) async {
    try {
      await _supabase
          .from('sighting_notifications')
          .update(<String, dynamic>{'is_read': true}).eq('id', id);
    } catch (_) {}
  }

  Future<void> markAllNotificationsRead() async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await _supabase
          .from('sighting_notifications')
          .update(<String, dynamic>{'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Contributor identity (privacy preferences — never email/phone)
  // ---------------------------------------------------------------------------

  Future<ContributorProfile?> fetchContributorProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final row = await _supabase
          .from('wildlife_contributor_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return null;
      return ContributorProfile.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveContributorProfile(ContributorProfile profile) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const SightingSubmissionException('প্রোফাইল সংরক্ষণে লগইন প্রয়োজন');
    }
    final payload = profile.toJson()..['user_id'] = userId;
    try {
      await _supabase
          .from('wildlife_contributor_profiles')
          .upsert(payload, onConflict: 'user_id');
    } on PostgrestException catch (e) {
      throw SightingSubmissionException(_friendlyServerError(e.message));
    }
  }

  // ---------------------------------------------------------------------------
  // Public citizen-science feed (masked projection only)
  // ---------------------------------------------------------------------------

  /// Loads published sightings from the masked public view.
  ///
  /// Media is fetched in a second, explicit query and merged in Dart: this keeps
  /// the client independent of PostgREST view-relationship inference and makes
  /// sure no private column can be selected by accident.
  Future<List<PublicWildlifeSighting>> fetchPublicSightings({
    String? speciesQuery,
    String? district,
    String? state,
    String? habitat,
    DateTime? observedFrom,
    DateTime? observedTo,
    bool verifiedOnly = false,
    bool featuredOnly = false,
    int limit = 60,
  }) async {
    try {
      var query = _supabase.from(publicView).select('*');

      final species = (speciesQuery ?? '').trim();
      if (species.isNotEmpty) {
        final escaped = species.replaceAll(',', ' ').replaceAll('%', '');
        query = query.or(
            'common_name.ilike.%$escaped%,bengali_name.ilike.%$escaped%,scientific_name.ilike.%$escaped%');
      }
      if (district != null && district.trim().isNotEmpty) {
        query = query.eq('district', district.trim());
      }
      if (state != null && state.trim().isNotEmpty) {
        query = query.eq('state', state.trim());
      }
      if (habitat != null && habitat.trim().isNotEmpty) {
        query = query.eq('habitat', habitat.trim());
      }
      if (observedFrom != null) {
        query = query.gte('observed_at', _dateOnly(observedFrom));
      }
      if (observedTo != null) {
        query = query.lte('observed_at', _dateOnly(observedTo));
      }
      if (verifiedOnly) {
        query = query.inFilter('verification_status',
            <String>['editor_verified', 'scientifically_verified']);
      }
      if (featuredOnly) {
        query = query.eq('featured', true);
      }

      final rows = await query
          .order('featured', ascending: false)
          .order('editorial_priority', ascending: false)
          .order('observed_at', ascending: false)
          .order('published_at', ascending: false)
          .limit(limit);

      final list = (rows as List)
          .whereType<Map>()
          .map((e) => PublicWildlifeSighting.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      return _attachMedia(list);
    } catch (_) {
      return const <PublicWildlifeSighting>[];
    }
  }

  Future<PublicWildlifeSighting?> fetchPublicSightingById(String id) async {
    try {
      final row =
          await _supabase.from(publicView).select('*').eq('id', id).maybeSingle();
      if (row == null) return null;
      final list = await _attachMedia(<PublicWildlifeSighting>[
        PublicWildlifeSighting.fromJson(Map<String, dynamic>.from(row)),
      ]);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  Future<List<PublicWildlifeSighting>> _attachMedia(
      List<PublicWildlifeSighting> sightings) async {
    if (sightings.isEmpty) return sightings;

    final ids = sightings.map((s) => s.id).toList();
    Map<String, List<WildlifeSightingMedia>> mediaBySighting =
        <String, List<WildlifeSightingMedia>>{};
    try {
      final rows = await _supabase
          .from(publicMediaView)
          .select('*')
          .inFilter('sighting_id', ids);

      for (final raw in (rows as List).whereType<Map>()) {
        final media = WildlifeSightingMedia.fromJson(Map<String, dynamic>.from(raw));
        mediaBySighting
            .putIfAbsent(media.sightingId, () => <WildlifeSightingMedia>[])
            .add(media);
      }
    } catch (_) {
      mediaBySighting = <String, List<WildlifeSightingMedia>>{};
    }

    return sightings
        .map((s) => PublicWildlifeSighting(
              id: s.id,
              commonName: s.commonName,
              bengaliName: s.bengaliName,
              scientificName: s.scientificName,
              description: s.description,
              observedAt: s.observedAt,
              observedTime: s.observedTime,
              habitat: s.habitat,
              individualCount: s.individualCount,
              behaviour: s.behaviour,
              iucnStatus: s.iucnStatus,
              district: s.district,
              state: s.state,
              country: s.country,
              publicLocationLabel: s.publicLocationLabel,
              publicLocationPrecision: s.publicLocationPrecision,
              sensitivityLevel: s.sensitivityLevel,
              verificationStatus: s.verificationStatus,
              featured: s.featured,
              editorialPriority: s.editorialPriority,
              publishedAt: s.publishedAt,
              createdAt: s.createdAt,
              contributorName: s.contributorName,
              contributorPublic: s.contributorPublic,
              media: mediaBySighting[s.id] ?? const <WildlifeSightingMedia>[],
            ))
        .toList();
  }

  /// Species counts for the "জনপ্রিয় প্রজাতি" chips.
  Future<List<Map<String, dynamic>>> fetchPopularSpecies({int limit = 12}) async {
    try {
      final res = await _supabase.rpc('popular_sighting_species', params: {
        'p_limit': limit,
      });
      if (res is List) {
        return res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  /// Whether the public database has any published sighting at all (used to
  /// pick between a welcoming empty state and a "no results" state).
  Future<bool> hasAnyPublishedSightings() async {
    try {
      final count = await _supabase.from(publicView).count();
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  /// Community moderation: flags a published sighting for editorial review.
  Future<void> reportSighting(String sightingId, {String? reason}) async {
    try {
      await _supabase.rpc('report_sighting', params: {
        'p_sighting_id': sightingId,
        'p_reason': reason,
      });
    } on PostgrestException catch (e) {
      throw SightingSubmissionException(_friendlyServerError(e.message));
    }
  }
}
