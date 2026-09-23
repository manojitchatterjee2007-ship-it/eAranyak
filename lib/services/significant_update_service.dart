import 'package:supabase_flutter/supabase_flutter.dart';

/// Creates a significant_update_event through the secure edge function.
/// The event is then drained by the `deliver-significant-updates` cron job,
/// which delivers FCM notifications with the correct animal/nature sound.
///
/// Server-side authorization ensures only editors/admins can create events.
class SignificantUpdateService {
  /// Inserts a significant update event into the pipeline.
  ///
  /// [contentType] must be one of: news, gallery, magazine, quiz,
  /// app_notification, community_article, podcast, vlog, tutorial.
  /// [contentId] is the stable identifier for the content.
  /// [title]/[body] are the notification text.
  /// [data] is forwarded as the FCM data payload for deep-linking.
  static Future<void> create({
    required String contentType,
    required String contentId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'create-significant-update',
        body: {
          'content_type': contentType,
          'content_id': contentId,
          'title': title,
          'body': body,
          if (data != null) 'data': data,
        },
      );
    } catch (_) {
      // Fail silently — notification is best-effort and must not block the
      // editorial action that triggered it.
    }
  }
}
