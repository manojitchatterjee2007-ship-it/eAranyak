import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tutorial.dart';

class TutorialService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all tutorials for admin
  Future<List<Tutorial>> fetchAllTutorials({String? filter}) async {
    try {
      var query = _supabase.from('tutorials').select();

      if (filter == 'published') {
        query = query.eq('is_published', true);
      } else if (filter == 'draft') {
        query = query.eq('is_published', false);
      } else if (filter != null &&
          ['video', 'pdf', 'article', 'external'].contains(filter)) {
        query = query.eq('resource_type', filter);
      }

      final res = await query
          .order('editorial_priority', ascending: false)
          .order('created_at', ascending: false);

      return (res as List).map((e) => Tutorial.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch published tutorials for public UI
  Future<List<Tutorial>> fetchPublishedTutorials() async {
    final res = await _supabase
        .from('tutorials')
        .select()
        .eq('is_published', true)
        .order('editorial_priority', ascending: false)
        .order('published_at', ascending: false)
        .order('created_at', ascending: false);

    final list =
        (res as List).map((e) => Tutorial.fromJson(e)).toList();

    final now = DateTime.now().toUtc();

    return list.where((t) {
      if (!t.isPublished) return false;

      if (t.scheduledPublishAt != null &&
          t.scheduledPublishAt!.isAfter(now)) {
        return false;
      }

      if (t.expiresAt != null &&
          !t.expiresAt!.isAfter(now)) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Fetch a single published tutorial by ID
  Future<Tutorial?> fetchTutorialById(String id) async {
    try {
      final res = await _supabase
          .from('tutorials')
          .select()
          .eq('id', id)
          .eq('is_published', true)
          .maybeSingle();

      if (res == null) return null;

      final tutorial = Tutorial.fromJson(res);
      final now = DateTime.now().toUtc();

      if (tutorial.scheduledPublishAt != null &&
          tutorial.scheduledPublishAt!.isAfter(now)) {
        return null;
      }

      if (tutorial.expiresAt != null &&
          !tutorial.expiresAt!.isAfter(now)) {
        return null;
      }

      return tutorial;
    } catch (_) {
      return null;
    }
  }

  String _getContentType(
    String ext, {
    required String resourceType,
  }) {
    final cleanExt = ext.toLowerCase();

    if (resourceType == 'pdf') {
      return 'application/pdf';
    }

    if (resourceType == 'video') {
      switch (cleanExt) {
        case 'webm':
          return 'video/webm';
        case 'mov':
          return 'video/quicktime';
        case 'mp4':
        default:
          return 'video/mp4';
      }
    }

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

  /// Upload file to tutorials bucket
  Future<Map<String, String>> uploadFile({
    required PlatformFile file,
    required String subFolder,
    required String resourceType,
  }) async {
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw Exception('Selected file is empty or unreadable');
    }

    final ext = file.extension?.toLowerCase() ?? 'bin';

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';

    final storagePath = '$subFolder/$fileName';

    final contentType = _getContentType(
      ext,
      resourceType: resourceType,
    );

    await _supabase.storage.from('tutorials').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );

    final publicUrl = _supabase.storage
        .from('tutorials')
        .getPublicUrl(storagePath);

    return {
      'publicUrl': publicUrl,
      'storagePath': storagePath,
    };
  }

  /// Create a new tutorial
  ///
  /// Provenance fields are optional so existing manually-created
  /// tutorials continue to work normally.
  Future<Tutorial> createTutorial({
    required String title,
    String? description,
    String? snippet,
    String? thumbnailUrl,
    String? resourceUrl,
    String? storagePath,
    String resourceType = 'video',
    String category = 'General',
    String difficulty = 'beginner',
    int? durationMinutes,
    int priority = 10,
    bool isFeatured = false,
    bool isPublished = false,
    DateTime? scheduledPublishAt,
    DateTime? expiresAt,

    // Editorial/source provenance
    String? sourceUrl,
    String? sourceName,
    String? sourceArticleId,
    String? translationProvider,
    String? imageProvenance,
    List<dynamic>? contentBlocks,
  }) async {
    final user = _supabase.auth.currentUser;
    final now = DateTime.now().toUtc();

    final payload = {
      'title': title.trim(),
      'description': description?.trim(),
      'snippet': snippet?.trim(),
      'thumbnail_url': thumbnailUrl?.trim(),
      'resource_url': resourceUrl?.trim(),
      'storage_path': storagePath?.trim(),
      'resource_type': resourceType,
      'category': category.trim(),
      'difficulty': difficulty,
      if (durationMinutes != null)
        'duration_minutes': durationMinutes,
      'editorial_priority': priority,
      'is_featured': isFeatured,
      'is_published': isPublished,
      if (scheduledPublishAt != null)
        'scheduled_publish_at':
            scheduledPublishAt.toUtc().toIso8601String(),
      if (expiresAt != null)
        'expires_at': expiresAt.toUtc().toIso8601String(),
      'published_at':
          isPublished ? now.toIso8601String() : null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      if (user != null) 'created_by': user.id,
      if (user != null) 'updated_by': user.id,

      // Editorial/source provenance
      if (sourceUrl != null && sourceUrl.trim().isNotEmpty)
        'source_url': sourceUrl.trim(),
      if (sourceName != null && sourceName.trim().isNotEmpty)
        'source_name': sourceName.trim(),
      if (sourceArticleId != null &&
          sourceArticleId.trim().isNotEmpty)
        'source_article_id': sourceArticleId.trim(),
      if (translationProvider != null &&
          translationProvider.trim().isNotEmpty)
        'translation_provider': translationProvider.trim(),
      if (imageProvenance != null &&
          imageProvenance.trim().isNotEmpty)
        'image_provenance': imageProvenance.trim(),

      // Ordered rich tutorial content blocks.
      'content_blocks': contentBlocks ?? <dynamic>[],
    };

    final res = await _supabase
        .from('tutorials')
        .insert(payload)
        .select()
        .single();

    return Tutorial.fromJson(res);
  }

  /// Update tutorial
  Future<Tutorial> updateTutorial({
    required String id,
    required String title,
    String? description,
    String? snippet,
    String? thumbnailUrl,
    String? resourceUrl,
    String? storagePath,
    String? resourceType,
    String? category,
    String? difficulty,
    int? durationMinutes,
    int? priority,
    bool? isFeatured,
    bool? isPublished,
    DateTime? scheduledPublishAt,
    DateTime? expiresAt,
    String? oldStoragePath,

    // Editorial/source provenance
    String? sourceUrl,
    String? sourceName,
    String? sourceArticleId,
    String? translationProvider,
    String? imageProvenance,
    List<dynamic>? contentBlocks,
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

    if (thumbnailUrl != null) {
      payload['thumbnail_url'] = thumbnailUrl.trim();
    }

    if (resourceUrl != null) {
      payload['resource_url'] = resourceUrl.trim();
    }

    if (storagePath != null) {
      payload['storage_path'] = storagePath.trim();
    }

    if (resourceType != null) {
      payload['resource_type'] = resourceType;
    }

    if (category != null) {
      payload['category'] = category.trim();
    }

    if (difficulty != null) {
      payload['difficulty'] = difficulty;
    }

    if (durationMinutes != null) {
      payload['duration_minutes'] = durationMinutes;
    }

    if (priority != null) {
      payload['editorial_priority'] = priority;
    }

    if (isFeatured != null) {
      payload['is_featured'] = isFeatured;
    }

    if (isPublished != null) {
      payload['is_published'] = isPublished;

      if (isPublished) {
        payload['published_at'] = now.toIso8601String();
      }
    }

    if (scheduledPublishAt != null) {
      payload['scheduled_publish_at'] =
          scheduledPublishAt.toUtc().toIso8601String();
    }

    if (expiresAt != null) {
      payload['expires_at'] =
          expiresAt.toUtc().toIso8601String();
    }

    // Editorial/source provenance
    if (sourceUrl != null) {
      payload['source_url'] =
          sourceUrl.trim().isEmpty ? null : sourceUrl.trim();
    }

    if (sourceName != null) {
      payload['source_name'] =
          sourceName.trim().isEmpty ? null : sourceName.trim();
    }

    if (sourceArticleId != null) {
      payload['source_article_id'] =
          sourceArticleId.trim().isEmpty
              ? null
              : sourceArticleId.trim();
    }

    if (translationProvider != null) {
      payload['translation_provider'] =
          translationProvider.trim().isEmpty
              ? null
              : translationProvider.trim();
    }

    if (imageProvenance != null) {
      payload['image_provenance'] =
          imageProvenance.trim().isEmpty
              ? null
              : imageProvenance.trim();
    }

    // Do not overwrite existing rich content unless the caller supplies it.
    if (contentBlocks != null) {
      payload['content_blocks'] = contentBlocks;
    }

    final res = await _supabase
        .from('tutorials')
        .update(payload)
        .eq('id', id)
        .select()
        .single();

    // Clean up old storage object if replaced
    if (oldStoragePath != null &&
        oldStoragePath.isNotEmpty &&
        storagePath != null &&
        storagePath.isNotEmpty &&
        oldStoragePath != storagePath) {
      try {
        await _supabase.storage
            .from('tutorials')
            .remove([oldStoragePath]);
      } catch (_) {}
    }

    return Tutorial.fromJson(res);
  }

  /// Publish tutorial
  Future<void> publishTutorial(
    String id, {
    int? priority,
  }) async {
    final now = DateTime.now().toUtc();

    final payload = <String, dynamic>{
      'is_published': true,
      'published_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    if (priority != null) {
      payload['editorial_priority'] = priority;
    }

    await _supabase
        .from('tutorials')
        .update(payload)
        .eq('id', id);
  }

  /// Unpublish tutorial
  Future<void> unpublishTutorial(String id) async {
    await _supabase.from('tutorials').update({
      'is_published': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Update priority
  Future<void> updatePriority(
    String id,
    int priority,
  ) async {
    await _supabase.from('tutorials').update({
      'editorial_priority': priority,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Toggle featured
  Future<void> toggleFeatured(
    String id,
    bool isFeatured,
  ) async {
    await _supabase.from('tutorials').update({
      'is_featured': isFeatured,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Delete tutorial and associated storage
  Future<void> deleteTutorial(
    String id, {
    String? storagePath,
  }) async {
    await _supabase
        .from('tutorials')
        .delete()
        .eq('id', id);

    if (storagePath != null &&
        storagePath.trim().isNotEmpty) {
      try {
        await _supabase.storage
            .from('tutorials')
            .remove([storagePath.trim()]);
      } catch (_) {}
    }
  }
}