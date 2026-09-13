import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/vlog.dart';

class VlogService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all vlogs for admin
  Future<List<Vlog>> fetchAllVlogs({String? filter}) async {
    try {
      var query = _supabase.from('vlogs').select();
      if (filter == 'published') {
        query = query.eq('is_published', true);
      } else if (filter == 'draft') {
        query = query.eq('is_published', false);
      }
      final res = await query
          .order('editorial_priority', ascending: false)
          .order('created_at', ascending: false);
      return (res as List).map((e) => Vlog.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  String _getContentType(String ext, {bool isVideo = false}) {
    final cleanExt = ext.toLowerCase();
    if (isVideo) {
      switch (cleanExt) {
        case 'webm':
          return 'video/webm';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        case 'mkv':
          return 'video/x-matroska';
        case 'mp4':
        default:
          return 'video/mp4';
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

  /// Upload file to vlogs bucket
  Future<Map<String, String>> uploadFile({
    required PlatformFile file,
    required String subFolder,
    bool isVideo = false,
  }) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Selected file is empty or unreadable');
    }

    final ext = file.extension?.toLowerCase() ?? (isVideo ? 'mp4' : 'jpg');
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final storagePath = '$subFolder/$fileName';
    final contentType = _getContentType(ext, isVideo: isVideo);

    await _supabase.storage.from('vlogs').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    final publicUrl = _supabase.storage.from('vlogs').getPublicUrl(storagePath);
    return {
      'publicUrl': publicUrl,
      'storagePath': storagePath,
    };
  }

  /// Create a new vlog
  Future<Vlog> createVlog({
    required String title,
    String? description,
    String? snippet,
    String? thumbnailUrl,
    String? videoUrl,
    String? storagePath,
    int? durationSeconds,
    String category = 'Nature',
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
      'description': description?.trim(),
      'snippet': snippet?.trim(),
      'thumbnail_url': thumbnailUrl?.trim(),
      'video_url': videoUrl?.trim(),
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

    final res = await _supabase.from('vlogs').insert(payload).select().single();
    return Vlog.fromJson(res);
  }

  /// Update vlog
  Future<Vlog> updateVlog({
    required String id,
    required String title,
    String? description,
    String? snippet,
    String? thumbnailUrl,
    String? videoUrl,
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

    if (thumbnailUrl != null) payload['thumbnail_url'] = thumbnailUrl.trim();
    if (videoUrl != null) payload['video_url'] = videoUrl.trim();
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

    final res = await _supabase.from('vlogs').update(payload).eq('id', id).select().single();

    // Clean up old storage object if replaced
    if (oldStoragePath != null &&
        oldStoragePath.isNotEmpty &&
        storagePath != null &&
        storagePath.isNotEmpty &&
        oldStoragePath != storagePath) {
      try {
        await _supabase.storage.from('vlogs').remove([oldStoragePath]);
      } catch (_) {}
    }

    return Vlog.fromJson(res);
  }

  /// Publish vlog
  Future<void> publishVlog(String id, {int? priority}) async {
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'is_published': true,
      'published_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    if (priority != null) payload['editorial_priority'] = priority;

    await _supabase.from('vlogs').update(payload).eq('id', id);
  }

  /// Unpublish vlog
  Future<void> unpublishVlog(String id) async {
    await _supabase.from('vlogs').update({
      'is_published': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Update priority
  Future<void> updatePriority(String id, int priority) async {
    await _supabase.from('vlogs').update({
      'editorial_priority': priority,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Toggle featured
  Future<void> toggleFeatured(String id, bool isFeatured) async {
    await _supabase.from('vlogs').update({
      'is_featured': isFeatured,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Delete vlog and associated storage
  Future<void> deleteVlog(String id, {String? storagePath}) async {
    await _supabase.from('vlogs').delete().eq('id', id);
    if (storagePath != null && storagePath.trim().isNotEmpty) {
      try {
        await _supabase.storage.from('vlogs').remove([storagePath.trim()]);
      } catch (_) {}
    }
  }
}
