import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../screens/news_detail_screen.dart';
import '../screens/magazine_reader_screen.dart';
import '../screens/wildlife_gallery_screen.dart';
import '../screens/nature_games_screen.dart';
import '../screens/notification_detail_screen.dart';
import '../screens/community_article_reader_screen.dart';
import '../screens/podcast_screen.dart';
import '../screens/vlog_screen.dart';
import '../screens/tutorial_screen.dart';
import '../services/app_notification_service.dart';
import '../services/writing_submission_service.dart';
import 'sound_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class PendingDeepLink {
  static final List<String> _pending = [];
  static void stash(String rawPayload) => _pending.add(rawPayload);
  static String? take() => _pending.isEmpty ? null : _pending.removeAt(0);

  static void stashFromUri(Uri uri) {
    final path = uri.path;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments[0] == 'news') {
      stash(jsonEncode({'type': 'news', 'id': segments[1]}));
    } else if (segments.length >= 3 &&
        segments[0] == 'social' &&
        segments[1] == 'article') {
      stash(jsonEncode({'type': 'news', 'id': segments[2]}));
    }
  }
}

Future<void> handleNotificationPayload(String rawPayload) async {
  try {
    final data = jsonDecode(rawPayload);
    if (data is Map<String, dynamic>) {
      await routeToContent(data);
    }
  } catch (_) {}
}

