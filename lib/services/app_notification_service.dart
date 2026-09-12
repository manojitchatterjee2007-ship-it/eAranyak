import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_notification.dart';

class AppNotificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch a single notification by ID
  static Future<AppNotificationItem?> fetchNotificationById(String id) async {
    try {
      final res = await Supabase.instance.client
          .from('app_notifications')
          .select('*, app_notification_images(*)')
          .eq('id', id)
          .maybeSingle();
      if (res != null) {
        return AppNotificationItem.fromJson(res);
      }
    } catch (_) {}
    return null;
  }

  /// Upload files (images or PDF) to Supabase Storage bucket 'app_notifications'
  Future<String> uploadFile({
    required PlatformFile file,
    required String subFolder,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Editor session required / লগইন আবশ্যক');

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('ফাইল খোলার ক্ষেত্রে সমস্যা হয়েছে / File is empty');
    }

    final ext = file.extension?.toLowerCase() ?? 'bin';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final path = '$subFolder/$fileName';

    String contentType = 'application/octet-stream';
    if (ext == 'pdf') {
      contentType = 'application/pdf';
    } else if (ext == 'png') {
      contentType = 'image/png';
    } else if (ext == 'webp') {
      contentType = 'image/webp';
    } else if (['jpg', 'jpeg'].contains(ext)) {
      contentType = 'image/jpeg';
    }

    await _supabase.storage.from('app_notifications').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );

    return _supabase.storage.from('app_notifications').getPublicUrl(path);
  }

  /// Upload multiple image files
  Future<List<String>> uploadImages(List<PlatformFile> files, String notifId) async {
    final List<String> urls = [];
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        final url = await uploadFile(file: file, subFolder: 'notifications/$notifId/images');
        urls.add(url);
      } catch (_) {}
    }
    return urls;
  }

  /// Fetch PUBLISHED notifications for public display
  Future<List<AppNotificationItem>> fetchPublishedNotifications() async {
    try {
      try {
        final res = await _supabase
            .from('app_notifications')
            .select('*, app_notification_images(*)')
            .eq('is_published', true)
            .order('editorial_priority', ascending: false)
            .order('published_at', ascending: false);

        return (res as List).map((e) => AppNotificationItem.fromJson(e)).toList();
      } catch (_) {
        final res = await _supabase
            .from('app_notifications')
            .select()
            .eq('is_published', true)
            .order('editorial_priority', ascending: false)
            .order('published_at', ascending: false);

        return (res as List).map((e) => AppNotificationItem.fromJson(e)).toList();
      }
    } catch (e) {
      return [];
    }
  }

  /// Fetch all notifications for Admin editorial review
  Future<List<AppNotificationItem>> fetchAllNotifications({String? filter}) async {
    try {
      var query = _supabase.from('app_notifications').select('*, app_notification_images(*)');

      if (filter != null && filter.isNotEmpty && filter != 'all') {
        if (filter == 'published') {
          query = query.eq('is_published', true);
        } else if (filter == 'draft') {
          query = query.eq('is_published', false);
        } else if (['text', 'image', 'pdf'].contains(filter)) {
          query = query.eq('notification_type', filter);
        }
      }

      final res = await query.order('created_at', ascending: false);
      return (res as List).map((e) => AppNotificationItem.fromJson(e)).toList();
    } catch (_) {
      var query = _supabase.from('app_notifications').select();

      if (filter != null && filter.isNotEmpty && filter != 'all') {
        if (filter == 'published') {
          query = query.eq('is_published', true);
        } else if (filter == 'draft') {
          query = query.eq('is_published', false);
        } else if (['text', 'image', 'pdf'].contains(filter)) {
          query = query.eq('notification_type', filter);
        }
      }

      final res = await query.order('created_at', ascending: false);
      return (res as List).map((e) => AppNotificationItem.fromJson(e)).toList();
    }
  }

  /// Create a new notification item
  Future<AppNotificationItem> createNotification({
    required String title,
    String? snippet,
    String? content,
    required String notificationType, // 'text', 'image', 'pdf'
    List<PlatformFile> imageFiles = const [],
    PlatformFile? pdfFile,
    int priority = 10,
    bool publishNow = false,
  }) async {
    final user = _supabase.auth.currentUser;
    final now = DateTime.now().toUtc();

    // 1. Insert notification base record
    final Map<String, dynamic> payload = {
      'title': title.trim(),
      'snippet': snippet?.trim(),
      'content': content?.trim(),
      'notification_type': notificationType,
      'editorial_priority': priority,
      'is_published': publishNow,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      if (publishNow) 'published_at': now.toIso8601String(),
      if (user != null) 'created_by': user.id,
    };

    final res = await _supabase
        .from('app_notifications')
        .insert(payload)
        .select()
        .single();

    final notifId = res['id'].toString();
    String? mainThumbnailUrl;
    String? pdfPublicUrl;

    // 2. Handle PDF file upload if PDF type
    if (notificationType == 'pdf' && pdfFile != null) {
      try {
        pdfPublicUrl = await uploadFile(file: pdfFile, subFolder: 'notifications/$notifId/documents');
      } catch (_) {}
    }

    // 3. Handle image files upload if Image type or has images
    if (imageFiles.isNotEmpty) {
      for (int i = 0; i < imageFiles.length; i++) {
        try {
          final url = await uploadFile(file: imageFiles[i], subFolder: 'notifications/$notifId/images');
          final isPrimary = i == 0;
          if (isPrimary) mainThumbnailUrl = url;

          await _supabase.from('app_notification_images').insert({
            'notification_id': notifId,
            'image_url': url,
            'display_order': i,
            'is_primary': isPrimary,
          });
        } catch (_) {}
      }
    }

    // 4. Update thumbnail and PDF URL if available
    if (mainThumbnailUrl != null || pdfPublicUrl != null) {
      final Map<String, dynamic> updatePayload = {};
      if (mainThumbnailUrl != null) updatePayload['thumbnail_url'] = mainThumbnailUrl;
      if (pdfPublicUrl != null) updatePayload['pdf_url'] = pdfPublicUrl;

      await _supabase.from('app_notifications').update(updatePayload).eq('id', notifId);
    }

    // Return created notification
    final updatedRes = await _supabase
        .from('app_notifications')
        .select('*, app_notification_images(*)')
        .eq('id', notifId)
        .single();

    return AppNotificationItem.fromJson(updatedRes);
  }

  /// Publish a notification
  Future<void> publishNotification(String notifId, {int? priority}) async {
    final now = DateTime.now().toUtc();
    final Map<String, dynamic> payload = {
      'is_published': true,
      'published_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    if (priority != null) payload['editorial_priority'] = priority;

    await _supabase.from('app_notifications').update(payload).eq('id', notifId);
  }

  /// Unpublish a notification
  Future<void> unpublishNotification(String notifId) async {
    await _supabase.from('app_notifications').update({
      'is_published': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', notifId);
  }

  /// Update editorial priority
  Future<void> updatePriority(String notifId, int priority) async {
    await _supabase.from('app_notifications').update({
      'editorial_priority': priority,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', notifId);
  }

  /// Delete notification permanently
  Future<void> deleteNotification(String notifId) async {
    await _supabase.from('app_notifications').delete().eq('id', notifId);
  }
}
