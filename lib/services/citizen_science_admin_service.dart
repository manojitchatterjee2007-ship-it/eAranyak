import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wildlife_sighting.dart';
import 'sighting_validation.dart';

/// Editorial service for the Citizen Science module of the Control Centre.
///
/// Every write goes through the same RLS + trigger guarded table the public app
/// uses, so publication state stays server-authoritative: this service can only
/// change what `public.is_editor()` is allowed to change.
class CitizenScienceAdminService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String mediaBucket = 'citizen_sightings';

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  Future<Map<String, int>> fetchStats() async {
    final empty = <String, int>{
      'total': 0,
      'pending_review': 0,
      'today': 0,
      'published': 0,
      'flagged': 0,
      'needs_information': 0,
      'approved': 0,
      'featured': 0,
    };
    try {
      final res = await _supabase.rpc('citizen_science_stats');
      if (res is Map) {
        return res.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
      }
    } catch (_) {}
    return empty;
  }

  /// Editorial list with search + filters (status, verification, species,
  /// district, date window, flagged, featured).
  Future<List<WildlifeSighting>> fetchSightings({
    String? status,
    String? verificationStatus,
    String? speciesQuery,
    String? district,
    String? state,
    DateTime? submittedFrom,
    DateTime? submittedTo,
    bool flaggedOnly = false,
    bool featuredOnly = false,
    int limit = 200,
  }) async {
    try {
      var query = _supabase.from('wildlife_sightings').select('*, wildlife_sighting_media(*)');

      if (status != null && status.isNotEmpty && status != 'all') {
        query = query.eq('status', status);
      }
      if (verificationStatus != null &&
          verificationStatus.isNotEmpty &&
          verificationStatus != 'all') {
        query = query.eq('verification_status', verificationStatus);
      }
      if (district != null && district.trim().isNotEmpty) {
        query = query.eq('district', district.trim());
      }
      if (state != null && state.trim().isNotEmpty) {
        query = query.eq('state', state.trim());
      }
      if (submittedFrom != null) {
        query = query.gte('submitted_at', submittedFrom.toUtc().toIso8601String());
      }
      if (submittedTo != null) {
        query = query.lte('submitted_at', submittedTo.toUtc().toIso8601String());
      }
      if (flaggedOnly) query = query.eq('is_flagged', true);
      if (featuredOnly) query = query.eq('featured', true);

      final species = (speciesQuery ?? '').trim();
      if (species.isNotEmpty) {
        final escaped = species.replaceAll(',', ' ').replaceAll('%', '');
        query = query.or(
            'common_name.ilike.%$escaped%,bengali_name.ilike.%$escaped%,scientific_name.ilike.%$escaped%,contributor_display_name.ilike.%$escaped%');
      }

      final rows = await query
          .order('is_flagged', ascending: false)
          .order('submitted_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .whereType<Map>()
          .map((e) => WildlifeSighting.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const <WildlifeSighting>[];
    }
  }

  Future<WildlifeSighting?> fetchSightingById(String id) async {
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

  Future<List<Map<String, dynamic>>> fetchAuditLog(String sightingId,
      {int limit = 60}) async {
    try {
      final rows = await _supabase
          .from('wildlife_sighting_audit_log')
          .select()
          .eq('sighting_id', sightingId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Distinct districts / states currently in the review queue (filter chips).
  Future<Map<String, List<String>>> fetchFacets() async {
    try {
      final rows = await _supabase
          .from('wildlife_sightings')
          .select('district, state')
          .limit(500);
      final districts = <String>{};
      final states = <String>{};
      for (final raw in (rows as List).whereType<Map>()) {
        final d = (raw['district'] ?? '').toString().trim();
        final s = (raw['state'] ?? '').toString().trim();
        if (d.isNotEmpty) districts.add(d);
        if (s.isNotEmpty) states.add(s);
      }
      return <String, List<String>>{
        'districts': districts.toList()..sort(),
        'states': states.toList()..sort(),
      };
    } catch (_) {
      return <String, List<String>>{
        'districts': <String>[],
        'states': <String>[],
      };
    }
  }

  // ---------------------------------------------------------------------------
  // Editorial actions
  // ---------------------------------------------------------------------------

  /// Sends a submission into formal review (submitted → under_review).
  Future<void> markUnderReview(String id) =>
      _update(id, <String, dynamic>{'status': 'under_review'});

  /// Asks the contributor for more information with a Bengali message.
  Future<void> requestInformation(String id, String message,
      {String? editorNotes}) async {
    await _update(id, <String, dynamic>{
      'status': 'needs_information',
      'info_request_message': SightingValidation.normalizeText(message,
          maxLength: SightingValidation.maxNotesLength),
      if (editorNotes != null)
        'editor_notes': SightingValidation.normalizeText(editorNotes,
            maxLength: SightingValidation.maxNotesLength),
    });
  }

  /// Marks the record editorially verified / approved (not yet public).
  Future<void> approve(
    String id, {
    String verificationStatus = 'editor_verified',
    String? editorNotes,
  }) async {
    await _update(id, <String, dynamic>{
      'status': 'approved',
      if (SightingValidation.verificationStatuses.contains(verificationStatus))
        'verification_status': verificationStatus,
      if (editorNotes != null)
        'editor_notes': SightingValidation.normalizeText(editorNotes,
            maxLength: SightingValidation.maxNotesLength),
    });
  }

  /// Publishes an approved sighting — the only path that makes it public.
  Future<void> publish(String id, {int priority = 10, bool? featured}) async {
    final payload = <String, dynamic>{
      'status': 'published',
      'editorial_priority': priority.clamp(0, 100),
    };
    if (featured != null) payload['featured'] = featured;
    await _update(id, payload);
  }

  Future<void> reject(String id, {required String reason}) async {
    await _update(id, <String, dynamic>{
      'status': 'rejected',
      'rejection_reason': SightingValidation.normalizeText(reason,
          maxLength: SightingValidation.maxNotesLength),
    });
  }

  /// Removes a sighting from the public feed but keeps the record.
  Future<void> archive(String id, {String? editorNotes}) async {
    await _update(id, <String, dynamic>{
      'status': 'archived',
      'featured': false,
      if (editorNotes != null)
        'editor_notes': SightingValidation.normalizeText(editorNotes,
            maxLength: SightingValidation.maxNotesLength),
    });
  }

  Future<void> setFeatured(String id, bool featured, {int? priority}) async {
    await _update(id, <String, dynamic>{
      'featured': featured,
      if (priority != null) 'editorial_priority': priority.clamp(0, 100),
    });
  }

  Future<void> setPriority(String id, int priority) =>
      _update(id, <String, dynamic>{'editorial_priority': priority.clamp(0, 100)});

  /// Flags / clears a moderation flag.
  Future<void> setFlagged(String id, bool flagged, {String? reason}) async {
    await _update(id, <String, dynamic>{
      'is_flagged': flagged,
      'flag_reason': flagged
          ? SightingValidation.normalizeText(
              (reason ?? 'সম্পাদকীয় পর্যালোচনা'), maxLength: 500)
          : null,
    });
  }

  /// Corrections: taxonomy, habitat, behaviour, dates, counts, IUCN status.
  Future<void> updateMetadata(
    String id, {
    String? commonName,
    String? bengaliName,
    String? scientificName,
    String? description,
    String? observationNotes,
    String? habitat,
    String? behaviour,
    int? individualCount,
    DateTime? observedAt,
    String? observedTime,
    String? iucnStatus,
    String? editorNotes,
    String? verificationStatus,
    String? aiSuggestedSpecies,
    String? aiSuggestionNote,
    bool? breedingSite,
  }) async {
    final payload = <String, dynamic>{};

    void put(String key, String? value,
        {int maxLength = SightingValidation.maxDescriptionLength}) {
      if (value == null) return;
      payload[key] = SightingValidation.normalizeText(value, maxLength: maxLength);
    }

    put('common_name', commonName, maxLength: SightingValidation.maxNameLength);
    put('bengali_name', bengaliName, maxLength: SightingValidation.maxNameLength);
    put('scientific_name', scientificName,
        maxLength: SightingValidation.maxNameLength);
    put('description', description);
    put('observation_notes', observationNotes,
        maxLength: SightingValidation.maxNotesLength);
    put('habitat', habitat, maxLength: 160);
    put('behaviour', behaviour, maxLength: 400);
    put('observed_time', observedTime, maxLength: 40);
    put('iucn_status', iucnStatus, maxLength: 60);
    put('editor_notes', editorNotes, maxLength: SightingValidation.maxNotesLength);
    put('ai_suggested_species', aiSuggestedSpecies,
        maxLength: SightingValidation.maxNameLength);
    put('ai_suggestion_note', aiSuggestionNote, maxLength: 400);

    if (individualCount != null) payload['individual_count'] = individualCount;
    if (observedAt != null) {
      final utc = observedAt.toUtc();
      payload['observed_at'] =
          '${utc.year}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
    }
    if (breedingSite != null) payload['breeding_site'] = breedingSite;
    if (verificationStatus != null &&
        SightingValidation.verificationStatuses.contains(verificationStatus)) {
      payload['verification_status'] = verificationStatus;
    }

    if (payload.isEmpty) return;
    await _update(id, payload);
  }

  /// Overrides / re-masks the public location representation.
  ///
  /// [precision] is the masking bucket; [publicLabel] is the exact string that
  /// becomes public (null keeps the database-generated label).
  Future<void> updateLocation(
    String id, {
    String? district,
    String? state,
    String? country,
    String? precision,
    String? publicLabel,
    String? sensitivityLevel,
    bool editorOverride = true,
    double? latitude,
    double? longitude,
    bool clearCoordinates = false,
  }) async {
    final payload = <String, dynamic>{};

    if (district != null) {
      payload['district'] = SightingValidation.normalizeText(district, maxLength: 120);
    }
    if (state != null) {
      payload['state'] = SightingValidation.normalizeText(state, maxLength: 120);
    }
    if (country != null) {
      payload['country'] = SightingValidation.normalizeText(country, maxLength: 120);
    }
    if (precision != null &&
        SightingValidation.locationPrecisions.contains(precision)) {
      payload['location_precision'] = precision;
    }
    if (publicLabel != null) {
      payload['public_location_label'] =
          publicLabel.trim().isEmpty ? null : publicLabel.trim();
    }
    if (sensitivityLevel != null &&
        const <String>['normal', 'elevated', 'high', 'critical']
            .contains(sensitivityLevel)) {
      payload['sensitivity_level'] = sensitivityLevel;
      payload['sensitivity_source'] = editorOverride ? 'editor' : 'auto';
    }
    if (clearCoordinates) {
      payload['latitude'] = null;
      payload['longitude'] = null;
    } else if (latitude != null && longitude != null) {
      payload['latitude'] = latitude;
      payload['longitude'] = longitude;
    }

    if (payload.isEmpty) return;
    await _update(id, payload);
  }

  /// Hides the precise location entirely (state-level only, coordinates removed).
  Future<void> hideSensitiveLocation(String id) => updateLocation(
        id,
        precision: 'hidden',
        publicLabel: null,
        clearCoordinates: true,
        sensitivityLevel: 'critical',
      );

  /// Deletes a sighting permanently, including its private storage objects.
  Future<void> deleteSighting(String id) async {
    List<String> paths = const <String>[];
    try {
      final rows = await _supabase
          .from('wildlife_sighting_media')
          .select('storage_path')
          .eq('sighting_id', id);
      paths = (rows as List)
          .map((e) => (e['storage_path'] ?? '').toString())
          .where((p) => p.isNotEmpty)
          .toList();
    } catch (_) {}

    await _supabase.from('wildlife_sightings').delete().eq('id', id);

    if (paths.isNotEmpty) {
      try {
        await _supabase.storage.from(mediaBucket).remove(paths);
      } catch (_) {}
    }
  }

  Future<void> _update(String id, Map<String, dynamic> payload) async {
    await _supabase.from('wildlife_sightings').update(payload).eq('id', id);
  }
}
