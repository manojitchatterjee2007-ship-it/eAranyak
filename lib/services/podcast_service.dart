import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/podcast.dart';

class PodcastService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all podcasts for admin
  Future<List<Podcast>> fetchAllPodcasts({String? filter}) async {
    try {
      var query = _supabase.from('podcasts').select();
      if (filter == 'published') {
        query = query.eq('is_published', true);
      } else if (filter == 'draft') {
        query = query.eq('is_published', false);
      }
      final res = await query
          .order('editorial_priority', ascending: false)
          .order('created_at', ascending: false);
      return (res as List).map((e) => Podcast.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch published podcasts for public UI
  Future<List<Podcast>> fetchPublishedPodcasts() async {
    final res = await _supabase
        .from('podcasts')
        .select()
        .eq('is_published', true)
        .order('editorial_priority', ascending: false)
        .order('published_at', ascending: false)
        .order('created_at', ascending: false);

    final list = (res as List).map((e) => Podcast.fromJson(e)).toList();
    final now = DateTime.now().toUtc();

    return list.where((p) {
      if (!p.isPublished) return false;
      if (p.scheduledPublishAt != null && p.scheduledPublishAt!.isAfter(now)) {
        return false;
      }
      if (p.expiresAt != null && !p.expiresAt!.isAfter(now)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Fetch a single published podcast episode by ID
  Future<Podcast?> fetchPodcastById(String id) async {
    try {
      final res = await _supabase
          .from('podcasts')
          .select()
          .eq('id', id)
          .eq('is_published', true)
          .maybeSingle();

      if (res == null) return null;
      final podcast = Podcast.fromJson(res);
      final now = DateTime.now().toUtc();

      if (podcast.scheduledPublishAt != null && podcast.scheduledPublishAt!.isAfter(now)) {
        return null;
      }
      if (podcast.expiresAt != null && !podcast.expiresAt!.isAfter(now)) {
        return null;
      }
      return podcast;
    } catch (_) {
      return null;
    }
  }

  String _getContentType(String ext, {bool isAudio = false}) {
    final cleanExt = ext.toLowerCase();
    if (isAudio) {
      switch (cleanExt) {
        case 'm4a':
          return 'audio/mp4';
        case 'wav':
          return 'audio/wav';
        case 'aac':
          return 'audio/aac';
        case 'ogg':
          return 'audio/ogg';
        case 'mp3':
        default:
          return 'audio/mpeg';
      }
    } else {
      switch (cleanExt) {
        case 'png':
          return 'image/png';
        case 'webp':
          return 'image/webp';
        case 'jpg':
        case 'jpeg':
        default:
          return 'image/jpeg';
      }
    }
  }

  /// Upload file to podcasts bucket
  Future<Map<String, String>> uploadFile({
    required PlatformFile file,
    required String subFolder,
    bool isAudio = false,
  }) async {
    // file_picker 13.x removed `PlatformFile.bytes`; the bytes are read on demand.
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Selected file is empty or unreadable');
    }

    final ext = file.extension?.toLowerCase() ?? (isAudio ? 'mp3' : 'jpg');
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final storagePath = '$subFolder/$fileName';
    final contentType = _getContentType(ext, isAudio: isAudio);

    await _supabase.storage.from('podcasts').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    final publicUrl = _supabase.storage.from('podcasts').getPublicUrl(storagePath);
    return {
      'publicUrl': publicUrl,
      'storagePath': storagePath,
    };
  }

  /// Create a new podcast episode
  Future<Podcast> createPodcast({
    required String title,
    int? episodeNumber,
    String? description,
    String? snippet,
    String? thumbnailUrl,
    String? audioUrl,
    String? storagePath,
    int? durationSeconds,
    String category = 'General',
    int priority = 10,
    bool isFeatured = false,
    bool isPublished = false,
    DateTime? scheduledPublishAt,
    DateTime? expiresAt,
  }) async {
    final user = _supabase.auth.currentUser;
    final now = DateTime.now().toUtc();

    final payload = {
      'title': title.trim(),
      if (episodeNumber != null) 'episode_number': episodeNumber,
      'description': description?.trim(),
      'snippet': snippet?.trim(),
      'thumbnail_url': thumbnailUrl?.trim(),
      'audio_url': audioUrl?.trim(),
      'storage_path': storagePath?.trim(),
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      'category': category.trim(),
      'editorial_priority': priority,
      'is_featured': isFeatured,
      'is_published': isPublished,
      if (scheduledPublishAt != null) 'scheduled_publish_at': scheduledPublishAt.toUtc().toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
      'published_at': isPublished ? now.toIso8601String() : null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      if (user != null) 'created_by': user.id,
      if (user != null) 'updated_by': user.id,
    };

    final res = await _supabase.from('podcasts').insert(payload).select().single();
    return Podcast.fromJson(res);
  }

  /// Update podcast
  Future<Podcast> updatePodcast({
    required String id,
    required String title,
    int? episodeNumber,
    String? description,
    String? snippet,
    String? thumbnailUrl,
    String? audioUrl,
    String? storagePath,
    int? durationSeconds,
    String? category,
    int? priority,
    bool? isFeatured,
    bool? isPublished,
    DateTime? scheduledPublishAt,
    DateTime? expiresAt,
    String? oldStoragePath,
  }) async {
    final user = _supabase.auth.currentUser;
    final now = DateTime.now().toUtc();

    final payload = <String, dynamic>{
      'title': title.trim(),
      'description': description?.trim(),
      'snippet': snippet?.trim(),
      'updated_at': now.toIso8601String(),
      if (user != null) 'updated_by': user.id,
    };

    if (episodeNumber != null) payload['episode_number'] = episodeNumber;
    if (thumbnailUrl != null) payload['thumbnail_url'] = thumbnailUrl.trim();
    if (audioUrl != null) payload['audio_url'] = audioUrl.trim();
    if (storagePath != null) payload['storage_path'] = storagePath.trim();
    if (durationSeconds != null) payload['duration_seconds'] = durationSeconds;
    if (category != null) payload['category'] = category.trim();
    if (priority != null) payload['editorial_priority'] = priority;
    if (isFeatured != null) payload['is_featured'] = isFeatured;
    if (isPublished != null) {
      payload['is_published'] = isPublished;
      if (isPublished) payload['published_at'] = now.toIso8601String();
    }
    if (scheduledPublishAt != null) payload['scheduled_publish_at'] = scheduledPublishAt.toUtc().toIso8601String();
    if (expiresAt != null) payload['expires_at'] = expiresAt.toUtc().toIso8601String();

    final res = await _supabase.from('podcasts').update(payload).eq('id', id).select().single();

    // Clean up old storage object if replaced
    if (oldStoragePath != null &&
        oldStoragePath.isNotEmpty &&
        storagePath != null &&
        storagePath.isNotEmpty &&
        oldStoragePath != storagePath) {
      try {
        await _supabase.storage.from('podcasts').remove([oldStoragePath]);
      } catch (_) {}
    }

    return Podcast.fromJson(res);
  }

  /// Publish podcast
  Future<void> publishPodcast(String id, {int? priority}) async {
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'is_published': true,
      'published_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    if (priority != null) payload['editorial_priority'] = priority;

    await _supabase.from('podcasts').update(payload).eq('id', id);
  }

  /// Unpublish podcast
  Future<void> unpublishPodcast(String id) async {
    await _supabase.from('podcasts').update({
      'is_published': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Update priority
  Future<void> updatePriority(String id, int priority) async {
    await _supabase.from('podcasts').update({
      'editorial_priority': priority,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Toggle featured
  Future<void> toggleFeatured(String id, bool isFeatured) async {
    await _supabase.from('podcasts').update({
      'is_featured': isFeatured,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Delete podcast and associated storage
  Future<void> deletePodcast(String id, {String? storagePath}) async {
    await _supabase.from('podcasts').delete().eq('id', id);
    if (storagePath != null && storagePath.trim().isNotEmpty) {
      try {
        await _supabase.storage.from('podcasts').remove([storagePath.trim()]);
      } catch (_) {}
    }
  }
}
