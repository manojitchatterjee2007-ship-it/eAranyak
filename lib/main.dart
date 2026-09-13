import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/config.dart';
import 'services/sound_service.dart';
import 'services/push_notification_service.dart';
import 'screens/boot_splash_screen.dart';
import 'screens/home_screen.dart';

// -------------------------------------------------------------
// BACKGROUND PERIODIC WORKMANAGER DISPATCHER
// -------------------------------------------------------------
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final supaClient = SupabaseClient(supabaseUrl, supabaseAnonKey);
      final res = await supaClient
          .from('wildlife_news')
          .select()
          .eq('is_published', true)
          .order('editorial_priority', ascending: false)
          .order('published_at', ascending: false)
          .limit(1);

      if (res.isNotEmpty) {
        final latest = res.first;
        final prefs = await SharedPreferences.getInstance();
        final lastNotifiedId = prefs.getString('last_background_news_id');
        final currentId = latest['id']?.toString() ?? latest['title'];

        if (lastNotifiedId != currentId) {
          await prefs.setString('last_background_news_id', currentId);
          final soundName = await NotificationSoundPool.getNextSound();

          final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'earanyak_news_v3',
            '📰 News Updates',
            channelDescription:
            'Real-time wildlife happenings & environmental news',
            importance: Importance.max,
            priority: Priority.high,
            sound: RawResourceAndroidNotificationSound(soundName),
            playSound: true,
          );

          final NotificationDetails notifDetails =
          NotificationDetails(android: androidDetails);

          final plugin = FlutterLocalNotificationsPlugin();
          await plugin.show(
            101,
            NewsEditorialService.safeHeadline(
                (latest['title'] ?? 'New Wildlife Update').toString()),
            latest['snippet'] ??
                'Tap to read full article / সম্পূর্ণ প্রতিবেদন পড়তে ট্যাপ করুন',
            notifDetails,
            payload: jsonEncode({
              'type': 'news',
              'id': latest['id']?.toString(),
              'title': latest['title']?.toString(),
            }),
          );
        }
      }
    } catch (_) {}
    return Future.value(true);
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Push messages with a "notification" block are displayed by the FCM system tray automatically.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    ).timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('[Boot] Supabase init failed: $e');
  }

  runApp(const EAranyakApp());

  unawaited(_initializeAppInBackground());
}

Future<void> _initializeAppInBackground() async {
  try {
    await SoundService.init();
  } catch (_) {}

  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings();
      const InitializationSettings initializationSettings =
      InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
        macOS: initializationSettingsDarwin,
      );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            unawaited(handleNotificationPayload(payload));
          }
        },
      ).timeout(const Duration(seconds: 20));

      final androidPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'earanyak_news_v3',
            '📰 News Updates',
            description: 'Real-time wildlife happenings & environmental news',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound('elephant_trumpet'),
            playSound: true,
          ),
        );
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'earanyak_gallery_v3',
            '📸 Wildlife Gallery',
            description: 'New gallery photos & wildlife photography',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound('owl_hoot'),
            playSound: true,
          ),
        );
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'earanyak_magazine_v3',
            '📖 Magazine Release',
            description: 'New magazine issues & special editions',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound('tiger_roar'),
            playSound: true,
          ),
        );
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'earanyak_quiz_v3',
            '🧩 Wildlife Quizzes',
            description: 'New quizzes & nature games',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound('cricket'),
            playSound: true,
          ),
        );
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'earanyak_events_v3',
            '📢 Official Announcements',
            description: 'App events & official announcements',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound('cricket'),
            playSound: true,
          ),
        );
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'earanyak_community_v3',
            '✍️ Community Articles',
            description: 'New reader & community articles published',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound('deer_call'),
            playSound: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Boot] Notifications init failed: $e');
    }

    try {
      Workmanager().initialize(callbackDispatcher);
      Workmanager().registerPeriodicTask(
        "wildlife_news_fetch_task",
        "fetchWildlifeNewsBackground",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('[Boot] Workmanager init failed: $e');
    }
  }

  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 20));
      await PushNotificationService.instance
          .init()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[Push] Firebase init skipped/failed: $e');
    }
  }

  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      final launchDetails = await flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails()
          .timeout(const Duration(seconds: 10));
      final payload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        PendingDeepLink.stash(payload);
      }
    } catch (_) {}
  }
}

class EAranyakApp extends StatelessWidget {
  const EAranyakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'eআরণ্যক',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1410),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF81C784),
          surface: Color(0xFF18221B),
        ),
      ),
      // NOTE: no `home:` here — onGenerateInitialRoutes below builds the
      // initial route (BootSplash) AND stashes any web deep-link URL
      // (/news/{id} or /social/article/{id}) before the app renders.
      // Flutter asserts that `home` and `onGenerateInitialRoutes` are
      // mutually exclusive, so the entry point must stay route-driven.
      onGenerateInitialRoutes: (initialRoute) {
        // Support direct Web URLs like /news/123
        final uri = Uri.tryParse(initialRoute);
        if (uri != null) {
          PendingDeepLink.stashFromUri(uri);
        }
        return [
          MaterialPageRoute(builder: (_) => const BootSplash()),
        ];
      },
      onGenerateRoute: (settings) {
        // Support navigation via browser address bar / shared links.
        // Accepts both /news/{id} and /social/article/{id} deep links.
        final uri = Uri.tryParse(settings.name ?? '');
        if (uri != null &&
            (uri.path.startsWith('/news/') ||
                uri.path.startsWith('/social/article/'))) {
          PendingDeepLink.stashFromUri(uri);
          return MaterialPageRoute(builder: (_) => const BootSplash());
        }
        return null;
      },
    );
  }
}