Future<void> routeToContent(Map<String, dynamic> data) async {
  final nav = navigatorKey.currentState;
  if (nav == null) {
    PendingDeepLink.stash(jsonEncode(data));
    return;
  }
  final type = (data['type'] ?? '').toString();
  try {
    if (type == 'news') {
      final idStr = (data['id'] ?? '').toString();
      Map<String, dynamic>? item;
      if (idStr.isNotEmpty) {
        try {
          final numId = int.tryParse(idStr);
          final query = supabase.from('wildlife_news').select('*, article_id');
          Map<String, dynamic>? res;
          
          try {
            res = await query.eq('id', idStr).maybeSingle();
          } catch (_) {}
          
          if (res == null && numId != null) {
            try {
              res = await query.eq('article_id', numId).maybeSingle();
            } catch (_) {}
          }
          
          if (res != null) {
            item = Map<String, dynamic>.from(res);
          }
        } catch (_) {}
      }
      
      item ??= {
        'id': idStr,
        'title': 'Article Not Found / প্রতিবেদনটি পাওয়া যায়নি',
        'content': 'The requested article may have been moved or deleted.\n(অনুরোধ করা প্রতিবেদনটি সরানো হয়েছে অথবা মুছে ফেলা হয়েছে।)',
        'source': 'eআরণ্যক',
        'is_not_found': true,
      };

      nav.push(MaterialPageRoute(
          builder: (_) => NewsDetailScreen(newsItem: item!)));
    } else if (type == 'game' || type == 'quiz') {
      final category = (data['category'] ?? 'photo').toString();
      final difficulty = (data['difficulty'] ?? 'medium').toString();

      if (category == 'scramble' || category == 'puzzle') {
        nav.push(
          MaterialPageRoute(
            builder: (_) => ScrambledImageGame(difficulty: difficulty),
          ),
        );
      } else if (category == 'word' || category == 'crossword') {
        nav.push(
          MaterialPageRoute(
            builder: (_) => WordPuzzleGame(difficulty: difficulty),
          ),
        );
      } else {
        nav.push(
          MaterialPageRoute(
            builder: (_) => WildlifeQuizGame(
              type: category,
              difficulty: difficulty,
            ),
          ),
        );
      }
    } else if (type == 'magazine') {
      final email = supabase.auth.currentUser?.email ?? 'guest';
      nav.push(MaterialPageRoute(
          builder: (_) => ProtectedReaderScreen(
              magazineId: (data['id'] ?? '').toString(),
              title: formatMagazineTitle((data['title'] ?? 'এখন আরণ্যক').toString()),
              userEmail: email)));
    } else if (type == 'gallery') {
      final email = supabase.auth.currentUser?.email ?? 'guest';
      final galleryPath = (data['id'] ?? '').toString();
      nav.push(MaterialPageRoute(
          builder: (_) => WildlifeGalleryScreen(
              userEmail: email,
              isAdmin: false,
              initialStoragePath:
                  galleryPath.isEmpty ? null : galleryPath)));
    } else if (type == 'app_notification' || type == 'notification') {
      final notifId = (data['id'] ?? '').toString();
      if (notifId.isNotEmpty) {
        try {
          final notif = await AppNotificationService.fetchNotificationById(notifId);
          if (notif != null) {
            nav.push(MaterialPageRoute(
                builder: (_) => NotificationDetailScreen(notification: notif)));
          }
        } catch (_) {}
      }
    } else if (type == 'community_article') {
      final articleId = (data['id'] ?? '').toString();
      if (articleId.isNotEmpty) {
        try {
          final article = await WritingSubmissionService.fetchSubmissionById(articleId);
          if (article != null) {
            nav.push(MaterialPageRoute(
                builder: (_) => CommunityArticleReaderScreen(article: article)));
          }
        } catch (_) {}
      }
    } else if (type == 'podcast') {
      final podcastId = (data['id'] ?? '').toString();
      nav.push(MaterialPageRoute(
          builder: (_) => PodcastScreen(
                initialPodcastId: podcastId.isNotEmpty ? podcastId : null,
              )));
    } else if (type == 'vlog') {
      final vlogId = (data['id'] ?? '').toString();
      nav.push(MaterialPageRoute(
          builder: (_) => VlogScreen(
                initialVlogId: vlogId.isNotEmpty ? vlogId : null,
              )));
    } else if (type == 'tutorial') {
      final tutorialId = (data['id'] ?? '').toString();
      nav.push(MaterialPageRoute(
          builder: (_) => TutorialScreen(
                initialTutorialId: tutorialId.isNotEmpty ? tutorialId : null,
              )));
    }
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  String? _lastToken;

  Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: true);

    final token = await messaging.getToken();
    _lastToken = token;
    if (token != null) await _registerToken(token);
    messaging.onTokenRefresh.listen((t) {
      _lastToken = t;
      unawaited(_registerToken(t));
    });

    supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession) {
        final t = _lastToken;
        if (t != null) unawaited(_registerToken(t));
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      unawaited(_showLocal(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      unawaited(routeToContent(message.data));
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      PendingDeepLink.stash(jsonEncode(initial.data));
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await supabase.from('device_tokens').upsert({
        'token': token,
        'user_id': supabase.auth.currentUser?.id,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'token');
      debugPrint('[Push] device token registered ok.');
    } catch (e) {
      debugPrint('[Push] device token registration FAILED: $e');
    }
  }

  Future<void> _showLocal(RemoteMessage message) async {
    try {
      final payloadData = message.data;
      final type = (payloadData['type'] ?? '').toString();

      String channelId = 'earanyak_general_v3';
      String channelName = '🌿 General Updates';

      String soundName = (payloadData['sound_key'] ?? payloadData['sound'] ?? '').toString();
      if (soundName.isEmpty || !NotificationSoundPool.notificationSounds.contains(soundName)) {
        soundName = await NotificationSoundPool.getNextSound();
      }

      if (type == 'news') {
        channelId = 'earanyak_news_v3';
        channelName = '📰 News Updates';
      } else if (type == 'gallery') {
        channelId = 'earanyak_gallery_v3';
        channelName = '📸 Wildlife Gallery';
      } else if (type == 'magazine') {
        channelId = 'earanyak_magazine_v3';
        channelName = '📖 Magazine Release';
      } else if (type == 'quiz' || type == 'game') {
        channelId = 'earanyak_quiz_v3';
        channelName = '🧩 Wildlife Quizzes';
      } else if (type == 'app_notification') {
        channelId = 'earanyak_events_v3';
        channelName = '📢 Official Announcements';
      } else if (type == 'community_article') {
        channelId = 'earanyak_community_v3';
        channelName = '✍️ Community Articles';
      } else if (type == 'podcast') {
        channelId = 'earanyak_podcast_v3';
        channelName = '🎙️ Podcast Episodes';
      } else if (type == 'vlog') {
        channelId = 'earanyak_vlog_v3';
        channelName = '🎬 Nature Vlogs';
      } else if (type == 'tutorial') {
        channelId = 'earanyak_tutorial_v3';
        channelName = '📚 Tutorials & Guides';
      }

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.max,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound(soundName),
        playSound: true,
      );

      await flutterLocalNotificationsPlugin.show(
       id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 2147483647,
       title: message.notification?.title ?? 'eআরণ্যক',
       body: message.notification?.body ?? '',
       notificationDetails: NotificationDetails(
        android: androidDetails,
       ),
       payload: jsonEncode(payloadData),
     );
    } catch (_) {}
  }
}

class AppNotifier {
  static Future<void> notify({
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      await supabase.functions.invoke(
        'send-significant-update',
        body: {'title': title, 'body': body, 'data': data},
        headers: {'x-significant-update-secret': 'earanyak-notify-2026'},
      );
    } catch (e) {
      debugPrint('[Push] notify invoke failed: $e');
    }
  }
}
