import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalyticsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Log a lightweight content analytics event
  Future<void> logEvent({
    required String contentType,
    required String contentId,
    required String eventType,
  }) async {
    try {
      await _supabase.from('content_analytics_events').insert({
        'content_type': contentType,
        'content_id': contentId,
        'event_type': eventType,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[Analytics] Log event error: $e');
    }
  }

  /// Fetch top analytics stats for the Admin Dashboard
  Future<Map<String, dynamic>> fetchAdminStats() async {
    try {
      final res = await _supabase
          .from('content_analytics_events')
          .select('content_type, content_id, event_type');

      final List<dynamic> events = res as List<dynamic>;

      int totalOpens = 0;
      int totalOrderClicks = 0;
      final Map<String, int> newsOpens = {};
      final Map<String, int> articleOpens = {};
      final Map<String, int> notificationOpens = {};
      final Map<String, int> bookOpens = {};
      final Map<String, int> bookOrderClicks = {};

      for (final event in events) {
        final type = (event['content_type'] ?? '').toString();
        final id = (event['content_id'] ?? '').toString();
        final eType = (event['event_type'] ?? '').toString();

        if (eType == 'open') totalOpens++;
        if (eType == 'order_click') totalOrderClicks++;

        if (type == 'news' && eType == 'open') {
          newsOpens[id] = (newsOpens[id] ?? 0) + 1;
        } else if (type == 'community_article' && eType == 'open') {
          articleOpens[id] = (articleOpens[id] ?? 0) + 1;
        } else if (type == 'notification' && eType == 'open') {
          notificationOpens[id] = (notificationOpens[id] ?? 0) + 1;
        } else if (type == 'online_book') {
          if (eType == 'open') {
            bookOpens[id] = (bookOpens[id] ?? 0) + 1;
          } else if (eType == 'order_click') {
            bookOrderClicks[id] = (bookOrderClicks[id] ?? 0) + 1;
          }
        }
      }

      return {
        'totalEvents': events.length,
        'totalOpens': totalOpens,
        'totalOrderClicks': totalOrderClicks,
        'newsOpens': newsOpens,
        'articleOpens': articleOpens,
        'notificationOpens': notificationOpens,
        'bookOpens': bookOpens,
        'bookOrderClicks': bookOrderClicks,
      };
    } catch (e) {
      debugPrint('[Analytics] Fetch stats error: $e');
      return {
        'totalEvents': 0,
        'totalOpens': 0,
        'totalOrderClicks': 0,
        'newsOpens': <String, int>{},
        'articleOpens': <String, int>{},
        'notificationOpens': <String, int>{},
        'bookOpens': <String, int>{},
        'bookOrderClicks': <String, int>{},
      };
    }
  }
}
