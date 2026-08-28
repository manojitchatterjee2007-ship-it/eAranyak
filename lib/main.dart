import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// --- CONFIGURATION ---
const String supabaseUrl = 'https://btbcojfuipogpsarjcdw.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0YmNvamZ1aXBvZ3BzYXJqY2R3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyNTU2OTYsImV4cCI6MjEwMjgzMTY5Nn0.q2wtTcZX15QWXMrRg9nWKleZC1F633Ng_d6ajsXuOng';
const String adminEmail = 'manojitchatterjee2007@gmail.com';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
          .order('created_at', ascending: false)
          .limit(1);

      if (res.isNotEmpty) {
        final latest = res.first;
        final prefs = await SharedPreferences.getInstance();
        final lastNotifiedId = prefs.getString('last_background_news_id');
        final currentId = latest['id']?.toString() ?? latest['title'];

        if (lastNotifiedId != currentId) {
          await prefs.setString('last_background_news_id', currentId);

          const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'wildlife_news_channel',
            'Wildlife News Updates',
            channelDescription:
            'Real-time wildlife happenings & environmental news',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          );

          const NotificationDetails notifDetails =
          NotificationDetails(android: androidDetails);

          final plugin = FlutterLocalNotificationsPlugin();
          await plugin.show(
            101,
            latest['title'] ?? 'New Wildlife Update',
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

// -------------------------------------------------------------
// SCHEMATIC GRID PAINTER
// -------------------------------------------------------------
class SchematicGridPainter extends CustomPainter {
  final Color accentColor;
  const SchematicGridPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 16) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 16) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    final circlePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 34, circlePaint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 22, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

// -------------------------------------------------------------
// BACKGROUND MULTI-TASK UPLOAD MANAGER
// -------------------------------------------------------------
class UploadTask {
  final String id;
  final String fileName;
  final String issueString;
  double progress;
  String status;
  bool isCompleted;
  bool hasError;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.issueString,
    this.progress = 0.0,
    this.status = 'Queued / সারিবদ্ধ...',
    this.isCompleted = false,
    this.hasError = false,
  });
}

class UploadManager {
  static final UploadManager instance = UploadManager._internal();
  UploadManager._internal();

  final ValueNotifier<List<UploadTask>> tasksNotifier = ValueNotifier([]);

  Future<void> startUpload({
    required PlatformFile file,
    required String issueString,
    required VoidCallback onAllCompleted,
  }) async {
    final task = UploadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${file.name}',
      fileName: file.name,
      issueString: issueString,
      status: 'Rendering & Slicing PDF...',
    );

    tasksNotifier.value = [...tasksNotifier.value, task];
    _processTask(task, file, onAllCompleted);
  }

  Future<void> _processTask(
      UploadTask task,
      PlatformFile file,
      VoidCallback onAllCompleted,
      ) async {
    try {
      final pdfBytes = file.bytes!;
      final doc = await pdfx.PdfDocument.openData(pdfBytes);
      final int totalPages = doc.pagesCount;

      final magRes = await supabase
          .from('magazines')
          .insert({
        'title': 'eআরণ্যক',
        'issue_date': task.issueString,
        'total_pages': totalPages,
      })
          .select()
          .single();

      final String magId = magRes['id'];

      for (int i = 1; i <= totalPages; i++) {
        task.status = 'Uploading page $i of $totalPages...';
        task.progress = i / totalPages;
        tasksNotifier.value = List.from(tasksNotifier.value);

        final page = await doc.getPage(i);
        final pageImg = await page.render(
          width: page.width * 1.6,
          height: page.height * 1.6,
          format: pdfx.PdfPageImageFormat.jpeg,
          quality: 82,
        );
        await page.close();

        if (pageImg != null) {
          final storagePath = '$magId/page_$i.jpg';

          await supabase.storage.from('magazine_pages').uploadBinary(
            storagePath,
            pageImg.bytes,
            fileOptions:
            const FileOptions(contentType: 'image/jpeg', upsert: true),
          );

          await supabase.from('magazine_pages').insert({
            'magazine_id': magId,
            'page_number': i,
            'storage_path': storagePath,
          });
        }
      }

      await doc.close();

      task.progress = 1.0;
      task.isCompleted = true;
      task.status = 'Completed / সম্পন্ন হয়েছে!';
      tasksNotifier.value = List.from(tasksNotifier.value);

      onAllCompleted();

      // Notify all app users about the new magazine issue.
      unawaited(AppNotifier.notify(
        title: 'নতুন সংখ্যা প্রকাশিত! (New Issue Published)',
        body: 'eআরণ্যক — ${task.issueString} এসেছে। পড়তে ট্যাপ করুন।',
        data: {
          'type': 'magazine',
          'id': magId,
          'title': 'eআরণ্যক — ${task.issueString}',
        },
      ));
    } catch (e) {
      task.hasError = true;
      task.status = 'Error: $e';
      tasksNotifier.value = List.from(tasksNotifier.value);
    }
  }

  void clearCompleted() {
    tasksNotifier.value =
        tasksNotifier.value.where((t) => !t.isCompleted).toList();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Render the first Flutter frame IMMEDIATELY. All initialization that can
  // touch the network (Supabase, Firebase, FCM token, notifications) runs in
  // the background as time-boxed, failure-isolated steps, so a slow or
  // unreachable endpoint can NEVER hold the splash/logo screen hostage.
  // (Previously main() awaited these BEFORE runApp(), which kept the native
  //  launch logo visible forever when any of them hung.)
  runApp(const EAranyakApp());

  unawaited(_initializeAppInBackground());
}

Future<void> _initializeAppInBackground() async {
  // 1) Core: Supabase client (needed by AuthGate and most screens).
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    ).timeout(const Duration(seconds: 20));
  } catch (e) {
    debugPrint('[Boot] Supabase init failed: $e');
  }

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    // 2) Local notifications.
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
    } catch (e) {
      debugPrint('[Boot] Notifications init failed: $e');
    }

    // 3) Background worker (best-effort; must never block startup).
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

  // 4) FCM push. Fully guarded: if Firebase is not configured (no
  //    google-services.json) or the network is unreachable, the app still runs
  //    exactly as before — only push delivery is skipped.
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 20));
    await PushNotificationService.instance
        .init()
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    debugPrint('[Push] Firebase init skipped/failed: $e');
  }

  // 5) If the app was launched by tapping a notification (cold start),
  //    remember the target so it can be opened after the shell loads.
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

final supabase = Supabase.instance.client;

// -------------------------------------------------------------
// NOTIFICATION DEEP-LINK ROUTING
// Payloads are JSON: {"type":"news"|"game"|"magazine"|"gallery", ...}
// -------------------------------------------------------------
class PendingDeepLink {
  static final List<String> _pending = [];
  static void stash(String rawPayload) => _pending.add(rawPayload);
  static String? take() => _pending.isEmpty ? null : _pending.removeAt(0);
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
    // Shell not ready yet (e.g. cold start) — retry once it mounts.
    PendingDeepLink.stash(jsonEncode(data));
    return;
  }
  final type = (data['type'] ?? '').toString();
  try {
    if (type == 'news') {
      final id = (data['id'] ?? '').toString();
      Map<String, dynamic>? item;
      if (id.isNotEmpty) {
        try {
          final res = await supabase
              .from('wildlife_news')
              .select()
              .eq('id', id)
              .limit(1);
          if (res.isNotEmpty) item = Map<String, dynamic>.from(res.first);
        } catch (_) {}
      }
      item ??= {
        'title': (data['title'] ?? '').toString(),
      };
      // Prefer the cached Bengali editorial for the article (the news rows
      // store the English source; translations live in the shared cache).
      final srcUrl = (item['source_url'] ?? '').toString();
      if (srcUrl.isNotEmpty) {
        try {
          final tr = await supabase
              .from('wildlife_news_translations')
              .select('headline, dek, body')
              .eq('source_url', srcUrl)
              .maybeSingle();
          final bnHeadline = tr?['headline']?.toString() ?? '';
          if (bnHeadline.isNotEmpty) {
            item['title'] = bnHeadline;
            final bnDek = tr?['dek']?.toString() ?? '';
            if (bnDek.isNotEmpty) item['snippet'] = bnDek;
            final bnBody = tr?['body']?.toString() ?? '';
            if (bnBody.isNotEmpty) item['content'] = bnBody;
          }
        } catch (_) {}
      }
      final target = item;
      nav.push(MaterialPageRoute(
          builder: (_) => NewsDetailScreen(newsItem: target)));
    } else if (type == 'game') {
      final category = (data['category'] ?? 'photo').toString();
      if (category == 'scramble') {
        nav.push(
            MaterialPageRoute(builder: (_) => const ScrambledImageGame()));
      } else {
        nav.push(
            MaterialPageRoute(builder: (_) => WildlifeQuizGame(type: category)));
      }
    } else if (type == 'magazine') {
      final email = supabase.auth.currentUser?.email ?? 'guest';
      nav.push(MaterialPageRoute(
          builder: (_) => ProtectedReaderScreen(
              magazineId: (data['id'] ?? '').toString(),
              title: (data['title'] ?? 'eআরণ্যক').toString(),
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
    }
  } catch (_) {}
}

// -------------------------------------------------------------
// FIREBASE CLOUD MESSAGING (guarded — no-ops if Firebase unconfigured)
// -------------------------------------------------------------
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  String? _lastToken;

  Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: true);

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    final token = await messaging.getToken();
    _lastToken = token;
    if (token != null) await _registerToken(token);
    messaging.onTokenRefresh.listen((t) {
      _lastToken = t;
      unawaited(_registerToken(t));
    });

    // Re-attach the device token whenever the user signs in. Registration
    // also runs at boot, but boot can happen before login — in that case
    // user_id would be null and a failed attempt would otherwise never be
    // retried until app restart.
    supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession) {
        final t = _lastToken;
        if (t != null) unawaited(_registerToken(t));
      }
    });

    // App in foreground: FCM does not auto-display, so show locally.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      unawaited(_showLocal(
        title: message.notification?.title ?? 'eআরণ্যক',
        body: message.notification?.body ?? '',
        payload: jsonEncode(message.data),
      ));
    });

    // Tapped while app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      unawaited(routeToContent(message.data));
    });

    // Tapped while app was terminated.
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
        'platform': 'android',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'token');
      debugPrint('[Push] device token registered ok.');
    } catch (e) {
      debugPrint('[Push] device token registration FAILED: $e');
    }
  }

  Future<void> _showLocal(
      {required String title, required String body, String? payload}) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'earanyak_push_channel',
        'eআরণ্যক Updates',
        channelDescription:
            'New magazine issues, gallery photos & weekly challenges',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );
      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 % 2147483647,
        title,
        body,
        const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Push messages with a "notification" block are displayed by the FCM
  // system tray automatically; nothing to do here.
}

// -------------------------------------------------------------
// SERVER-SIDE PUSH TRIGGER (called after admin uploads / weekly rotation)
// -------------------------------------------------------------
class AppNotifier {
  static Future<void> notify({
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      await supabase.functions.invoke(
        'notify-users',
        body: {'title': title, 'body': body, 'data': data},
        headers: {'x-earanyak-key': 'earanyak-notify-2026'},
      );
    } catch (e) {
      debugPrint('[Push] notify-users invoke failed: $e');
    }
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
        primaryColor: const Color(0xFF00E676),
        scaffoldBackgroundColor: const Color(0xFF0D1410),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF81C784),
          surface: Color(0xFF18221B),
        ),
        fontFamily: 'serif',
      ),
      home: const BootSplash(),
    );
  }
}

// -------------------------------------------------------------
// ANIMATED LAUNCH SCREEN (zoom-in icon on brand background)
// -------------------------------------------------------------
class BootSplash extends StatefulWidget {
  const BootSplash({super.key});

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _scale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.55));
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => const AuthGate()));
          }
        });
      }
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF141F17),
                    border: Border.all(
                        color: const Color(0xFF00E676), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF00E676).withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const Icon(Icons.eco,
                          size: 80, color: Color(0xFF00E676)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'eআরণ্যক',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 1. AUTH GATEWAY
// -------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        final identity = (session.user.email ?? session.user.phone ?? '')
            .trim()
            .toLowerCase();
        return MainNavigationShell(userEmail: identity);
      },
    );
  }
}

// -------------------------------------------------------------
// 2. REGISTRATION & LOGIN
// -------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneOrEmailCtrl = TextEditingController();
  final _optionalEmailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIdentity = prefs.getString('saved_identity');
    final savedPass = prefs.getString('saved_pass');
    if (savedIdentity != null && savedPass != null) {
      setState(() {
        _phoneOrEmailCtrl.text = savedIdentity;
        _passCtrl.text = savedPass;
        _rememberMe = true;
      });
    }
  }

  Future<void> _saveCredentials(String identity, String pass) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_identity', identity);
      await prefs.setString('saved_pass', pass);
    } else {
      await prefs.remove('saved_identity');
      await prefs.remove('saved_pass');
    }
  }

  Future<void> _forgotPassword() async {
    final identity = _phoneOrEmailCtrl.text.trim();
    if (identity.isEmpty || !identity.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please enter your registered Email address above\n(অনুগ্রহ করে ওপরে আপনার নিবন্ধিত ইমেইলটি লিখুন)'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      await supabase.auth.resetPasswordForEmail(identity);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Password reset link sent to your email\n(পাসওয়ার্ড রিসেট লিঙ্ক আপনার ইমেলে পাঠানো হয়েছে)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitAuth() async {
    final identity = _phoneOrEmailCtrl.text.trim();
    final optionalEmail = _optionalEmailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (identity.isEmpty || pass.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please enter mobile/email and password\n(মোবাইল নম্বর/ইমেইল ও পাসওয়ার্ড প্রদান করুন)'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      final bool isEmail = identity.contains('@');

      if (_isSignUp) {
        if (isEmail) {
          await supabase.auth.signUp(email: identity, password: pass);
        } else {
          final registrationEmail = optionalEmail.isNotEmpty
              ? optionalEmail
              : '$identity@earanyak.local';
          await supabase.auth.signUp(email: registrationEmail, password: pass);
        }

        await _saveCredentials(identity, pass);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF142419),
              content: Text(
                '“অরণ্য মানুষের আদিমতম শিক্ষক; প্রকৃতির প্রতিটি স্পন্দনে লুকানো থাকে জীবনের পরম সত্য।”\nWelcome to eআরণ্যক! Registration Complete. Please Login.\n(eআরণ্যক অ্যাপে স্বাগতম! সফলভাবে নিবন্ধিত হয়েছেন।)',
                style: TextStyle(color: Color(0xFF00E676)),
              ),
              duration: Duration(seconds: 5),
            ),
          );
          setState(() {
            _isSignUp = false;
          });
        }
      } else {
        if (isEmail) {
          await supabase.auth
              .signInWithPassword(email: identity, password: pass);
        } else {
          final loginEmail = optionalEmail.isNotEmpty
              ? optionalEmail
              : '$identity@earanyak.local';
          await supabase.auth
              .signInWithPassword(email: loginEmail, password: pass);
        }
        await _saveCredentials(identity, pass);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auth Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.22,
              child: Image.asset(
                'assets/images/tribute_bg.jpg',
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                errorBuilder: (c, e, s) => const SizedBox.shrink(),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF141F17),
                      border: Border.all(
                          color: const Color(0xFF00E676), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color:
                          const Color(0xFF00E676).withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Icon(Icons.eco,
                            size: 80, color: Color(0xFF00E676)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'eআরণ্যক',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Nature & Wildlife Digital Library\n(প্রকৃতি ও বন্যপ্রাণ ডিজিটাল লাইব্রেরি)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 380,
                    child: TextField(
                      controller: _phoneOrEmailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number or Email',
                        helperText: '(মোবাইল নম্বর অথবা ইমেইল)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android_rounded),
                      ),
                    ),
                  ),
                  if (_isSignUp) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 380,
                      child: TextField(
                        controller: _optionalEmailCtrl,
                        decoration: const InputDecoration(
                          labelText:
                          'Email Address (Optional for Welcome Mail)',
                          helperText:
                          '(ইমেইল ঠিকানা - ঐচ্ছিক ধন্যবাদ বার্তার জন্য)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 380,
                    child: TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText: '(পাসওয়ার্ড)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 380,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              activeColor: const Color(0xFF00E676),
                              onChanged: (val) {
                                setState(() {
                                  _rememberMe = val ?? true;
                                });
                              },
                            ),
                            const Text('Remember Me\n(মনে রাখুন)',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                        if (!_isSignUp)
                          TextButton(
                            onPressed: _forgotPassword,
                            child: const Text(
                                'Forgot Password?\n(পাসওয়ার্ড ভুলে গেছেন?)',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 10, color: Color(0xFF00E676))),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 380,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isLoading ? null : _submitAuth,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_isSignUp ? 'Register' : 'Login',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              _isSignUp
                                  ? '(নিবন্ধন করুন)'
                                  : '(প্রবেশ করুন)',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isSignUp = !_isSignUp;
                      });
                    },
                    child: Column(
                      children: [
                        Text(
                          _isSignUp
                              ? 'Already registered? Login'
                              : "New reader? Register with Mobile/Email",
                          style: const TextStyle(
                              color: Color(0xFF00E676), fontSize: 13),
                        ),
                        Text(
                          _isSignUp
                              ? '(ইতিমধ্যে অ্যাকাউন্ট আছে? প্রবেশ করুন)'
                              : '(নতুন পাঠক? ফোন/ইমেইল দিয়ে নিবন্ধন করুন)',
                          style: const TextStyle(
                              color: Color(0xFF81C784), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 3. MAIN NAVIGATION SHELL
// -------------------------------------------------------------
class MainNavigationShell extends StatefulWidget {
  final String userEmail;
  const MainNavigationShell({super.key, required this.userEmail});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  AudioPlayer? _audioPlayer;
  Timer? _audioTimer;

  final GlobalKey<_NatureGamesScreenState> _gamesKey =
  GlobalKey<_NatureGamesScreenState>();
  final GlobalKey<_BookshelfScreenState> _bookshelfKey =
  GlobalKey<_BookshelfScreenState>();
  final GlobalKey<_WildlifeGalleryScreenState> _galleryKey =
  GlobalKey<_WildlifeGalleryScreenState>();
  final GlobalKey<_HomeScreenState> _homeKey = GlobalKey<_HomeScreenState>();

  @override
  void initState() {
    super.initState();
    _initAndPlayBirdCall();
    // If the app was opened from a notification tap (cold start),
    // route to the target content once the shell is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final raw = PendingDeepLink.take();
      if (raw != null) {
        unawaited(handleNotificationPayload(raw));
      }
    });
  }

  Future<void> _initAndPlayBirdCall() async {
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setPlayerMode(PlayerMode.lowLatency);
      await _audioPlayer!.setVolume(1.0);
      await _audioPlayer!.play(AssetSource('audio/bird_call.mp3'));

      _audioTimer = Timer(const Duration(seconds: 10), () {
        _audioPlayer?.stop();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioTimer?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    if (index == 0) {
      _homeKey.currentState?.loadData();
    }
    if (index == 1) {
      _bookshelfKey.currentState?.loadMagazines();
    }
    if (index == 2) {
      _gamesKey.currentState?.refresh();
    }
    if (index == 3) {
      _galleryKey.currentState?.loadPhotos();
    }
  }

  void _openContactDialog() {
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.mail_outline_rounded, color: Color(0xFF00E676)),
                SizedBox(width: 10),
                Text('Contact & Feedback',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(left: 34),
              child: Text('(যোগাযোগ ও প্রতিক্রিয়া)',
                  style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send message directly to the editor:',
                style: TextStyle(fontSize: 13, color: Colors.white70)),
            const Text('(সরাসরি সম্পাদকের কাছে বার্তা পাঠান:)',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 14),
            TextField(
              controller: subjectCtrl,
              decoration: const InputDecoration(
                  labelText: 'Subject',
                  helperText: '(বিষয়)',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Write your message...',
                  helperText: '(আপনার বার্তা লিখুন...)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Cancel (বাতিল)',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send (পাঠান)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final subject = Uri.encodeComponent(
                  subjectCtrl.text.trim().isEmpty
                      ? 'eআরণ্যক Feedback'
                      : subjectCtrl.text.trim());
              final body = Uri.encodeComponent(
                  '${messageCtrl.text.trim()}\n\nFrom: ${widget.userEmail}');
              final mailUrl =
              Uri.parse('mailto:$adminEmail?subject=$subject&body=$body');

              Navigator.pop(ctx);
              if (await canLaunchUrl(mailUrl)) {
                await launchUrl(mailUrl, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = widget.userEmail.trim().toLowerCase() ==
        adminEmail.trim().toLowerCase() ||
        widget.userEmail.contains('admin');

    final List<Widget> pages = [
      HomeScreen(
          key: _homeKey,
          userEmail: widget.userEmail,
          onNavigateToBookshelf: () => _switchTab(1)),
      BookshelfScreen(key: _bookshelfKey, userEmail: widget.userEmail),
      NatureGamesScreen(key: _gamesKey),
      WildlifeGalleryScreen(
          key: _galleryKey, userEmail: widget.userEmail, isAdmin: isAdmin),
      if (isAdmin)
        AdminDashboardScreen(
            onUploadComplete: () =>
                _bookshelfKey.currentState?.loadMagazines()),
    ];

    if (_currentIndex >= pages.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.85),
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        title: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF00E676), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.35),
                blurRadius: 12,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/icon/app_icon.png',
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                color: const Color(0xFF00E676),
                child: const Center(
                  child: Text('e',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'serif')),
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF00E676), size: 24),
            tooltip: 'Refresh / রিফ্রেশ করুন',
            onPressed: () {
              _homeKey.currentState?.loadData();
              _bookshelfKey.currentState?.loadMagazines();
              _galleryKey.currentState?.loadPhotos();
            },
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF141F17),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(
                  top: 50, bottom: 24, left: 20, right: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF1E2E23), Color(0xFF141F17)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF00E676), width: 2.5)),
                    child: ClipOval(
                        child: Image.asset('assets/icon/app_icon.png',
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(Icons.eco,
                                color: Color(0xFF00E676), size: 34))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('eআরণ্যক',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(widget.userEmail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.home_rounded, color: Color(0xFF00E676)),
              title: const Text('Home'),
              subtitle: const Text('(নীড়)',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _switchTab(0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shelves, color: Color(0xFF00E676)),
              title: const Text('Bookshelf'),
              subtitle: const Text('(বইয়ের তাক)',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _switchTab(1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF00E676)),
              title: const Text('Wildlife Gallery'),
              subtitle: const Text('(চিত্রশালা)',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _switchTab(3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videogame_asset_rounded,
                  color: Color(0xFF00E676)),
              title: const Text('Nature Games'),
              subtitle: const Text('(খেলার ছলে প্রকৃতি পাঠ)',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _switchTab(2);
              },
            ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded,
                    color: Color(0xFF00E676)),
                title: const Text('Editor Mode'),
                subtitle: const Text('(সম্পাদক মোড)',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(context);
                  _switchTab(4);
                },
              ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.contact_mail_rounded,
                  color: Color(0xFF81C784)),
              title: const Text('Contact & Feedback'),
              subtitle: const Text('(যোগাযোগ ও মতামত)',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _openContactDialog();
              },
            ),
            const Spacer(),
            const Divider(color: Colors.white12),
            ListTile(
              leading:
              const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Logout',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold)),
              subtitle: const Text('(প্রস্থান)',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('saved_identity');
                await prefs.remove('saved_pass');
                await supabase.auth.signOut();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              // Keep the artwork fully visible below the app bar instead
              // of letting it hide behind the translucent top bar.
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight),
              child: Opacity(
                opacity: 0.22,
                child: Image.asset('assets/images/tribute_bg.jpg',
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                    errorBuilder: (c, e, s) => const SizedBox.shrink()),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0D1410).withValues(alpha: 0.15),
                    Colors.transparent,
                    const Color(0xFF0D1410).withValues(alpha: 0.85),
                    const Color(0xFF0D1410),
                  ],
                  stops: const [0.0, 0.35, 0.75, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(child: pages[_currentIndex]),

// Persistent Floating Upload Queue
          ValueListenableBuilder<List<UploadTask>>(
            valueListenable: UploadManager.instance.tasksNotifier,
            builder: (context, tasks, _) {
              final activeTasks = tasks.where((t) => !t.isCompleted).toList();
              if (activeTasks.isEmpty) {
                return const SizedBox.shrink();
              }

              return Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF142419),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 16)
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Color(0xFF00E676))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Uploading ${activeTasks.length} issue(s) in background...',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...activeTasks.map((t) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                    child: Text(
                                        '${t.fileName} (${t.issueString})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white70))),
                                Text('${(t.progress * 100).round()}%',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF00E676),
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                  value: t.progress,
                                  minHeight: 3,
                                  backgroundColor: Colors.white12,
                                  color: const Color(0xFF00E676)),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0D1410),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: _switchTab,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'Home\n(নীড়)'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.shelves), label: 'Bookshelf\n(বইয়ের তাক)'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.videogame_asset_rounded),
              label: 'Games\n(খেলা)'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.photo_library_rounded),
              label: 'Gallery\n(চিত্রশালা)'),
          if (isAdmin)
            const BottomNavigationBarItem(
                icon: Icon(Icons.admin_panel_settings_rounded),
                label: 'Editor\n(সম্পাদক)'),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// NATURAL WATERCOLOUR NEWS ART / COLD-PRESS PAPER
// -------------------------------------------------------------
class _WatercolorNewsPainter extends CustomPainter {
  final String title;
  final String category;
  final int seed;

  const _WatercolorNewsPainter({
    required this.title,
    required this.category,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final Rect rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFFE6E1D3),
    );

    _paintPaperWashes(canvas, size, random);
    _paintScene(canvas, size);
    _paintPigmentBleed(canvas, size, random);
    _paintPaperGrain(canvas, size, random);
  }

  void _paintPaperWashes(Canvas canvas, Size size, math.Random random) {
    const washColors = <Color>[
      Color(0xFF789177),
      Color(0xFF9B9A68),
      Color(0xFFB98262),
      Color(0xFF6E8290),
      Color(0xFF8F735A),
      Color(0xFFC4A96C),
    ];

    for (int i = 0; i < 34; i++) {
      final Offset center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final double w = size.width * (0.10 + random.nextDouble() * 0.26);
      final double h = size.height * (0.08 + random.nextDouble() * 0.24);
      final paint = Paint()
        ..color = washColors[random.nextInt(washColors.length)].withValues(
          alpha: 0.028 + random.nextDouble() * 0.052,
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          7 + random.nextDouble() * 12,
        );
      canvas.drawOval(
        Rect.fromCenter(center: center, width: w, height: h),
        paint,
      );
    }
  }

  void _paintScene(Canvas canvas, Size size) {
    if (category == 'birds' || title.contains('পাখি')) {
      _paintBirdScene(canvas, size);
    } else if (category == 'carnivore' || title.contains('কারাকাল')) {
      _paintCaracalScene(canvas, size);
    } else if (category == 'flora' || title.contains('কলসি')) {
      _paintFloraScene(canvas, size);
    } else if (category == 'art_eco') {
      _paintArtScene(canvas, size);
    } else if (category == 'history') {
      _paintHistoryScene(canvas, size);
    } else {
      _paintForestScene(canvas, size);
    }
  }

  void _paintBirdScene(Canvas canvas, Size size) {
    _paintSky(canvas, size, const Color(0xFFB9C8BE));
    _paintDistantTrees(
        canvas, size, const Color(0xFF74836A).withValues(alpha: 0.30), 5);
    _paintDistantTrees(
        canvas, size, const Color(0xFF5E6D59).withValues(alpha: 0.22), 8);

    final grass = Paint()
      ..color = const Color(0xFF7D875B).withValues(alpha: 0.48)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    for (int i = 0; i < 90; i++) {
      final x = (i / 90) * size.width;
      final y = size.height * (0.70 + (i % 7) * 0.02);
      canvas.drawLine(
        Offset(x, y + 12),
        Offset(x + math.sin(i) * 3, y - 7 - (i % 4) * 2),
        grass,
      );
    }

    _paintBranch(canvas, size, Offset(size.width * 0.03, size.height * 0.73),
        Offset(size.width * 0.58, size.height * 0.38));
    _paintBird(canvas, Offset(size.width * 0.48, size.height * 0.37), 1.0,
        const Color(0xFF4A5146));
    _paintBird(canvas, Offset(size.width * 0.69, size.height * 0.28), 0.68,
        const Color(0xFF5E6355));
    _paintSun(canvas, Offset(size.width * 0.18, size.height * 0.18),
        size.height * 0.10);
  }

  void _paintCaracalScene(Canvas canvas, Size size) {
    _paintSky(canvas, size, const Color(0xFFB8B39A));
    _paintHills(canvas, size);
    _paintBrushes(canvas, size, const Color(0xFF7C7654));

    final Offset base = Offset(size.width * 0.60, size.height * 0.64);
    _paintCaracal(canvas, base, size.height * 0.52);
    _paintSun(canvas, Offset(size.width * 0.18, size.height * 0.17),
        size.height * 0.09);
  }

  void _paintFloraScene(Canvas canvas, Size size) {
    _paintSky(canvas, size, const Color(0xFFC3CBBE));
    _paintDistantTrees(
        canvas, size, const Color(0xFF657B62).withValues(alpha: 0.28), 7);
    _paintLeafCluster(
        canvas,
        size,
        Offset(size.width * 0.28, size.height * 0.52),
        1.0,
        const Color(0xFF617F55));
    _paintLeafCluster(
        canvas,
        size,
        Offset(size.width * 0.72, size.height * 0.46),
        0.82,
        const Color(0xFF72835B));
    _paintPitcherPlant(canvas, Offset(size.width * 0.52, size.height * 0.68),
        size.height * 0.66);
    _paintSun(canvas, Offset(size.width * 0.78, size.height * 0.17),
        size.height * 0.085);
  }

  void _paintArtScene(Canvas canvas, Size size) {
    _paintSky(canvas, size, const Color(0xFFC6C4AE));
    _paintDistantTrees(
        canvas, size, const Color(0xFF6A775E).withValues(alpha: 0.30), 8);

    final person = Paint()
      ..color = const Color(0xFF6D5747).withValues(alpha: 0.56)
      ..strokeCap = StrokeCap.round;
    for (final Offset p in [
      Offset(size.width * 0.58, size.height * 0.54),
      Offset(size.width * 0.68, size.height * 0.59),
      Offset(size.width * 0.76, size.height * 0.56),
    ]) {
      canvas.drawCircle(
          p + Offset(0, -size.height * 0.10), size.height * 0.045, person);
      canvas.drawLine(p, p + Offset(0, size.height * 0.16),
          person..strokeWidth = size.height * 0.035);
      canvas.drawLine(
          p + Offset(0, size.height * 0.04),
          p + Offset(-size.width * 0.055, size.height * 0.09),
          person..strokeWidth = size.height * 0.018);
      canvas.drawLine(
          p + Offset(0, size.height * 0.04),
          p + Offset(size.width * 0.055, size.height * 0.09),
          person..strokeWidth = size.height * 0.018);
    }

    _paintAncientTree(canvas, size,
        Offset(size.width * 0.17, size.height * 0.82), size.height * 0.66);
    _paintSun(canvas, Offset(size.width * 0.78, size.height * 0.18),
        size.height * 0.09);
  }

  void _paintHistoryScene(Canvas canvas, Size size) {
    _paintSky(canvas, size, const Color(0xFFC1B8A2));
    _paintDistantTrees(
        canvas, size, const Color(0xFF69755B).withValues(alpha: 0.27), 7);
    _paintAncientTree(canvas, size,
        Offset(size.width * 0.30, size.height * 0.84), size.height * 0.72);
    _paintRibbonCrowd(canvas, size);
    _paintSun(canvas, Offset(size.width * 0.76, size.height * 0.17),
        size.height * 0.085);
  }

  void _paintForestScene(Canvas canvas, Size size) {
    _paintSky(canvas, size, const Color(0xFFBFC5B7));
    _paintDistantTrees(
        canvas, size, const Color(0xFF617360).withValues(alpha: 0.25), 9);
    _paintAncientTree(canvas, size,
        Offset(size.width * 0.43, size.height * 0.85), size.height * 0.76);
    _paintBrushes(canvas, size, const Color(0xFF73805B));
    _paintSun(canvas, Offset(size.width * 0.80, size.height * 0.18),
        size.height * 0.08);
  }

  void _paintSky(Canvas canvas, Size size, Color color) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.74),
      Paint()..color = color.withValues(alpha: 0.54),
    );
  }

  void _paintDistantTrees(Canvas canvas, Size size, Color color, int count) {
    final paint = Paint()..color = color;
    for (int i = 0; i < count; i++) {
      final double x = size.width * (i + 0.5) / count;
      final double y = size.height * (0.38 + (i % 3) * 0.045);
      final double r = size.height * (0.11 + (i % 2) * 0.035);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x, y), width: r * 1.8, height: r * 1.35),
          paint);
      canvas.drawLine(
        Offset(x, y + r * 0.55),
        Offset(x + (i.isEven ? -5 : 5), size.height * 0.83),
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..strokeWidth = 6,
      );
    }
  }

  void _paintHills(Canvas canvas, Size size) {
    final hill1 = Path()
      ..moveTo(0, size.height * 0.62)
      ..quadraticBezierTo(size.width * 0.22, size.height * 0.40,
          size.width * 0.47, size.height * 0.60)
      ..quadraticBezierTo(
          size.width * 0.72, size.height * 0.76, size.width, size.height * 0.44)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill1,
        Paint()..color = const Color(0xFF77735E).withValues(alpha: 0.38));

    final hill2 = Path()
      ..moveTo(0, size.height * 0.68)
      ..quadraticBezierTo(size.width * 0.18, size.height * 0.55,
          size.width * 0.40, size.height * 0.66)
      ..quadraticBezierTo(
          size.width * 0.70, size.height * 0.78, size.width, size.height * 0.58)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill2,
        Paint()..color = const Color(0xFF665F4A).withValues(alpha: 0.30));
  }

  void _paintBrushes(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.36)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    for (int i = 0; i < 120; i++) {
      final double x = (i / 120) * size.width;
      final double y = size.height * (0.73 + (i % 13) * 0.017);
      canvas.drawLine(
          Offset(x, y + 10), Offset(x - 1.5, y - (7 + i % 8)), paint);
    }
  }

  void _paintBranch(Canvas canvas, Size size, Offset a, Offset b) {
    final branch = Paint()
      ..color = const Color(0xFF564D3D).withValues(alpha: 0.58)
      ..strokeWidth = size.height * 0.026
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, branch);
    canvas.drawLine(
      Offset(size.width * 0.45, size.height * 0.47),
      Offset(size.width * 0.53, size.height * 0.22),
      branch..strokeWidth = size.height * 0.015,
    );
  }

  void _paintBird(Canvas canvas, Offset center, double scale, Color color) {
    final body = Paint()..color = color.withValues(alpha: 0.72);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 64 * scale, height: 38 * scale),
      body,
    );
    final wing = Path()
      ..moveTo(center.dx - 9 * scale, center.dy + 2 * scale)
      ..quadraticBezierTo(center.dx + 1 * scale, center.dy - 34 * scale,
          center.dx + 28 * scale, center.dy - 2 * scale)
      ..quadraticBezierTo(center.dx + 12 * scale, center.dy + 8 * scale,
          center.dx - 9 * scale, center.dy + 2 * scale)
      ..close();
    canvas.drawPath(wing, Paint()..color = color.withValues(alpha: 0.86));
    final beak = Path()
      ..moveTo(center.dx + 28 * scale, center.dy - 1 * scale)
      ..lineTo(center.dx + 45 * scale, center.dy + 3 * scale)
      ..lineTo(center.dx + 28 * scale, center.dy + 8 * scale)
      ..close();
    canvas.drawPath(
        beak, Paint()..color = const Color(0xFF9B7249).withValues(alpha: 0.74));
    canvas.drawCircle(Offset(center.dx + 19 * scale, center.dy - 10 * scale),
        2.1 * scale, Paint()..color = Colors.white70);
    canvas.drawCircle(Offset(center.dx + 19 * scale, center.dy - 10 * scale),
        1 * scale, Paint()..color = const Color(0xFF2F332F));
  }

  void _paintCaracal(Canvas canvas, Offset base, double h) {
    final fur = Paint()
      ..color = const Color(0xFF8E6548).withValues(alpha: 0.78);
    final darkFur = Paint()
      ..color = const Color(0xFF594637).withValues(alpha: 0.58);

    final body = Rect.fromCenter(
        center: base + Offset(-h * 0.03, -h * 0.15),
        width: h * 0.64,
        height: h * 0.32);
    canvas.drawOval(body, fur);
    canvas.drawCircle(base + Offset(h * 0.30, -h * 0.35), h * 0.16, fur);

    final leftEar = Path()
      ..moveTo(base.dx + h * 0.20, base.dy - h * 0.46)
      ..lineTo(base.dx + h * 0.24, base.dy - h * 0.70)
      ..lineTo(base.dx + h * 0.33, base.dy - h * 0.49)
      ..close();
    canvas.drawPath(leftEar, fur);
    final rightEar = Path()
      ..moveTo(base.dx + h * 0.36, base.dy - h * 0.48)
      ..lineTo(base.dx + h * 0.46, base.dy - h * 0.72)
      ..lineTo(base.dx + h * 0.50, base.dy - h * 0.42)
      ..close();
    canvas.drawPath(rightEar, fur);

    final legPaint = Paint()
      ..color = fur.color.withValues(alpha: 0.72)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.075;
    for (final dx in [-0.22, -0.06, 0.13, 0.28]) {
      canvas.drawLine(
        base + Offset(h * dx, -h * 0.03),
        base + Offset(h * (dx - 0.015), h * 0.30),
        legPaint,
      );
    }

    final tail = Path()
      ..moveTo(base.dx - h * 0.28, base.dy - h * 0.10)
      ..quadraticBezierTo(base.dx - h * 0.54, base.dy - h * 0.20,
          base.dx - h * 0.72, base.dy - h * 0.04);
    canvas.drawPath(
      tail,
      Paint()
        ..color = darkFur.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = h * 0.065,
    );

    canvas.drawCircle(base + Offset(h * 0.34, -h * 0.36), h * 0.018,
        Paint()..color = Colors.black54);
    final muzzle = Path()
      ..moveTo(base.dx + h * 0.38, base.dy - h * 0.28)
      ..quadraticBezierTo(base.dx + h * 0.48, base.dy - h * 0.22,
          base.dx + h * 0.39, base.dy - h * 0.15)
      ..quadraticBezierTo(base.dx + h * 0.31, base.dy - h * 0.22,
          base.dx + h * 0.38, base.dy - h * 0.28)
      ..close();
    canvas.drawPath(muzzle,
        Paint()..color = const Color(0xFFA68162).withValues(alpha: 0.52));
  }

  void _paintLeafCluster(
      Canvas canvas, Size size, Offset center, double scale, Color color) {
    final stem = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = size.height * 0.012
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center + Offset(0, size.height * 0.25 * scale),
        center + Offset(0, -size.height * 0.26 * scale), stem);
    for (int i = -3; i <= 3; i++) {
      final y = center.dy + i * size.height * 0.07 * scale;
      final side = i.isEven ? -1.0 : 1.0;
      final leafCenter =
      Offset(center.dx + side * size.width * 0.12 * scale, y);
      canvas.drawOval(
        Rect.fromCenter(
            center: leafCenter,
            width: size.width * 0.22 * scale,
            height: size.height * 0.10 * scale),
        Paint()..color = color.withValues(alpha: 0.40 + (i.abs() % 2) * 0.05),
      );
    }
  }

  void _paintPitcherPlant(Canvas canvas, Offset base, double h) {
    final stem = Paint()
      ..color = const Color(0xFF56714E).withValues(alpha: 0.66)
      ..strokeWidth = h * 0.017
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(base, base + Offset(-h * 0.07, -h * 0.74), stem);
    canvas.drawLine(base + Offset(-h * 0.03, -h * 0.30),
        base + Offset(-h * 0.38, -h * 0.47), stem);
    canvas.drawLine(base + Offset(-h * 0.05, -h * 0.45),
        base + Offset(h * 0.30, -h * 0.58), stem);

    _paintPitcher(canvas, base + Offset(-h * 0.07, -h * 0.72), h * 0.34,
        const Color(0xFF8E7450));
    _paintPitcher(canvas, base + Offset(-h * 0.38, -h * 0.48), h * 0.28,
        const Color(0xFF6F8255));
    _paintPitcher(canvas, base + Offset(h * 0.30, -h * 0.58), h * 0.30,
        const Color(0xFF7F6B4E));
  }

  void _paintPitcher(Canvas canvas, Offset center, double h, Color color) {
    final double w = h * 0.56;
    final path = Path()
      ..moveTo(center.dx - w * 0.32, center.dy - h * 0.30)
      ..quadraticBezierTo(center.dx - w * 0.67, center.dy + h * 0.07,
          center.dx - w * 0.28, center.dy + h * 0.42)
      ..quadraticBezierTo(center.dx, center.dy + h * 0.62, center.dx + w * 0.28,
          center.dy + h * 0.38)
      ..quadraticBezierTo(center.dx + w * 0.62, center.dy + h * 0.08,
          center.dx + w * 0.30, center.dy - h * 0.29)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.67));
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(center.dx, center.dy - h * 0.30),
          width: w,
          height: h * 0.15),
      Paint()..color = const Color(0xFF48523C).withValues(alpha: 0.78),
    );
    final vein = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.2;
    for (int i = -2; i <= 2; i++) {
      canvas.drawLine(
        Offset(center.dx + i * w * 0.12, center.dy - h * 0.16),
        Offset(center.dx + i * w * 0.08, center.dy + h * 0.26),
        vein,
      );
    }
  }

  void _paintAncientTree(Canvas canvas, Size size, Offset base, double h) {
    final trunk = Paint()
      ..color = const Color(0xFF635546).withValues(alpha: 0.54)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.055;
    canvas.drawLine(base, base + Offset(-size.width * 0.05, -h), trunk);
    canvas.drawLine(
        base + Offset(-size.width * 0.04, -h * 0.64),
        base + Offset(size.width * 0.11, -h * 0.83),
        trunk..strokeWidth = h * 0.035);

    for (int i = 0; i < 18; i++) {
      final angle = (i / 18) * math.pi * 2;
      final center = base +
          Offset(math.cos(angle) * size.width * 0.15,
              -h * 0.88 + math.sin(angle) * size.height * 0.10);
      canvas.drawCircle(
        center,
        size.height * (0.085 + (i % 3) * 0.018),
        Paint()
          ..color =
          const Color(0xFF617B5D).withValues(alpha: 0.18 + (i % 4) * 0.018),
      );
    }
  }

  void _paintRibbonCrowd(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6B594B).withValues(alpha: 0.38);
    for (int i = 0; i < 11; i++) {
      final x = size.width * (0.50 + i * 0.035);
      final y = size.height * (0.72 + (i % 3) * 0.02);
      canvas.drawCircle(
          Offset(x, y - size.height * 0.09), size.height * 0.025, paint);
      canvas.drawLine(
          Offset(x, y - size.height * 0.06),
          Offset(x, y + size.height * 0.08),
          paint..strokeWidth = size.height * 0.022);
    }
    final ribbon = Paint()
      ..color = const Color(0xFF98624F).withValues(alpha: 0.28)
      ..strokeWidth = size.height * 0.012
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(size.width * (0.53 + i * 0.06), size.height * 0.65),
        Offset(size.width * (0.61 + i * 0.04), size.height * 0.77),
        ribbon,
      );
    }
  }

  void _paintSun(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius * 1.45,
      Paint()
        ..color = const Color(0xFFE0B76E).withValues(alpha: 0.055)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFFE8C77E).withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      radius * 0.64,
      Paint()..color = const Color(0xFFF1D39C).withValues(alpha: 0.20),
    );
  }

  void _paintPigmentBleed(Canvas canvas, Size size, math.Random random) {
    for (int i = 0; i < 18; i++) {
      final x = random.nextDouble() * size.width;
      final y = size.height * (0.74 + random.nextDouble() * 0.26);
      final paint = Paint()
        ..color = const Color(0xFF6A6555)
            .withValues(alpha: 0.022 + random.nextDouble() * 0.026)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x, y),
            width: size.width * 0.10,
            height: size.height * 0.04),
        paint,
      );
    }
  }

  void _paintPaperGrain(Canvas canvas, Size size, math.Random random) {
    final grain = Paint()
      ..color = const Color(0xFF5C5346).withValues(alpha: 0.018);
    for (int i = 0; i < 420; i++) {
      canvas.drawCircle(
        Offset(random.nextDouble() * size.width,
            random.nextDouble() * size.height),
        0.3 + random.nextDouble() * 0.7,
        grain,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WatercolorNewsPainter oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.category != category ||
        oldDelegate.seed != seed;
  }
}

class _PaperTexturePainter extends CustomPainter {
  final int seed;

  const _PaperTexturePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final paint = Paint()
      ..color = const Color(0xFF5E5549).withValues(alpha: 0.018);
    for (int i = 0; i < 180; i++) {
      canvas.drawCircle(
        Offset(random.nextDouble() * size.width,
            random.nextDouble() * size.height),
        0.3 + random.nextDouble() * 0.7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperTexturePainter oldDelegate) =>
      oldDelegate.seed != seed;
}

// -------------------------------------------------------------
// AUTOMATIC PHOTO -> WATERCOLOR NEWS IMAGE
// No AI image-generation API is used here.
// Source photos are fetched and transformed locally in Flutter.
// Only a small bounded in-memory LRU cache is kept; no image files
// are written to permanent device storage.
// -------------------------------------------------------------
class _WatercolorNewsImage extends StatelessWidget {
  final Map<String, dynamic> item;
  final CustomPainter fallbackPainter;
  final BoxFit fit;

  const _WatercolorNewsImage({
    required this.item,
    required this.fallbackPainter,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = <String?>[
      item['image_url'],
      item['primaryImage'],
      item['primary_image'],
      item['watercolor_source_image'],
      item['image'],
    ].map((value) => value?.toString().trim()).firstWhere(
          (value) => value != null && value.isNotEmpty,
          orElse: () => null,
        );

    final sourceName = item['source']?.toString().trim() ?? '';
    var rawCredit = item['image_credit']?.toString().trim() ?? '';
    // Normalise credits: strip any duplicated "Photo:" / "Original image:"
    // prefixes so the overlay never renders phrases like
    // "Photo: Original image: Nature In Focus".
    rawCredit = rawCredit
        .replaceFirst(RegExp(r'^photo\s*:\s*', caseSensitive: false), '')
        .replaceFirst(
            RegExp(r'^original image(?: from|:)?\s*', caseSensitive: false),
            '')
        .trim();
    final credit = rawCredit.isNotEmpty
        ? rawCredit
        : (sourceName.isNotEmpty ? sourceName : 'Source publication');

    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null && imageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl,
            // Some publishers (e.g. Nature In Focus behind Cloudflare) reject
            // requests without a browser-like User-Agent.
            httpHeaders: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36',
            },
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (context, url) => Container(
              color: const Color(0xFF142419),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF81C784),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: const Color(0xFF142419),
              alignment: Alignment.center,
              child: const Icon(
                Icons.photo_outlined,
                color: Color(0xFF81C784),
                size: 42,
              ),
            ),
          )
        else
          // No photograph available — render the watercolor artwork instead
          // of an empty placeholder icon (fallbackPainter was previously
          // accepted but never used).
          CustomPaint(
            painter: fallbackPainter,
            child: const SizedBox.expand(),
          ),

        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Photo: $credit',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// 4. TAB 1: HOME
// -------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final String userEmail;
  final VoidCallback onNavigateToBookshelf;

  const HomeScreen(
      {super.key,
        required this.userEmail,
        required this.onNavigateToBookshelf});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _issues = [];
  Timer? _autoShuffleTimer;
  int _lastAnimalSoundIndex = -1;
  final AudioPlayer _notificationAudioPlayer = AudioPlayer();

  String? _lastReadMagId;
  String? _lastReadTitle;
  int _lastReadPage = 0;
  int _lastReadTotalPages = 0;

  static const List<String> _animalAudioAssets = [
    'audio/tiger_roar.mp3',
    'audio/elephant_trumpet.mp3',
    'audio/deer_call.mp3',
    'audio/owl_hoot.mp3',
  ];

  static const List<Map<String, dynamic>> _masterNewsPool = [
    {
      'title': 'গাছ লাগানোর ভুল পদক্ষেপে সাভানা ঘাসজমির পাখি বিপন্ন',
      'source': 'Mongabay India',
      'source_url':
      'https://india.mongabay.com/2026/07/when-trees-replace-grasslands-specialist-birds-lose-their-habitat/',
      'date_str': '০২ জুলাই, ২০২৬',
      'category': 'birds',
      'img_tags': 'savanna,grassland,bird,watercolor,nature',
      'snippet':
      'মহারাষ্ট্রের সাভানা অঞ্চলে কৃত্রিম বনসৃজনের ফলে ভারতীয় কোর্সার ও টনি পিপিট পাখিদের বাসস্থান হারিয়ে যাওয়ার বৈজ্ঞানিক প্রমাণ...',
      'content':
      'ভারতের প্রাকৃতিক বাস্তুতন্ত্রে সাভানা ও উন্মুক্ত ঘাসজমিকে বহু দশক ধরে ব্রিটিশ ঔপনিবেশিক আমলের অবৈজ্ঞানিক ধারণা অনুযায়ী অনাবাদি বা পতিত জমি (Wastelands) হিসেবে গণ্য করে অবাধ বৃক্ষরোপণ করা হয়েছে। ঔপনিবেশিক অরণ্য আইন ও উত্তর-স্বাধীনতা কালে বন দপ্তরের লক্ষ্য ছিল যেখানেই ফাঁকা জায়গা পাওয়া যাবে সেখানেই চারা লাগানো। এর ফলে ভারতের প্রায় ১০ শতাংশ এলাকা জুড়ে বিস্তৃত সাভানা বাস্তুতন্ত্রের মারাত্মক ক্ষতি হয়েছে।\n\nসম্প্রতি পরিবেশ বিজ্ঞানী সিমরিন সিরুর পরিচালিত বিস্তারিত মাঠপর্যায়ের গবেষণায় স্পষ্ট প্রমাণিত হয়েছে যে, মহারাষ্ট্রের প্রাচীন সাভানা ঘাসজমিতে গ্লিরিসিডিয়ার (Gliricidia) মতো বিদেশি প্রজাতির গাছের কৃত্রিম বাগান গড়ে তোলার ফলে ঘাসজমির নিজস্ব বিশেষজ্ঞ পাখি প্রজাতি মারাত্মকভাবে বাস্তুচ্যুত হচ্ছে। বিশেষ করে ভারতীয় কোর্সার (Indian Courser) এবং টনি পিপিট (Tawny Pipit)-এর মতো পাখিরা, যারা মূলত খোলা প্রান্তরে বাসা বাঁধে ও খাবার খোঁজে, তারা লম্বা গাছের আধিক্যের ফলে শিকারী পাখিদের ভয়ে ঘাসজমি ছেড়ে দিচ্ছে। বিজ্ঞানীদের মতে, অরণ্য মানেই শুধুমাত্র গাছ নয়; ঘাসজমির নিজস্ব বাস্তুতন্ত্র রক্ষা করা জৈববৈচিত্র্যের জন্য সমান গুরুত্বপূর্ণ।'
    },
    {
      'title': 'সুরক্ষিত অরণ্যের বাইরেই কারাকালের তিন-চতুর্থাংশ বাসভূমি',
      'source': 'Mongabay India',
      'source_url':
      'https://india.mongabay.com/2026/07/caracal-prefer-ravines-open-natural-ecosystems-over-protected-areas/',
      'date_str': '০৯ জুলাই, ২০২৬',
      'category': 'carnivore',
      'img_tags': 'caracal,wildcat,landscape,watercolor',
      'snippet':
      'রণথম্বোর-ধোলপুর অঞ্চলে চম্বলের গভীর গিরিখাত ও কাঁটাঝোপ কারাকালের অস্তিত্ব রক্ষার মূল চাবিকাঠি...',
      'content':
      'ভারতের অন্যতম রহস্যময়, ক্ষিপ্র ও চরম বিপন্ন বন্য মার্জার প্রজাতি কারাকালের (Caracal) ওপর ন্যাশনাল টাইগার কনজারভেশন অথরিটি (NTCA) ও ওয়াইল্ডলাইফ ইনস্টিটিউট অফ ইন্ডিয়ার (WII) গবেষণায় অত্যন্ত উদ্বেগজনক তথ্য উঠে এসেছে। একসময় মরুভূমি ও শুষ্ক অঞ্চলের ‘গরিবের চিতা’ নামে পরিচিত এই প্রাণীটি এখন রাজস্থান ও গুজরাটের মাত্র কয়েকটি পকেটে সীমাবদ্ধ।\n\nগবেষণায় দেখা গেছে, কারাকালের মোট বাসভূমির প্রায় ৭৫ শতাংশই অবস্থিত সুরক্ষিত অভয়ারণ্য বা জাতীয় উদ্যানের সীমানার বাইরে। রাজস্থানের রণথম্বোর ও ধোলপুর অঞ্চলে চম্বল নদীর গভীর গিরিখাত (Ravines) এবং সংলগ্ন কাঁটাঝোপ কারাকালের অস্তিত্ব রক্ষার জন্য সবচেয়ে নিরাপদ আশ্রয়। দুর্ভাগ্যবশত, এই এলাকাগুলি সুরক্ষিত না হওয়ায় খনি শিল্প, নগরায়ণ এবং অবাধ পশুচারণের ফলে কারাকালের বিচরণক্ষেত্র ক্রমশ সংকুচিত হচ্ছে। বিজ্ঞানীদের মতে, যদি এখনই চম্বলের এই দুর্গম গিরিখাতগুলিকে সংরক্ষিত অঞ্চল হিসেবে ঘোষণা না করা হয়, তবে এদেশ থেকে কারাকাল চিরতরে বিলুপ্ত হয়ে যেতে পারে।'
    },
    {
      'title': 'মেঘালয়ের খাসি পাহাড়ে শিকারী কলসি উদ্ভিদের বিবর্তন ও সংকট',
      'source': 'Sanctuary Nature Foundation',
      'source_url':
      'https://www.sanctuarynaturefoundation.org/article/predatory-pitcher-plants',
      'date_str': 'ফেব্রুয়ারি ২০২৪',
      'category': 'flora',
      'img_tags': 'pitcherplant,botanical,jungle,watercolor',
      'snippet':
      'ভারতের একমাত্র পতঙ্গভুক কলসি উদ্ভিদ নেপেন্থেস খাসিয়ানার অতিবেগুনি আলোর ফাঁদ ও ঔষধি গুরুত্ব...',
      'content':
      'মেঘালয়ের খাসি, জয়ন্তীয়া ও দক্ষিণ গারো পাহাড়ের অত্যন্ত পুষ্টিহীন, অম্লীয় ও নাইট্রোজেন-ঘাটতিযুক্ত পাহাড়ি মাটিতে টিকে থাকতে লক্ষ কোটি বছরের বিবর্তনে পতঙ্গ শিকারের অদ্ভুত রূপান্তর ঘটিয়েছে ভারতের একমাত্র আদিম কলসি উদ্ভিদ নেপেন্থেস খাসিয়ানা (Nepenthes khasiana)। স্থানীয় খাসি ভাষায় একে বলা হয় ‘তিউ-রাকত’ (Tiew-Rakot) বা রাক্ষুসে ফুল।\n\nবিস্ময়কর তথ্য এই যে, এই কলসি উদ্ভিদের মুখের চারপাশের রিং বা পেরিস্টোম থেকে অতিবেগুনি আলো (UV Light) নির্গত হয়, যা রাতের অন্ধকারে পতঙ্গদের সম্মোহিত করে কাছে টেনে আনে। কলসির ভেতর থাকা পিচ্ছিল পদার্থ ও পাচক রসের গোলকধাঁধায় একবার পড়লে পতঙ্গের আর নিস্তার থাকে না। বর্তমানে বাসভূমি ধ্বংস এবং স্থানীয় মানুষ কর্তৃক ভেষজ ঔষধ হিসেবে অতিরিক্ত সংগ্রহের ফলে এই বিস্ময়কর উদ্ভিদটি এখন বিলুপ্তির দ্বারপ্রান্তে। মেঘালয়ের দুর্গম পাহাড়ের কিছু অংশে আজও এরা টিকে আছে বিবর্তনের এক জীবন্ত সাক্ষী হিসেবে।'
    },
    {
      'title': 'শিল্পীদের তুলি ও প্রকৃতি সংরক্ষণের সুপ্রাচীন আত্মিক বন্ধন',
      'source': 'Sanctuary Nature Foundation',
      'source_url':
      'https://www.sanctuarynaturefoundation.org/article/your-canvas-awaits',
      'date_str': '১৮ জুন, ২০২৬',
      'category': 'art_eco',
      'img_tags': 'cave-painting,canvas,art,watercolor',
      'snippet':
      'প্রাচীন গুহাচিত্র থেকে আধুনিক তথ্যচিত্র: শিল্প কীভাবে সংরক্ষণ আন্দোলনের মূল চালিকাশক্তি...',
      'content':
      'মানুষ ও বন্যপ্রাণের নিবিড় সহাবস্থানের ইতিহাস প্রায় ৫১ হাজার বছর আগের গুহাচিত্র থেকেই শিল্পের মাধ্যমে মূর্ত হয়ে উঠেছে। স্পেনের আলতামিরা গুহা থেকে শুরু করে মধ্যপ্রদেশের ভীমবেটকা—সবখানেই আদিম মানুষের শিল্প ভাবনায় বন্যপ্রাণীরা ছিল অপরিহার্য অংশ। আধুনিক যুগেও আলোকচিত্র বা বৈজ্ঞানিক তথ্যের চেয়ে শিল্পীর আঁকা একটি ছবি মানুষের হৃদয়ে অধিক সহমর্মিতা জাগাতে সক্ষম।\n\nজন জেমস অডুবন (John James Audubon)-এর ‘বার্ডস অফ আমেরিকা’ ছিল বিশ্বের অন্যতম প্রথম প্রয়াস যেখানে শিল্পের মাধ্যমে জৈববৈচিত্র্য নথিভুক্ত করা হয়েছিল। শিল্পীরা শুধুমাত্র দৃশ্য ফুটিয়ে তোলেন না, তাঁরা প্রকৃতির বিপন্নতাকে সাধারণ মানুষের সামনে দৃশ্যমান করে তোলেন। বন্যপ্রাণ সংরক্ষণ আন্দোলন আজ শুধুমাত্র বিজ্ঞানীদের গবেষণাগারে সীমাবদ্ধ নেই, তা ছড়িয়ে পড়েছে শিল্পীর তুলি আর ক্যানভাসে, যা মানুষের মনে প্রকৃতির প্রতি এক গভীর আত্মিক দায়বদ্ধতা তৈরি করে।'
    },
    {
      'title': 'পরিবেশ রক্ষার লড়াইয়ে বিশ্ববরেণ্য অগ্রদূতদের ঐতিহাসিক পদচিহ্ন',
      'source': 'Sanctuary Nature Foundation',
      'source_url':
      'https://www.sanctuarynaturefoundation.org/article/on-the-shoulders-of-giants',
      'date_str': '০২ মে, ২০২৬',
      'category': 'history',
      'img_tags': 'old-manuscript,history,nature,watercolor',
      'snippet':
      'র‌্যাচেল কার্সনের সাইলেন্ট স্প্রিং থেকে সুন্দরলাল বহুগুণার চিপকো আন্দোলন: এক অবিস্মরণীয় বিপ্লব...',
      'content':
      'আধুনিক পৃথিবীর পরিবেশ সংরক্ষণ আন্দোলন নিছক সরকারি সিদ্ধান্ত নয়, বরং কয়েকজন নির্ভীক বিজ্ঞানপ্রেমী ও সমাজসংস্কারকের আজীবন সংগ্রামের ওপর ভিত্তি করে গড়ে উঠেছে। ১৯৬২ সালে সমুদ্র বিজ্ঞানী র‌্যাচেল কার্সনের যুগান্তকারী বই ‘সাইলেন্ট স্প্রিং’ (Silent Spring) মার্কিন যুক্তরাষ্ট্রে ডিডিটি-র মতো বিষাক্ত কীটনাশকের বিরুদ্ধে জনমত গঠন করেছিল, যা আধুনিক পরিবেশবাদের জন্ম দেয়।\n\nএকইভাবে ভারতে সত্তরের দশকে গাড়োয়াল হিমালয়ে যখন নির্বিচারে গাছ কাটা শুরু হয়, তখন স্থানীয় গ্রামবাসীরা গাছকে জড়িয়ে ধরে রক্ষা করার যে ‘চিপকো আন্দোলন’ (Chipko Movement) শুরু করেছিলেন, তার নেতৃত্ব দিয়েছিলেন সুন্দরলাল বহুগুণা ও গৌরা দেবী। তাঁদের এই আন্দোলন শুধুমাত্র গাছ বাঁচানোর লড়াই ছিল না, তা ছিল মানুষের জীবন ও জীবিকার সাথে অরণ্যের আত্মিক সম্পর্কের এক ঐতিহাসিক ঘোষণা। এই সব অগ্রদূতদের কাঁধে ভর করেই আজ আমরা এক টেকসই পৃথিবীর স্বপ্ন দেখতে পারছি।'
    }
  ];

  List<Map<String, dynamic>> _visibleNews = [];
  late final PageController _newsPageController;
  int _currentNewsPage = 0;

  final List<Map<String, dynamic>> _liveNews = [];
  bool _loadingLiveNews = false;

  @override
  void initState() {
    super.initState();
    _newsPageController = PageController(viewportFraction: 0.85);
    _refreshVisibleNewsWindow();
    loadData();
    _loadContinueReadingSession();
    _startAutoNewsShufflingTimer();
    
    // Fetch news and trigger audio alert after the first frame.
    // Small delay for audio ensures the native side is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLiveNews();
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _triggerAnimalAcousticAlert();
      });
    });
  }

  @override
  void dispose() {
    _autoShuffleTimer?.cancel();
    _newsPageController.dispose();
    _notificationAudioPlayer.dispose();
    super.dispose();
  }

  void _refreshVisibleNewsWindow() {
    // Shuffles the freshly fetched live news with our curated fallback pool
    // to give a unique mix every time the app launches or refreshes.
    // IMPORTANT: copy every item into a fresh mutable map. _masterNewsPool is
    // `static const`, so its maps are UNMODIFIABLE — handing one to
    // NewsDetailScreen crashed with "Cannot modify unmodifiable map" when the
    // on-open translation tried item['title'] = headline.
    final combined = <Map<String, dynamic>>[
      ..._liveNews.map((e) => Map<String, dynamic>.from(e)),
      ..._masterNewsPool.map((e) => Map<String, dynamic>.from(e)),
    ]..shuffle();

    if (!mounted) {
      _visibleNews = combined.take(5).toList();
      return;
    }
    setState(() {
      _visibleNews = combined.take(5).toList();
      _currentNewsPage = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_newsPageController.hasClients) return;
      _newsPageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _startAutoNewsShufflingTimer() {
    _autoShuffleTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _triggerAnimalAcousticAlert();
      _fetchLiveNews().then((_) => _refreshVisibleNewsWindow());
    });
  }

  /// Pulls the latest wildlife articles from the shared Supabase database.
  /// These articles are pre-processed and translated by the server-side
  /// background worker.
  Future<void> _fetchLiveNews() async {
    if (_loadingLiveNews) return;
    _loadingLiveNews = true;

    try {
      // Step 1: Fetch the news articles
      final newsRes = await supabase
          .from('wildlife_news')
          .select()
          .order('created_at', ascending: false)
          .limit(15);

      if (newsRes.isNotEmpty) {
        final List<Map<String, dynamic>> newsItems =
            List<Map<String, dynamic>>.from(newsRes);

        // Step 1b: Scrub homepage-card noise (leading counters, category
        // prefixes' artifacts, " — Source" suffixes) so cards and the free
        // translation fallback never work off polluted titles.
        for (final item in newsItems) {
          item['title'] = _tidyNewsTitle(item['title']?.toString() ?? '');
          item['snippet'] = _tidyNewsTitle(item['snippet']?.toString() ?? '');
        }

        // Step 2: Fetch any existing translations for these URLs
        final urls = newsItems.map((it) => it['source_url'].toString()).toList();
        final transRes = await supabase
            .from('wildlife_news_translations')
            .select('source_url, headline, dek, body')
            .inFilter('source_url', urls);

        final translationsMap = {
          for (var t in (transRes as List))
            if (_hasUsableBengaliBody(t['body'])) t['source_url'].toString(): t
        };

        // Step 3: Merge them. Only trust entries that really are Bengali,
        // and scrub any AI scaffolding ("Para 1", word-count notes) that
        // may have leaked into older cached rows.
        for (final item in newsItems) {
          final url = item['source_url'].toString();
          final cache = translationsMap[url];
          if (cache == null) continue;
          final headline =
              _sanitizeBengaliText((cache['headline'] ?? '').toString());
          final dek = _sanitizeBengaliText((cache['dek'] ?? '').toString());
          final body =
              _collapseToOneParagraph(_sanitizeBengaliText((cache['body'] ?? '').toString()));
          if (headline.isNotEmpty && _containsBengali(headline)) {
            item['title'] = headline;
          }
          if (dek.isNotEmpty && _containsBengali(dek)) item['snippet'] = dek;
          if (_hasUsableBengaliBody(body)) item['content'] = body;
        }

        if (mounted) {
          setState(() {
            _liveNews
              ..clear()
              ..addAll(newsItems);
          });
          
          // Background process for any still missing translations
          final missing = newsItems.where((it) => 
            !translationsMap.containsKey(it['source_url'].toString())).toList();
          if (missing.isNotEmpty) {
            unawaited(_translateFreshToBengali(missing));
          }
        }
      }
    } catch (e) {
      debugPrint('[News] robust fetch failed: $e');
    } finally {
      _loadingLiveNews = false;
    }
  }

  static final Set<String> _bengaliTranslatedUrls = <String>{};

  static final RegExp _bengaliCharRe = RegExp(r'[\u0980-\u09FF]');
  static final RegExp _thinkBlockRe =
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false);
  static final RegExp _openThinkRe =
      RegExp(r'<think>[\s\S]*$', caseSensitive: false);

  /// Matches AI drafting scaffolding that leaks into cached editions even
  /// when mixed with Bengali words: "Para 1:", "~90 words.", "(~90 words)",
  /// "DEK refine:", "Body polish", "Final check ...", "I'll go with ...".
  static final RegExp _scaffoldLineRe = RegExp(
      r'^\s*(?:\(?para(?:graph)?\s*\d+\)?\s*[:.]|[~≈]?\s*\d+\s*words?\s*[.:]*$|'
      r'dek\s+(?:refine|alternative)|headline\s+(?:refine|alternative|options?)|'
      r'body\s+polish|final\s+check\b|word\s+count\s*(?:for|check)|'
      r"i'?ll\s+(?:go|use|pick|write)|let'?s\s|let me\s+(?:count|refine|polish|check)|"
      r'draft\s*\d+\s*[:.]|option\s*\d+\s*[:.])',
      multiLine: true,
      caseSensitive: false);

  /// Anywhere-in-text markers that unambiguously betray drafting commentary.
  static final RegExp _scaffoldAnywhereRe = RegExp(
      r'\bhmm\b|\balternative\s*:|\brefine\b|\boff-tone\b',
      caseSensitive: false);
  static final RegExp _inlineWordCountRe = RegExp(
      r'\s*\(\s*[~≈]?\s*\d+\s*(?:bengali\s+)?words?\s*[.:]?\s*\)',
      caseSensitive: false);

  /// True when text still carries visible drafting scaffolding after
  /// sanitisation. Such content must never be shown or treated as done.
  static bool _hasScaffolding(String text) {
    if (_scaffoldLineRe.hasMatch(text)) return true;
    if (_scaffoldAnywhereRe.hasMatch(text)) return true;
    if (RegExp(
            r'^\s*(?:para(?:graph)?\s*\d+|\d+\s*words?\b)',
            multiLine: true,
            caseSensitive: false)
        .hasMatch(text)) {
      return true;
    }
    return _inlineWordCountRe.hasMatch(text);
  }

  /// Strips homepage-card noise from scraped titles/snippets: leading digit
  /// counters ("0 3 Environment ..."), trailing arrows and duplicated
  /// " — Nature In Focus" <title> suffixes. Mirrors tidyTitle() in the
  /// refresh-wildlife-news edge function.
  static final RegExp _leadingTitleNoiseRe = RegExp(
      r'^[\s.,:;\-–—|#*]*(?:\d[\s.,:;\-–—&]*)+');
  static final RegExp _sourceSuffixRe = RegExp(r'\s+—\s+[A-Za-z][^—]{0,60}$');

  static String _tidyNewsTitle(String text) {
    var t = text.trim();
    if (t.isEmpty) return t;
    t = t.replaceAll(RegExp(r'[→»›]'), ' ');
    t = t.replaceFirst(_sourceSuffixRe, ' ');
    t = t.replaceFirst(_leadingTitleNoiseRe, '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// True when [text] actually contains Bengali script.
  static bool _containsBengali(String text) => _bengaliCharRe.hasMatch(text);

  /// Collapses an article body into ONE long continuous paragraph: every
  /// line break / blank-line run becomes a single space, so the report reads
  /// as one flowing paragraph instead of many gapped ones.
  static String _collapseToOneParagraph(String text) {
    return text
        .replaceAll(RegExp(r'\s*\n+\s*'), ' ')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  /// Removes AI drafting scaffolding that sometimes leaks into stored
  /// editorials: <think> blocks, "Para 1 (~65 words):" style labels,
  /// English/Bengali-mixed planning notes and any line carrying no Bengali
  /// script (English planning / word-count notes).
  static String _sanitizeBengaliText(String text) {
    var t = text.replaceAll(_thinkBlockRe, '').replaceAll(_openThinkRe, '');
    if (!_containsBengali(t)) return t.trim();
    final kept = t.split('\n').where((line) {
      final l = line.trim();
      if (l.isEmpty) return true;
      // Drop short meta-commentary lines ("Para 2:", "DEK refine: ...") even
      // when they contain Bengali words, but never a long real paragraph.
      if (l.length <= 220 && _scaffoldLineRe.hasMatch(l)) return false;
      return _containsBengali(l);
    }).toList();
    return kept
        .join('\n')
        .replaceAll(_inlineWordCountRe, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static bool _hasUsableBengaliBody(dynamic value) {
    final text = _sanitizeBengaliText(value?.toString() ?? '');
    if (text.isEmpty || !_containsBengali(text)) return false;
    if (_hasScaffolding(text)) return false;
    return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length >= 280;
  }

  /// Rewrites freshly fetched English articles into Bengali (AI editorial
  /// via the bengali-news-editor edge function, with a free-translation
  /// fallback). Runs in the background; clips update as each article
  /// completes.
  Future<void> _translateFreshToBengali(
      List<Map<String, dynamic>> items) async {
    for (final item in items) {
      final changed = await _ensureBengaliEdition(item);
      if (changed && mounted) setState(() {});
      // Pacing between articles keeps us well under rate limits.
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  /// Resolves the Bengali edition (headline / dek / body) for one article:
  /// shared Supabase cache → AI editorial edge function → free translation
  /// fallback. Mutates [item] in place and is safe to call from any screen
  /// (no setState inside). Returns true when a Bengali edition is present
  /// on the item afterwards. Pass [force] to retry an article that already
  /// failed earlier in this session.
  static Future<bool> _ensureBengaliEdition(
    Map<String, dynamic> item, {
    bool force = false,
  }) async {
    final url = (item['source_url'] ?? '').toString();
    if (url.isEmpty) return false;
    if (!force && !_bengaliTranslatedUrls.add(url)) {
      return _containsBengali((item['title'] ?? '').toString());
    }

    debugPrint('[News] translating: $url');

    // 1) Shared Supabase cache first - avoids re-paying AI tokens on
    //    every launch and keeps wording identical across all users.
    try {
      final cached = await supabase
          .from('wildlife_news_translations')
          .select('headline, dek, body')
          .eq('source_url', url)
          .maybeSingle();
      final headline =
          _sanitizeBengaliText(cached?['headline']?.toString() ?? '');
      final body = _collapseToOneParagraph(
          _sanitizeBengaliText(cached?['body']?.toString() ?? ''));
      if (headline.isNotEmpty && _hasUsableBengaliBody(body)) {
        item['title'] = headline;
        final dek = _sanitizeBengaliText(cached?['dek']?.toString() ?? '');
        if (dek.isNotEmpty) item['snippet'] = dek;
        if (body.isNotEmpty) item['content'] = body;
        debugPrint('[News] CACHED: ${item['title']}');
        return true;
      }
    } catch (e) {
      debugPrint('[News] cache lookup failed (continuing): $e');
    }

      String articleText =
          (item['content'] ?? '').toString().isNotEmpty
              ? item['content'].toString()
              : (item['snippet'] ?? '').toString();

      if (articleText.length < 500) {
        // Source text too short — pull the full article SERVER-SIDE via the
        // fetch-news-article edge function. This handles bot-blocked /
        // JavaScript-heavy sites (e.g. Sanctuary) and extracts clean body
        // text, unlike naive client-side tag stripping.
        try {
          final articleRes = await supabase.functions.invoke(
            'fetch-news-article',
            body: {'url': url},
          );
          final articleData = articleRes.data;
          if (articleData is Map &&
              articleData['success'] == true &&
              (articleData['articleText'] ?? '').toString().length >= 500) {
            articleText = articleData['articleText'].toString();
          }
          // Bonus: adopt the real thumbnail image if we don't have one yet.
          if (articleData is Map &&
              (item['image_url'] ?? '').toString().isEmpty &&
              (articleData['primaryImage'] ?? '').toString().isNotEmpty) {
            item['image_url'] = articleData['primaryImage'].toString();
          }
        } catch (e) {
          debugPrint('[News] fetch-news-article invoke failed for $url: $e');
        }
        if (articleText.length < 500) {
          try {
            final res = await http
                .get(Uri.parse(url))
                .timeout(const Duration(seconds: 20));
            if (res.statusCode == 200) {
              final pageText = _stripHtmlTags(res.body);
              if (pageText.length > 6000) {
                articleText = pageText.substring(0, 6000);
              } else if (pageText.length > articleText.length) {
                articleText = pageText;
              }
            }
          } catch (_) {}
        }
      }
      if (articleText.isEmpty) {
        debugPrint('[News] SKIPPED (no article text available): $url');
        return false;
      }

      debugPrint(
          '[News] editorialising ${articleText.length} chars: $url');

      // 2) AI EDITORIAL REWRITE (OpenRouter).
      //    Invokes the shared Supabase Edge Function to generate a polished
      //    Bengali news summary. This also persists the result to the
      //    shared cache for other users.
      try {
        final res = await supabase.functions.invoke(
          'bengali-news-editor',
          body: {
            'sourceTitle': item['title'],
            'sourceUrl': url,
            'articleText': articleText,
          },
        );
        final data = res.data;
        if (data is Map && data['success'] == true) {
          final headline =
              _sanitizeBengaliText(data['headline']?.toString() ?? '');
          final dek = _sanitizeBengaliText(data['dek']?.toString() ?? '');
          final body = _collapseToOneParagraph(
              _sanitizeBengaliText(data['body']?.toString() ?? ''));
          if (headline.isNotEmpty && _containsBengali(headline) &&
              _hasUsableBengaliBody(body)) {
            item['title'] = headline;
            if (dek.isNotEmpty && _containsBengali(dek)) {
              item['snippet'] = dek;
            }
            item['content'] = body;
            debugPrint('[News] DONE (AI): $headline');
            return true;
          }
        }
      } catch (e) {
        debugPrint('[News] bengali-news-editor failed for $url: $e');
      }

      // 3) FALLBACK: ZERO-TOKEN TRANSLATION.
      //    Uses Google Translate's public gtx endpoint if AI fails.
      final headline =
          await _freeTranslateToBengali((item['title'] ?? '').toString());
      if (headline == null || headline.isEmpty) {
        debugPrint(
            '[News] translation unavailable right now, will retry later');
        return false;
      }

      final dek =
          await _freeTranslateToBengali(_firstSentences(articleText, 420)) ??
              '';
      final fallbackBody = await _freeTranslateChunked(
            articleText.length > 4000
                ? articleText.substring(0, 4000)
                : articleText,
          ) ??
          '';
      // One long flowing paragraph, never many gapped ones.
      final body = _collapseToOneParagraph(fallbackBody);

      item['title'] = headline;
      if (dek.isNotEmpty) item['snippet'] = dek;
      if (body.isNotEmpty) item['content'] = body;
      debugPrint('[News] DONE (fallback free): $headline');

      // 4) Persist fallback to the shared cache.
      try {
        await supabase.from('wildlife_news_translations').upsert({
          'source_url': url,
          'headline': headline,
          'dek': dek,
          'body': body,
        });
      } catch (e) {
        debugPrint('[News] cache write failed (non-fatal): $e');
      }

      return true;
  }

  /// Translates English text to Bengali using Google Translate's public
  /// gtx endpoint (free, keyless). Returns null on any failure. Retries
  /// with exponential backoff when rate-limited (HTTP 429).
  static Future<String?> _freeTranslateToBengali(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.parse(
            'https://translate.googleapis.com/translate_a/single')
        .replace(queryParameters: <String, String>{
      'client': 'gtx',
      'sl': 'en',
      'tl': 'bn',
      'dt': 't',
      'q': trimmed,
    });
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        // Back off 1s, 2s, 4s before retries (rate-limit friendly).
        await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          if (res.statusCode == 429 || res.statusCode >= 500) continue;
          debugPrint(
              '[News] translate HTTP ${res.statusCode}, giving up');
          return null;
        }
        final data = jsonDecode(res.body);
        if (data is! List || data.isEmpty || data[0] is! List) return null;
        final out = StringBuffer();
        for (final part in data[0]) {
          if (part is List && part.isNotEmpty) {
            out.write(part[0]?.toString() ?? '');
          }
        }
        final result = out.toString().trim();
        return result.isEmpty ? null : result;
      } catch (_) {
        // Network hiccup - one quiet retry via the loop.
      }
    }
    debugPrint('[News] translation failed after retries (rate limit?)');
    return null;
  }

  /// Trims [text] to roughly its first [maxChars] characters without
  /// cutting a sentence in half.
  static String _firstSentences(String text, int maxChars) {
    final t = text.trim();
    if (t.length <= maxChars) return t;
    var cut = t.substring(0, maxChars);
    final dot = cut.lastIndexOf('. ');
    if (dot > maxChars ~/ 2) cut = cut.substring(0, dot + 1);
    return cut;
  }

  /// Translates longer text in safe-sized chunks (GET query limits),
  /// joining paragraph breaks between pieces.
  static Future<String?> _freeTranslateChunked(String text) async {
    const chunkSize = 1100;
    final chunks = <String>[];
    var remaining = text.trim();
    while (remaining.isNotEmpty) {
      if (remaining.length <= chunkSize) {
        chunks.add(remaining);
        break;
      }
      var splitAt = remaining.lastIndexOf(' ', chunkSize);
      if (splitAt < chunkSize ~/ 2) splitAt = chunkSize;
      chunks.add(remaining.substring(0, splitAt));
      remaining = remaining.substring(splitAt).trim();
    }
    final out = StringBuffer();
    var first = true;
    for (final chunk in chunks) {
      if (!first) {
        // Gentle pacing so the public endpoint does not throttle us.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      first = false;
      final piece = await _freeTranslateToBengali(chunk);
      if (piece == null) {
        return out.isEmpty ? null : out.toString().trim();
      }
      if (out.isNotEmpty) out.write('\n\n');
      out.write(piece);
    }
    final result = out.toString().trim();
    return result.isEmpty ? null : result;
  }



  static String _stripHtmlTags(String input) {
    var text = input.replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
    text = text.replaceAll(
        RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8217;', '\u2019')
        .replaceAll('&#8216;', '\u2018')
        .replaceAll('&#8220;', '\u201C')
        .replaceAll('&#8221;', '\u201D')
        .replaceAll('&#8230;', '\u2026')
        .replaceAll('&hellip;', '\u2026')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ');
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.tryParse(m.group(1)!) ?? 32));
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }





  Future<void> _triggerAnimalAcousticAlert() async {
    final random = math.Random();
    int newIndex;
    do {
      newIndex = random.nextInt(_animalAudioAssets.length);
    } while (
    newIndex == _lastAnimalSoundIndex && _animalAudioAssets.length > 1);

    _lastAnimalSoundIndex = newIndex;

    try {
      await _notificationAudioPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _notificationAudioPlayer.stop();
      await _notificationAudioPlayer
          .play(AssetSource(_animalAudioAssets[newIndex]));
    } catch (_) {}
  }

  Future<void> _loadContinueReadingSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastReadMagId = prefs.getString('last_read_mag_id');
      _lastReadTitle = prefs.getString('last_read_title');
      _lastReadPage = prefs.getInt('last_read_page') ?? 0;
      _lastReadTotalPages = prefs.getInt('last_read_total_pages') ?? 0;
    });
  }

  Future<void> loadData() async {
    try {
      final res = await supabase
          .from('magazines')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _issues = List<Map<String, dynamic>>.from(res);
        });
        await _loadContinueReadingSession();
      }
      // Also refresh news when loadData is called (e.g. from the refresh button).
      await _fetchLiveNews();
      _refreshVisibleNewsWindow();
    } catch (_) {}
  }

  Widget _buildNewsClipImage(Map<String, dynamic> item) {
    return _WatercolorNewsImage(
      item: item,
      fallbackPainter: _WatercolorNewsPainter(
        title: (item['title'] ?? '').toString(),
        category: (item['category'] ?? '').toString().toLowerCase(),
        seed: (item['title'] ?? '').toString().hashCode,
      ),
    );
  }

// -------------------------------------------------------------
// AUTOMATIC PHOTO -> WATERCOLOR NEWS IMAGE
// No AI image-generation API is used here.
// The source photograph is fetched from the article and rendered
// locally with a warm paper wash, pigment softening and paper grain.
// -------------------------------------------------------------

  Widget _buildNewsTextPanel(Map<String, dynamic> item, bool compact) {
    final TextStyle titleStyle = TextStyle(
      fontSize: compact ? 17 : 22,
      height: 1.08,
      fontWeight: FontWeight.w800,
      color: const Color(0xFF382B25),
    );
    final TextStyle snippetStyle = TextStyle(
      fontSize: compact ? 10 : 11,
      height: 1.28,
      color: const Color(0xFF5E5A53),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF3EFE6),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PaperTexturePainter(seed: item['title'].hashCode),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 26,
              compact ? 14 : 20,
              compact ? 16 : 38,
              compact ? 12 : 18,
            ),
            child: LayoutBuilder(
              builder: (context, panelConstraints) {
                return SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: panelConstraints.maxHeight,
                    ),
                    child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB52B18),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          item['source']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item['date_str']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF746E66),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item['title']?.toString() ?? '',
                  maxLines: compact ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 8),
                Text(
                  item['snippet']?.toString() ?? '',
                  maxLines: compact ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: snippetStyle,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB52B18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'পড়ুন',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
            );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF00E676),
      onRefresh: () async {
        await loadData();
        await _fetchLiveNews();
        _refreshVisibleNewsWindow();
        await _triggerAnimalAcousticAlert();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          if (_lastReadMagId != null && _lastReadTotalPages > 0) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history_edu_rounded,
                          color: Color(0xFF00E676), size: 20),
                      SizedBox(width: 8),
                      Text('Continue Reading',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 28),
                    child: Text('(পড়া জারি রাখুন)',
                        style:
                        TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF142419),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 65,
                    decoration: BoxDecoration(
                        color: const Color(0xFF1E2E23),
                        borderRadius: BorderRadius.circular(6)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: CachedNetworkImage(
                        imageUrl: supabase.storage
                            .from('magazine_pages')
                            .getPublicUrl('$_lastReadMagId/page_1.jpg'),
                        fit: BoxFit.cover,
                        errorWidget: (c, u, e) => const Icon(
                            Icons.menu_book_rounded,
                            color: Color(0xFF00E676),
                            size: 26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_lastReadTitle ?? 'eআরণ্যক',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                            'Page ${_lastReadPage + 1} / $_lastReadTotalPages (${((_lastReadPage + 1) / _lastReadTotalPages * 100).round()}% Completed)',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF81C784))),
                        Text(
                          '(পৃষ্ঠা ${_lastReadPage + 1} / $_lastReadTotalPages)',
                          style:
                          const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              value: (_lastReadPage + 1) / _lastReadTotalPages,
                              minHeight: 5,
                              backgroundColor: Colors.white12,
                              color: const Color(0xFF00E676)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProtectedReaderScreen(
                              magazineId: _lastReadMagId!,
                              title: _lastReadTitle ?? 'eআরণ্যক',
                              userEmail: widget.userEmail,
                              initialPage: _lastReadPage),
                        ),
                      ).then((_) => _loadContinueReadingSession());
                    },
                    child: const Text('Resume (চালিয়ে যান)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bolt, color: Color(0xFF00E676), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Current Happenings & Wildlife News',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(left: 28),
                  child: Text(
                      '(চলতি ঘটনা ও বন্যপ্রাণ বার্তা - প্রতি ২ মিনিটে ৫টি নির্বাচিত খবর)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 12),
          SizedBox(
            height: 292,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _newsPageController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _visibleNews.length,
                      onPageChanged: (index) {
                        if (mounted) {
                          setState(() {
                            _currentNewsPage = index;
                          });
                        }
                      },
                      itemBuilder: (context, index) {
                        final item = _visibleNews[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            margin: EdgeInsets.zero,
                            color: const Color(0xFFF2EEE3),
                            elevation: 7,
                            shadowColor: Colors.black54,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        NewsDetailScreen(newsItem: item),
                                  ),
                                );
                              },
                              child: LayoutBuilder(
                                builder: (context, cardConstraints) {
                                  final bool compact =
                                      cardConstraints.maxWidth < 600;
                                  final double artFlex = compact ? 1 : 62;
                                  final double textFlex = compact ? 1 : 38;
                                  return Flex(
                                    direction: compact
                                        ? Axis.vertical
                                        : Axis.horizontal,
                                    children: [
                                      Expanded(
                                        flex: compact ? 1 : artFlex.toInt(),
                                        child: ClipRect(
                                          child: _buildNewsClipImage(item),
                                        ),
                                      ),
                                      Expanded(
                                        flex: compact ? 1 : textFlex.toInt(),
                                        child:
                                        _buildNewsTextPanel(item, compact),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_visibleNews.length > 1)
                      Positioned(
                        left: 16,
                        top: 0,
                        bottom: 30,
                        child: Center(
                          child: Material(
                            color: const Color(0xFFF7F3E8)
                                .withValues(alpha: 0.92),
                            elevation: 3,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                final prev = (_currentNewsPage - 1 +
                                        _visibleNews.length) %
                                    _visibleNews.length;
                                _newsPageController.animateToPage(
                                  prev,
                                  duration:
                                      const Duration(milliseconds: 380),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                              child: const SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: Color(0xFF1B241D),
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_visibleNews.length > 1)
                      Positioned(
                        right: 16,
                        top: 0,
                        bottom: 30,
                        child: Center(
                          child: Material(
                            color:
                            const Color(0xFFF7F3E8).withValues(alpha: 0.92),
                            elevation: 3,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                final next = (_currentNewsPage + 1) %
                                    _visibleNews.length;
                                _newsPageController.animateToPage(
                                  next,
                                  duration: const Duration(milliseconds: 380),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                              child: const SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Color(0xFF1B241D),
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_visibleNews.length > 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _visibleNews.length,
                                (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: index == _currentNewsPage ? 18 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: index == _currentNewsPage
                                    ? const Color(0xFF1A201A)
                                    : const Color(0xFF8A8B86),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          if (_issues.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Latest Release',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Text('(সদ্য প্রকাশিত সংখ্যা)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                  color: const Color(0xFF18221B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 110,
                      height: 155,
                      decoration: BoxDecoration(
                          color: const Color(0xFF1E2E23),
                          borderRadius: BorderRadius.circular(8)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: CachedNetworkImage(
                          imageUrl: supabase.storage
                              .from('magazine_pages')
                              .getPublicUrl(
                              '${_issues.first['id']}/page_1.jpg'),
                          fit: BoxFit.cover,
                          placeholder: (c, u) => const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF00E676)))),
                          errorWidget: (c, u, e) => const Icon(
                              Icons.menu_book_rounded,
                              color: Color(0xFF00E676),
                              size: 42),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_issues.first['title'] ?? 'eআরণ্যক',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          const SizedBox(height: 6),
                          Text(
                              '${_issues.first['issue_date']} • Total ${_issues.first['total_pages']} Pages',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13)),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12)),
                            icon: const Icon(Icons.chrome_reader_mode_rounded,
                                size: 18),
                            label: const Text(
                                'Read Full Issue (সম্পূর্ণ সংখ্যাটি পড়ুন)',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProtectedReaderScreen(
                                      magazineId:
                                      _issues.first['id'].toString(),
                                      title: _issues.first['title'],
                                      userEmail: widget.userEmail),
                                ),
                              ).then((_) => _loadContinueReadingSession());
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 32, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('খেলার ছলে প্রকৃতি পাঠ',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text('(Nature Study through Games)',
                    style: TextStyle(fontSize: 10, color: Color(0xFF81C784))),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                _buildHomeGameTile(
                  context,
                  'আলোকচিত্র চেনা',
                  'Identify Photos',
                  'assets/images/identify_image.png',
                  const Color(0xFF2E7D32),
                  'photo',
                      () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                          const WildlifeQuizGame(type: 'photo'))),
                ),
                const SizedBox(width: 12),
                _buildHomeGameTile(
                  context,
                  'ডাক শুনে চেনা',
                  'Identify from Call',
                  'assets/images/identify_call.png',
                  const Color(0xFF00897B),
                  'audio',
                      () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                          const WildlifeQuizGame(type: 'audio'))),
                ),
                const SizedBox(width: 12),
                _buildHomeGameTile(
                  context,
                  'ইঙ্গিত বুঝে চেনা',
                  'Identify Hints',
                  'assets/images/identify_clue.png',
                  const Color(0xFF1B5E20),
                  'hint',
                      () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                          const WildlifeQuizGame(type: 'hint'))),
                ),
                const SizedBox(width: 12),
                _buildHomeGameTile(
                  context,
                  'টুকরো ছবি জোড়া',
                  'Scrambled Image',
                  'assets/images/zigshaw_puzzle.png',
                  const Color(0xFFE65100),
                  'puzzle',
                      () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ScrambledImageGame())),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 36, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'এখন আরণ্যক প্রকাশিত বই',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '(Aranyak Published Books)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF81C784),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const AranyakHardboundBookCard(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: InkWell(
              onTap: () => _openWhatsApp('9432569171'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF25D366).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WhatsAppLogo(size: 34),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '9432569171',
                          style: TextStyle(
                            color: Color(0xFF25D366),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '(বইটি কেনার জন্য যোগাযোগ করুন)',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildImportantLinksSection(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildImportantLinksSection() {
    const links = <Map<String, String>>[
      {
        'name': 'eBird',
        'url': 'https://ebird.org/',
        'logo': 'https://ebird.org/favicon.ico',
      },
      {
        'name': 'iNaturalist',
        'url': 'https://www.inaturalist.org/',
        'logo': 'https://www.inaturalist.org/favicon.ico',
      },
      {
        'name': 'Macaulay Library',
        'url': 'https://macaulaylibrary.org/',
        'logo': 'https://macaulaylibrary.org/favicon.ico',
      },
      {
        'name': 'Observation.org',
        'url': 'https://observation.org/',
        'logo': 'https://observation.org/favicon.ico',
      },
      {
        'name': 'Xeno-canto',
        'url': 'https://xeno-canto.org/',
        'logo': 'https://xeno-canto.org/favicon.ico',
      },
      {
        'name': 'Project Noah',
        'url': 'https://projectnoah.org/',
        'logo': 'https://projectnoah.org/favicon.ico',
      },
      {
        'name': 'BirdTrack',
        'url': 'https://www.birdtrack.net/',
        'logo': 'https://www.birdtrack.net/favicon.ico',
      },
      {
        'name': 'Ornitho',
        'url': 'https://www.ornitho.ch/',
        'logo': 'https://www.ornitho.ch/favicon.ico',
      },
      {
        'name': 'Mushroom Observer',
        'url': 'https://mushroomobserver.org/',
        'logo': 'https://mushroomobserver.org/favicon.ico',
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.travel_explore_rounded,
                color: Color(0xFF00E676),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Important Links',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            '(গুরুত্বপূর্ণ লিঙ্ক)',
            style: TextStyle(
              color: Color(0xFF81C784),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720
                  ? 5
                  : constraints.maxWidth >= 480
                  ? 4
                  : 3;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: links.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.94,
                ),
                itemBuilder: (context, index) {
                  final link = links[index];

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () async {
                        final uri = Uri.parse(link['url']!);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: Image.network(
                                link['logo']!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.public_rounded,
                                  color: Color(0xFF2E7D32),
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              link['name']!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHomeGameTile(BuildContext context, String bn, String en,
      String imageAsset, Color color, String type, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 145,
        height: 145,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: CustomPaint(
                  painter: GameDiagramPainter(type: type, color: color),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        imageAsset,
                        width: 110,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 110,
                            height: 80,
                            alignment: Alignment.center,
                            color: color.withValues(alpha: 0.15),
                            child: Icon(
                              Icons.image_not_supported_rounded,
                              size: 32,
                              color: color,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(bn,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.2,
                            shadows: [
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                  offset: Offset(0, 1))
                            ])),
                    const SizedBox(height: 2),
                    Text(en,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 2)
                            ])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(String phone) async {
    final url = 'https://wa.me/91$phone';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

class GameDiagramPainter extends CustomPainter {
  final String type;
  final Color color;
  GameDiagramPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    if (type == 'photo') {
      // Large Camera with gradient feel
      final rrect = RRect.fromLTRBR(
          w * 0.1, h * 0.25, w * 0.9, h * 0.8, const Radius.circular(10));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, paint);
      canvas.drawCircle(Offset(w * 0.5, h * 0.52), w * 0.22, paint);
      canvas.drawCircle(
          Offset(w * 0.5, h * 0.52), w * 0.12, paint..strokeWidth = 1.5);
      canvas.drawRect(
          Rect.fromLTWH(w * 0.7, h * 0.18, w * 0.12, h * 0.07), paint);
    } else if (type == 'hint') {
      // Large Mind/Idea
      final brainPath = Path()
        ..addOval(Rect.fromCircle(
            center: Offset(w * 0.5, h * 0.38), radius: w * 0.28));
      canvas.drawPath(brainPath, fillPaint);
      canvas.drawPath(brainPath, paint);

      final neckPath = Path()
        ..moveTo(w * 0.25, h * 0.9)
        ..quadraticBezierTo(w * 0.25, h * 0.65, w * 0.5, h * 0.65)
        ..quadraticBezierTo(w * 0.75, h * 0.65, w * 0.75, h * 0.9);
      canvas.drawPath(neckPath, paint);
    } else if (type == 'call') {
      // Concentric Sound Waves
      for (int i = 0; i < 4; i++) {
        final radius = w * 0.15 + i * (w * 0.18);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.15, h * 0.5), radius: radius),
          -0.7 * math.pi / 2,
          1.4 * math.pi / 2,
          false,
          paint..strokeWidth = 3.5 - (i * 0.5),
        );
      }
    } else {
      // Large Interlocking Jigsaw
      final piece = Path()
        ..moveTo(w * 0.15, h * 0.25)
        ..lineTo(w * 0.35, h * 0.25)
        ..arcToPoint(Offset(w * 0.55, h * 0.25),
            radius: Radius.circular(w * 0.1))
        ..lineTo(w * 0.75, h * 0.25)
        ..lineTo(w * 0.75, h * 0.45)
        ..arcToPoint(Offset(w * 0.75, h * 0.65),
            radius: Radius.circular(w * 0.1), clockwise: false)
        ..lineTo(w * 0.75, h * 0.85)
        ..lineTo(w * 0.15, h * 0.85)
        ..close();
      canvas.drawPath(piece, fillPaint);
      canvas.drawPath(piece, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// -------------------------------------------------------------
// 5. TAB 2: WOODEN BOOKSHELF
// -------------------------------------------------------------
class BookshelfScreen extends StatefulWidget {
  final String userEmail;
  const BookshelfScreen({super.key, required this.userEmail});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  List<Map<String, dynamic>> _magazines = [];
  Map<String, double> _progressMap = {};

  @override
  void initState() {
    super.initState();
    loadMagazines();
  }

  Future<void> loadMagazines() async {
    try {
      final res = await supabase
          .from('magazines')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _magazines = List<Map<String, dynamic>>.from(res);
        });
        await loadProgress();
      }
    } catch (_) {}
  }

  Future<void> loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, double> newProgress = {};
    for (final mag in _magazines) {
      final String magId = mag['id'].toString();
      final double p = prefs.getDouble('progress_$magId') ?? 0.0;
      newProgress[magId] = p;
    }
    if (mounted) {
      setState(() {
        _progressMap = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<List<Map<String, dynamic>>> shelves = [];
    for (int i = 0; i < _magazines.length; i += 2) {
      shelves.add(
        _magazines.sublist(
            i, (i + 2 > _magazines.length) ? _magazines.length : i + 2),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00E676),
      onRefresh: loadMagazines,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: shelves.length,
        itemBuilder: (context, shelfIndex) {
          final shelfItems = shelves[shelfIndex];

          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: shelfItems.map((mag) {
                  final coverUrl = supabase.storage
                      .from('magazine_pages')
                      .getPublicUrl('${mag['id']}/page_1.jpg');

                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProtectedReaderScreen(
                            magazineId: mag['id'],
                            title: mag['title'],
                            userEmail: widget.userEmail,
                          ),
                        ),
                      ).then((_) => loadProgress());
                    },
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 12,
                            offset: const Offset(4, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 195,
                            decoration: BoxDecoration(
                              color: const Color(0xFF142419),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                              border: Border.all(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.35)),
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: coverUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (c, u) => const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Color(0xFF00E676),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (c, u, e) => const Icon(
                                        Icons.menu_book_rounded,
                                        color: Color(0xFF00E676),
                                        size: 36),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      color: Colors.black87,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${mag['issue_date']}\n${mag['total_pages']} Pages',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          if ((_progressMap[
                                          mag['id'].toString()] ??
                                              0.0) >
                                              0.01) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: ClipRRect(
                                                    borderRadius:
                                                    BorderRadius.circular(
                                                        2),
                                                    child:
                                                    LinearProgressIndicator(
                                                      value: _progressMap[
                                                      mag['id']
                                                          .toString()]!,
                                                      minHeight: 2.5,
                                                      backgroundColor:
                                                      Colors.white12,
                                                      color: const Color(
                                                          0xFF00E676),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  '${(_progressMap[mag['id'].toString()]! * 100).round()}%',
                                                  style: const TextStyle(
                                                    fontSize: 8,
                                                    color: Color(0xFF00E676),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              Container(
                height: 18,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF8D5B34),
                      Color(0xFF5A381E),
                      Color(0xFF3B2211)
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------
// 6. TAB 3: WILDLIFE GALLERY
// -------------------------------------------------------------
class WildlifeGalleryScreen extends StatefulWidget {
  final String userEmail;
  final bool isAdmin;

  /// When opened from a notification, the exact storage path of the new
  /// photo so the app can scroll to it and show it full-screen.
  final String? initialStoragePath;

  const WildlifeGalleryScreen(
      {super.key,
        required this.userEmail,
        required this.isAdmin,
        this.initialStoragePath});

  @override
  State<WildlifeGalleryScreen> createState() => _WildlifeGalleryScreenState();
}

class _WildlifeGalleryScreenState extends State<WildlifeGalleryScreen> {
  final _titleCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();
  List<Map<String, dynamic>> _photos = [];

  @override
  void initState() {
    super.initState();
    loadPhotos();
  }

  /// After the gallery loads, if this screen was launched from a
  /// notification for a specific photo, find it and open it full-screen.
  void _openInitialPhoto() {
    final path = widget.initialStoragePath;
    if (path == null || path.isEmpty || !mounted) return;
    final index = _photos.indexWhere((p) =>
        (p['storage_path'] ?? '').toString() == path);
    if (index < 0) return; // Photo no longer exists — just show the grid.
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => FullscreenProtectedImageViewer(
                photos: _photos,
                initialIndex: index,
                userEmail: widget.userEmail)));
  }

  Future<void> loadPhotos() async {
    try {
      final res = await supabase
          .from('wildlife_gallery')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _photos = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
    if (widget.initialStoragePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialPhoto();
      });
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.single.bytes == null) {
      return;
    }

    try {
      final fileBytes = result.files.single.bytes!;
      final filename =
          '${DateTime.now().millisecondsSinceEpoch}_${result.files.single.name}';
      final storagePath = 'photos/$filename';

      await supabase.storage.from('wildlife_gallery').uploadBinary(
          storagePath, fileBytes,
          fileOptions:
          const FileOptions(contentType: 'image/jpeg', upsert: true));
      await supabase.from('wildlife_gallery').insert({
        'title': _titleCtrl.text.trim(),
        'caption': _captionCtrl.text.trim(),
        'storage_path': storagePath
      });

      // Notify all app users about the new gallery photo.
      unawaited(AppNotifier.notify(
        title: 'নতুন ছবি যোগ হয়েছে! (New Gallery Photo)',
        body: _titleCtrl.text.trim().isNotEmpty
            ? '${_titleCtrl.text.trim()} — দেখতে ট্যাপ করুন।'
            : 'বন্যপ্রাণের নতুন ছবি এসেছে — দেখতে ট্যাপ করুন।',
        data: {'type': 'gallery', 'id': storagePath},
      ));

      _titleCtrl.clear();
      _captionCtrl.clear();
      loadPhotos();
    } catch (_) {}
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Delete Photo'),
            Text('(ছবিটি মুছে ফেলা নিশ্চিত করুন)',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        content: const Text(
            'Are you sure you want to completely delete this gallery photo from servers?\n(আপনি কি নিশ্চিত যে ছবিটি সম্পূর্ণভাবে মুছে ফেলতে চান?)'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancel (বাতিল)',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx, true);
            },
            child: const Text('Delete (মুছে ফেলুন)'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      final storagePath = (photo['storage_path'] ?? '').toString();
      if (storagePath.isNotEmpty) {
        await supabase.storage
            .from('wildlife_gallery')
            .remove([storagePath]);
      }
      await supabase
          .from('wildlife_gallery')
          .delete()
          .eq('id', photo['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Photo deleted successfully / ছবিটি মুছে ফেলা হয়েছে।')),
        );
        loadPhotos();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error deleting photo / ছবিটি মুছে ফেলা যায়নি।')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF00E676),
      onRefresh: loadPhotos,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wildlife Gallery',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Text('(আরণ্যক চিত্রশালা)',
                      style: TextStyle(color: Color(0xFF81C784), fontSize: 12)),
                ],
              ),
              if (widget.isAdmin)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black),
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: const Text('Add Photo (ছবি যোগ করুন)',
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: _pickAndUploadPhoto,
                ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.82),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final signedUrl = supabase.storage
                  .from('wildlife_gallery')
                  .getPublicUrl(photo['storage_path']);

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => FullscreenProtectedImageViewer(
                                    photos: _photos,
                                    initialIndex: index,
                                    userEmail: widget.userEmail)));
                      },
                      child: CachedNetworkImage(
                          imageUrl: signedUrl, fit: BoxFit.cover),
                    ),
                    if (widget.isAdmin)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => _deletePhoto(photo),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: const Icon(Icons.delete_forever_rounded,
                                color: Colors.redAccent, size: 17),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 7. TAB 4: ADMIN DASHBOARD
// -------------------------------------------------------------
class AdminDashboardScreen extends StatefulWidget {
  final VoidCallback onUploadComplete;
  const AdminDashboardScreen({super.key, required this.onUploadComplete});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late String _startMonth;
  late String _endMonth;
  late String _selectedYear;

  final List<String> _months = [
    'January (জানুয়ারি)',
    'February (ফেব্রুয়ারি)',
    'March (মার্চ)',
    'April (এপ্রিল)',
    'May (মে)',
    'June (জুন)',
    'July (জুলাই)',
    'August (আগস্ট)',
    'September (সেপ্টেম্বর)',
    'October (অক্টোবর)',
    'November (নভেম্বর)',
    'December (ডিসেম্বর)'
  ];

  late final List<String> _years;
  List<Map<String, dynamic>> _adminMagazines = [];

  @override
  void initState() {
    super.initState();
    _startMonth = _months[0];
    _endMonth = _months[2];

    _years = List.generate(31, (index) {
      final y = 2030 - index;
      final banglaDigits = {
        '0': '০',
        '1': '১',
        '2': '২',
        '3': '৩',
        '4': '৪',
        '5': '৫',
        '6': '৬',
        '7': '৭',
        '8': '৮',
        '9': '৯'
      };
      final bStr =
      y.toString().split('').map((e) => banglaDigits[e] ?? e).join('');
      return '$y ($bStr)';
    });

    _selectedYear = _years.firstWhere(
          (y) => y.startsWith('2026'),
      orElse: () => _years.first,
    );

    _loadAdminMagazines();
  }

  Future<void> _loadAdminMagazines() async {
    try {
      final res = await supabase
          .from('magazines')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _adminMagazines = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  Future<void> _pickAndUploadMultiplePdfs() async {
    final issueString = '$_startMonth - $_endMonth $_selectedYear';
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: true);

    if (result == null || result.files.isEmpty) {
      return;
    }

    final selectedFiles = result.files.where((f) => f.bytes != null).toList();

    for (final file in selectedFiles) {
      UploadManager.instance.startUpload(
          file: file,
          issueString: issueString,
          onAllCompleted: () {
            _loadAdminMagazines();
            widget.onUploadComplete();
          });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF18221B),
          content: Text(
            '${selectedFiles.length} PDF(s) added to background queue / ${selectedFiles.length}টি পিডিএফ ব্যাকগ্রাউন্ডে আপলোড হচ্ছে',
            style: const TextStyle(color: Color(0xFF00E676)),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _deleteMagazine(String magId, String issueDate) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Confirm Deletion'),
            Text('(সংখ্যা মুছে ফেলা নিশ্চিত করুন)',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        content: Text(
            'Are you sure you want to completely delete "$issueDate" issue from servers?\n(আপনি কি নিশ্চিত যে "$issueDate" সংখ্যাটি মুছে ফেলতে চান?)'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancel (বাতিল)',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx, true);
            },
            child: const Text('Delete (মুছে ফেলুন)'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      final pages = await supabase
          .from('magazine_pages')
          .select('storage_path')
          .eq('magazine_id', magId);
      final List<String> paths = [];
      for (final p in pages) {
        paths.add(p['storage_path'] as String);
      }
      if (paths.isNotEmpty) {
        await supabase.storage.from('magazine_pages').remove(paths);
      }
      await supabase.from('magazines').delete().eq('id', magId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Issue deleted successfully / সংখ্যাটি মুছে ফেলা হয়েছে।')),
        );
        _loadAdminMagazines();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Publish Magazine Issues (2000 - 2030)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Text('(নতুন সংখ্যা প্রকাশনা - পত্রিকার নাম নির্দিষ্ট: "eআরণ্যক")',
            style: TextStyle(color: Color(0xFF81C784), fontSize: 12)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF18221B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _startMonth,
                      dropdownColor: const Color(0xFF18221B),
                      decoration: const InputDecoration(
                        labelText: 'Start Month',
                        helperText: '(শুরুর মাস)',
                        border: OutlineInputBorder(),
                      ),
                      items: _months
                          .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m,
                              style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _startMonth = val!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _endMonth,
                      dropdownColor: const Color(0xFF18221B),
                      decoration: const InputDecoration(
                        labelText: 'End Month',
                        helperText: '(শেষের মাস)',
                        border: OutlineInputBorder(),
                      ),
                      items: _months
                          .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m,
                              style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _endMonth = val!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedYear,
                      dropdownColor: const Color(0xFF18221B),
                      decoration: const InputDecoration(
                        labelText: 'Year',
                        helperText: '(বছর)',
                        border: OutlineInputBorder(),
                      ),
                      items: _years
                          .map((y) => DropdownMenuItem(
                          value: y,
                          child: Text(y,
                              style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedYear = val!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Selected Issue: $_startMonth - $_endMonth $_selectedYear',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              minimumSize: const Size(double.infinity, 54)),
          icon: const Icon(Icons.upload_file),
          label: const Column(
            children: [
              Text('Select PDF(s) & Upload in Background',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text('(একাধিক ফাইল নির্বাচন করুন ও ব্যাকগ্রাউন্ডে আপলোড চালান)',
                  style: TextStyle(fontSize: 10, color: Colors.white70)),
            ],
          ),
          onPressed: _pickAndUploadMultiplePdfs,
        ),
        const SizedBox(height: 36),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),
        const Text('Manage & Delete Published Issues:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('(প্রকাশিত সংখ্যা পরিচালনা ও মুছে ফেলা)',
            style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
        const SizedBox(height: 12),
        if (_adminMagazines.isEmpty)
          const Text('No issues uploaded yet / আপাতত কোনো সংখ্যা নেই।',
              style: TextStyle(color: Colors.grey))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adminMagazines.length,
            itemBuilder: (context, index) {
              final mag = _adminMagazines[index];
              return Card(
                color: const Color(0xFF18221B),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.menu_book_rounded,
                      color: Color(0xFF00E676)),
                  title: Text('${mag['title']} (${mag['issue_date']})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Total Pages: ${mag['total_pages']} (মোট পৃষ্ঠা: ${mag['total_pages']} টি)'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_forever_rounded,
                        color: Colors.redAccent),
                    tooltip: 'Delete Issue / সংখ্যাটি মুছে ফেলুন',
                    onPressed: () {
                      _deleteMagazine(mag['id'], mag['issue_date']);
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

// -------------------------------------------------------------
// 8. FULL-PAGE ESSAY NEWS
// -------------------------------------------------------------
class NewsDetailScreen extends StatefulWidget {
  final Map<String, dynamic> newsItem;
  const NewsDetailScreen({super.key, required this.newsItem});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _translateOnOpenIfNeeded();
  }

  /// If this article was opened before its Bengali edition was ready
  /// (English title/body still visible), translate it right now and
  /// refresh the page when done.
  Future<void> _translateOnOpenIfNeeded() async {
    final item = widget.newsItem;
    final needsWork = !_HomeScreenState._containsBengali(
            (item['title'] ?? '').toString()) ||
        !_HomeScreenState._hasUsableBengaliBody(item['content']);
    if (!needsWork || _translating) return;
    _translating = true;
    final changed =
        await _HomeScreenState._ensureBengaliEdition(item, force: true);
    _translating = false;
    if (changed && mounted) setState(() {});
  }

  Future<void> _launchSourceUrl(BuildContext context) async {
    final urlStr = widget.newsItem['source_url']?.toString();
    if (urlStr == null || urlStr.isEmpty) {
      return;
    }

    final uri = Uri.parse(urlStr);
    try {
      final launched =
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw 'Could not launch $urlStr';
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not open external link / উৎস লিঙ্ক খোলা সম্ভব হয়নি')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final newsItem = widget.newsItem;
    final String title = (newsItem['title'] ?? '').toString();
    final String category =
    (newsItem['category'] ?? '').toString().toLowerCase();

    final int seed = title.hashCode.abs() % 100000;
    final fallbackPainter = _WatercolorNewsPainter(
      title: title,
      category: category,
      seed: seed,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(newsItem['source']?.toString() ?? 'Wildlife Report',
                style: const TextStyle(fontSize: 16)),
            const Text('(বন্যপ্রাণ বার্তা)',
                style: TextStyle(fontSize: 10, color: Color(0xFF81C784))),
          ],
        ),
        backgroundColor: Colors.black87,
        actions: [
          if (newsItem['source_url'] != null)
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded,
                  color: Color(0xFF00E676)),
              tooltip: 'Open in browser / ব্রাউজারে পড়ুন',
              onPressed: () {
                _launchSourceUrl(context);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
// Header Image
            Hero(
              tag: 'news_image_${newsItem['title']}',
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF142419),
                  ),
                  child: _WatercolorNewsImage(
                    item: newsItem,
                    fallbackPainter: fallbackPainter,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      newsItem['source']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    newsItem['title']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  if (_translating) ...[
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF00E676)),
                        ),
                        SizedBox(width: 8),
                        Text('বাংলা সংস্করণ প্রস্তুত হচ্ছে…',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(newsItem['date_str']?.toString() ?? '',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                      const Spacer(),
                      const Icon(Icons.share_rounded,
                          size: 16, color: Color(0xFF00E676)),
                      const SizedBox(width: 4),
                      const Text('Share',
                          style: TextStyle(
                              color: Color(0xFF00E676), fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B261E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                          const Color(0xFF00E676).withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Color(0xFF00E676), size: 16),
                            SizedBox(width: 8),
                            Text('Quick Summary / সংক্ষেপ',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF81C784))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          newsItem['snippet']?.toString() ?? '',
                          style: const TextStyle(
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF81C784),
                              height: 1.6),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Detailed Report / বিস্তারিত প্রতিবেদন',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    newsItem['content']?.toString() ?? '',
                    style: const TextStyle(
                        fontSize: 17, color: Colors.white70, height: 1.9),
                  ),
                  const SizedBox(height: 32),
                  InkWell(
                    onTap: () {
                      _launchSourceUrl(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142419),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                            const Color(0xFF00E676).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.language_rounded,
                              color: Color(0xFF00E676), size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Explore Original Report at ${newsItem['source']}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                    'উৎস সাইটে গিয়ে সম্পূর্ণ তথ্যচিত্র ও আলোকচিত্রসহ মূল খবরটি পড়ুন ↗',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 11. NATURE GAMES DATA & SCREEN
// -------------------------------------------------------------
// -------------------------------------------------------------
// 11. NATURE GAMES — LIVE WILDLIFE MEDIA
//
// Photo media:
//   1) Supabase wildlife-media function (preferred; can aggregate
//      eBird / Macaulay / iNaturalist)
//   2) iNaturalist public taxon API fallback
//
// Bird calls:
//   Supabase wildlife-media function. Keep Xeno-canto/eBird
//   credentials on the server, never inside this Flutter app.
//
// The important rule is that the MEDIA and ANSWER always belong
// to the same species record.
// -------------------------------------------------------------

class WildlifeMedia {
  final String species;
  final String? scientificName;
  final String? imageUrl;
  final String? audioUrl;
  final String source;
  final String? attribution;

  const WildlifeMedia({
    required this.species,
    this.scientificName,
    this.imageUrl,
    this.audioUrl,
    required this.source,
    this.attribution,
  });

  factory WildlifeMedia.fromMap(
      Map<String, dynamic> map, {
        required String fallbackSpecies,
        String fallbackSource = 'Wildlife media',
      }) {
    String? firstString(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      return null;
    }

    return WildlifeMedia(
      species: firstString(
        const ['species', 'common_name', 'commonName', 'name'],
      ) ??
          fallbackSpecies,
      scientificName: firstString(
        const ['scientific_name', 'scientificName', 'latin_name'],
      ),
      imageUrl: firstString(
        const ['image_url', 'imageUrl', 'photo_url', 'photoUrl', 'url'],
      ),
      audioUrl: firstString(
        const ['audio_url', 'audioUrl', 'recording_url', 'recordingUrl'],
      ),
      source: firstString(
        const ['source', 'provider', 'source_name'],
      ) ??
          fallbackSource,
      attribution: firstString(
        const ['attribution', 'credit', 'author', 'recordist'],
      ),
    );
  }
}

class WildlifeMediaService {
  static const String _iNaturalistBase = 'https://api.inaturalist.org/v1/taxa';

  /// Server-side aggregator. This function should keep Xeno-canto/eBird
  /// credentials off the device and may return iNaturalist/Macaulay media.
  static Future<WildlifeMedia?> _serverMedia({
    required String action,
    required String species,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'wildlife-media',
        body: <String, dynamic>{
          'action': action,
          'species': species,
        },
      );

      final raw = response.data;
      if (raw is! Map) return null;

      final data = Map<String, dynamic>.from(raw);
      final payload = data['media'] is Map
          ? Map<String, dynamic>.from(data['media'] as Map)
          : data;

      final result = WildlifeMedia.fromMap(
        payload,
        fallbackSpecies: species,
        fallbackSource: 'Wildlife media',
      );

      if (action == 'photo' && result.imageUrl == null) return null;

      return result;
    } catch (_) {
      return null;
    }
  }

  /// iNaturalist is used as a public read-only fallback for photographs.
  /// This keeps the Photo Quiz and Scrambled Image games usable even if
  /// the server-side aggregator is temporarily unavailable.
  static Future<WildlifeMedia?> _iNaturalistPhoto(String species) async {
    HttpClient? client;
    try {
      client = HttpClient();
      final encoded = Uri.encodeQueryComponent(species);
      final request = await client.getUrl(
        Uri.parse('$_iNaturalistBase?q=$encoded&rank=species&per_page=5'),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json',
      );

      final response = await request.close();
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      if (decoded is! Map || decoded['results'] is! List) return null;

      for (final raw in decoded['results']) {
        if (raw is! Map) continue;

        final taxon = Map<String, dynamic>.from(raw);
        final photo = taxon['default_photo'];

        if (photo is Map) {
          final photoMap = Map<String, dynamic>.from(photo);
          final url = photoMap['medium_url'] ??
              photoMap['large_url'] ??
              photoMap['square_url'];

          if (url != null && url.toString().trim().isNotEmpty) {
            return WildlifeMedia(
              species: taxon['preferred_common_name']?.toString() ?? species,
              scientificName: taxon['name']?.toString(),
              imageUrl: url.toString(),
              source: 'iNaturalist',
              attribution: photoMap['attribution']?.toString(),
            );
          }
        }
      }
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }

    return null;
  }

  /// Resolve a bird call from Wikimedia Commons.
  ///
  /// We deliberately do not use Xeno-canto, Macaulay Library or Cornell
  /// for the quiz. Commons' MediaWiki API returns the actual uploaded
  /// audio URL plus machine-readable MIME/metadata. The File: webpage
  /// itself is never passed to the audio player.
  static final Map<String, WildlifeMedia> _wikimediaAudioCache = {};

  static String? _metadataValue(Map<String, dynamic>? metadata, String key) {
    final raw = metadata?[key];
    if (raw is Map) {
      final value = raw['value'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    if (raw != null && raw.toString().trim().isNotEmpty) {
      return raw.toString().trim();
    }
    return null;
  }

  static int _audioFormatRank(String? mime, String url) {
    final m = (mime ?? '').toLowerCase();
    final u = url.toLowerCase();
    if (m == 'audio/mpeg' || u.endsWith('.mp3')) return 0;
    if (m == 'audio/wav' || m == 'audio/x-wav' || u.endsWith('.wav')) return 1;
    if (m == 'audio/ogg' || m == 'audio/opus' ||
        u.endsWith('.ogg') || u.endsWith('.oga') || u.endsWith('.opus')) {
      return 2;
    }
    if (m.startsWith('audio/')) return 3;
    return 99;
  }

  static Future<WildlifeMedia?> _wikimediaAudio(String species) async {
    final cached = _wikimediaAudioCache[species];
    if (cached != null) return cached;

    HttpClient? client;
    try {
      client = HttpClient();
      client.userAgent =
      'eAranyakApp/1.0 (educational wildlife app; Flutter)';

      final queries = <String>[
        '"$species" filetype:audio',
        '$species bird filetype:audio',
      ];

      for (final searchTerm in queries) {
        final uri = Uri.https(
          'commons.wikimedia.org',
          '/w/api.php',
          <String, String>{
            'action': 'query',
            'format': 'json',
            'generator': 'search',
            'gsrnamespace': '6',
            'gsrlimit': '30',
            'gsrsearch': searchTerm,
            'prop': 'imageinfo',
            'iiprop': 'url|mime|extmetadata',
          },
        );

        final request = await client.getUrl(uri);
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/json',
        );

        final response = await request.close();
        if (response.statusCode != 200) continue;

        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is! Map) continue;

        final query = decoded['query'];
        if (query is! Map) continue;

        final pages = query['pages'];
        if (pages is! Map) continue;

        final candidates = <Map<String, dynamic>>[];

        for (final rawPage in pages.values) {
          if (rawPage is! Map) continue;
          final page = Map<String, dynamic>.from(rawPage);
          final title = page['title']?.toString() ?? '';
          final imageInfo = page['imageinfo'];

          if (imageInfo is! List || imageInfo.isEmpty) continue;
          final first = imageInfo.first;
          if (first is! Map) continue;

          final info = Map<String, dynamic>.from(first);
          final url = info['url']?.toString().trim();
          final mime = info['mime']?.toString().trim();

          if (url == null || url.isEmpty || mime == null) continue;
          if (!mime.toLowerCase().startsWith('audio/')) continue;

          final titleLower = title.toLowerCase();
          final speciesLower = species.toLowerCase();

          int relevance = 0;
          if (titleLower.contains(speciesLower)) relevance += 100;
          if (titleLower.contains('call')) relevance += 20;
          if (titleLower.contains('song')) relevance += 10;

          final metadata = info['extmetadata'] is Map
              ? Map<String, dynamic>.from(info['extmetadata'] as Map)
              : null;

          candidates.add({
            'url': url,
            'mime': mime,
            'title': title,
            'metadata': metadata,
            'relevance': relevance,
          });
        }

        if (candidates.isEmpty) continue;

        candidates.sort((a, b) {
          final relevanceCompare =
          (b['relevance'] as int).compareTo(a['relevance'] as int);
          if (relevanceCompare != 0) return relevanceCompare;

          return _audioFormatRank(
            a['mime']?.toString(),
            a['url'].toString(),
          ).compareTo(
            _audioFormatRank(
              b['mime']?.toString(),
              b['url'].toString(),
            ),
          );
        });

        final best = candidates.first;
        final metadata = best['metadata'] as Map<String, dynamic>?;

        final artist = _metadataValue(metadata, 'Artist') ??
            _metadataValue(metadata, 'Credit') ??
            _metadataValue(metadata, 'Creator');

        final license = _metadataValue(metadata, 'LicenseShortName') ??
            _metadataValue(metadata, 'UsageTerms');

        final sourcePage = Uri.encodeFull(
          'https://commons.wikimedia.org/wiki/${best['title'].toString().replaceFirst('File:', 'File:')}',
        );

        final attributionParts = <String>[
          if (artist != null && artist.isNotEmpty) 'Recorded by $artist',
          if (license != null && license.isNotEmpty) license,
          'Wikimedia Commons',
        ];

        final media = WildlifeMedia(
          species: species,
          audioUrl: best['url'].toString(),
          source: 'Wikimedia Commons',
          attribution: '${attributionParts.join(' • ')} • $sourcePage',
        );

        _wikimediaAudioCache[species] = media;
        return media;
      }
    } catch (_) {
      // The quiz handles this as an unavailable call rather than crashing.
    } finally {
      client?.close(force: true);
    }

    return null;
  }

  static Future<WildlifeMedia?> fetchPhoto(String species) async {
    final server = await _serverMedia(
      action: 'photo',
      species: species,
    );

    if (server?.imageUrl != null) return server;

    return _iNaturalistPhoto(species);
  }

  static Future<WildlifeMedia?> fetchPuzzleImage(String species) async {
    final server = await _serverMedia(
      action: 'photo',
      species: species,
    );

    if (server?.imageUrl != null) return server;

    return _iNaturalistPhoto(species);
  }

  static Future<WildlifeMedia?> fetchAudio(String species) async {
    return _wikimediaAudio(species);
  }
}

class WildlifeGameSpecies {
  final String english;
  final String bengali;
  final String question;

  const WildlifeGameSpecies({
    required this.english,
    required this.bengali,
    required this.question,
  });

  String get label => '$english ($bengali)';
}

class WildlifeGameData {
  static const List<WildlifeGameSpecies> photoSpecies = [
    WildlifeGameSpecies(
      english: 'Bengal Tiger',
      bengali: 'রয়েল বেঙ্গল টাইগার',
      question: 'Identify this majestic national animal / এই রাজকীয় প্রাণীটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Asian Elephant',
      bengali: 'এশীয় হাতি',
      question: 'Identify this gentle giant of the forest / বনের এই শান্ত দৈত্যটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'One-horned Rhinoceros',
      bengali: 'একশৃঙ্গ গণ্ডার',
      question: 'Identify this prehistoric-looking mammal / প্রাগৈতিহাসিক চেহারার এই প্রাণীটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Himalayan Monal',
      bengali: 'হিমালয়ান মোনাল',
      question: 'Identify this high-altitude bird / উচ্চ পার্বত্য এই পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Great Indian Bustard',
      bengali: 'গ্রেট ইন্ডিয়ান বাস্টার্ড',
      question: 'Identify this iconic grassland bird / এই ঘাসভূমির পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Indian Skimmer',
      bengali: 'ইন্ডিয়ান স্কিমার',
      question: 'Identify this river bird / এই নদী-নির্ভর পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Snow Leopard',
      bengali: 'তুষার চিতা',
      question: 'Identify this mountain cat / পাহাড়ের এই বিড়ালটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Batagur baska',
      bengali: 'বাটাগুর বাসকা',
      question: 'Identify this endangered turtle / এই বিপন্ন কচ্ছপটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Gharial',
      bengali: 'ঘড়িয়াল',
      question: 'Identify this long-snouted crocodilian / লম্বা নাকের এই সরীসৃপটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Great Hornbill',
      bengali: 'ধনেশ',
      question: 'Identify this large rainforest bird / বৃষ্টিচ্ছায় অরণ্যের এই বড় পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Red Panda',
      bengali: 'লাল পাণ্ডা',
      question: 'Identify this Himalayan mammal / এই হিমালয়ান স্তন্যপায়ীটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Indian Pangolin',
      bengali: 'বনরুই',
      question: 'Identify this armour-clad mammal / বর্মধারী এই প্রাণীটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Barasingha',
      bengali: 'বারাসিঙ্গা',
      question: 'Identify this wetland deer / এই জলাভূমি-নির্ভর হরিণটিকে চিনুন',
    ),
  ];

  static const List<WildlifeGameSpecies> audioSpecies = [
    WildlifeGameSpecies(
      english: 'Oriental Magpie-Robin',
      bengali: 'দোয়েল',
      question: 'Listen carefully and identify this bird / মন দিয়ে শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Common Myna',
      bengali: 'শালিক',
      question: 'Whose call is this? / এই ডাকটি কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'Asian Koel',
      bengali: 'কোকিল',
      question: 'Identify the bird from its call / ডাক শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Greater Coucal',
      bengali: 'কুবো',
      question: 'Listen to the call and identify the bird / ডাক শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Black Drongo',
      bengali: 'ফিঙে',
      question: 'Identify this bird by its sharp call / ডাক শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Spotted Dove',
      bengali: 'তিলঘঘু',
      question: 'Which bird makes this cooing sound? / এই কুজন কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'Jungle Babbler',
      bengali: 'ছাতারে',
      question: 'Identify this noisy group call / এই শোরগোলপূর্ণ ডাকটি কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'White-throated Kingfisher',
      bengali: 'সাদা-গলা মাছরাঙা',
      question: 'Which bird made this call? / এই ডাকটি কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'Coppersmith Barbet',
      bengali: 'বসন্তবৌরি',
      question: 'Identify this rhythmic call / এই ছন্দময় ডাকটি চিনুন',
    ),
  ];

  static const List<Map<String, dynamic>> hintQuiz = [
    {
      'hints': [
        'I have the longest snout among all crocodilians.',
        'I am critically endangered and found in the Chambal river.',
        'Adult males have a pot-like structure on my nose.',
      ],
      'options': [
        'Gharial (ঘড়িয়াল)',
        'Mugger Crocodile (মাগর কুমির)',
        'Saltwater Crocodile (নোনা জলের কুমির)',
        'False Gharial (ফলস ঘড়িয়াল)',
      ],
      'answer': 'Gharial (ঘড়িয়াল)',
    },
    {
      'hints': [
        'I am a marine herbivore often called "Sea Cow".',
        'I am found in the Gulf of Mannar and Andaman islands.',
        'I am the state animal of Andaman and Nicobar.',
      ],
      'options': [
        'Dugong (ডুগং)',
        'Manatee (ম্যানাটি)',
        'Dolphin (ডলফিন)',
        'Porpoise (পরপাস)',
      ],
      'answer': 'Dugong (ডুগং)',
    },
    {
      'hints': [
        'I am the state bird of West Bengal.',
        'I have a brilliant blue color on my back and wings.',
        'I wait patiently on branches before diving for fish.',
      ],
      'options': [
        'White-throated Kingfisher (সাদা-গলা মাছরাঙা)',
        'Pied Kingfisher (কালো-সাদা মাছরাঙা)',
        'Common Kingfisher (ছোট মাছরাঙা)',
        'Blue Jay (নীলকণ্ঠ)',
      ],
      'answer': 'White-throated Kingfisher (সাদা-গলা মাছরাঙা)',
    },
    {
      'hints': [
        'I am an ancient, living fossil found on the Odisha coast.',
        'I come to the beach in thousands for "Arribada".',
        'I am the smallest and most abundant sea turtle.',
      ],
      'options': [
        'Olive Ridley (অলিভ রিডলি)',
        'Green Sea Turtle (সবুজ কচ্ছপ)',
        'Loggerhead (লগারহেড)',
        'Leatherback (লেদারব্যাক)',
      ],
      'answer': 'Olive Ridley (অলিভ রিডলি)',
    },
    {
      'hints': [
        'I am the only ape species found in India.',
        'I am known for my loud, distinctive hooting calls.',
        'I live in the rainforest forests of Northeast India.',
      ],
      'options': [
        'Hoolock Gibbon (উলুক)',
        'Bonobo (বোনাবো)',
        'Gorilla (গরিলা)',
        'Orangutan (ওরাংওটাং)',
      ],
      'answer': 'Hoolock Gibbon (উলুক)',
    },
    {
      'hints': [
        'I am an endemic macaque found in the Western Ghats.',
        'I have a silver-white mane surrounding my face.',
        'I am primarily a fruit-eater but also eat insects.',
      ],
      'options': [
        'Lion-tailed Macaque (সিংহপুচ্ছ বাঁদর)',
        'Bonnet Macaque (টুপি বাঁদর)',
        'Rhesus Macaque (লাল বাঁদর)',
        'Langur (লঙ্গুর)',
      ],
      'answer': 'Lion-tailed Macaque (সিংহপুচ্ছ বাঁদর)',
    },
    {
      'hints': [
        'I am the "dancing deer" of Manipur.',
        'I live on floating islands of vegetation called "Phumdis".',
        'I am found only in Keibul Lamjao National Park.',
      ],
      'options': [
        'Sangai (সাঙ্গাই)',
        'Hog Deer (পাড় হরিণ)',
        'Barking Deer (মায়া হরিণ)',
        'Chital (চিত্রা হরিণ)',
      ],
      'answer': 'Sangai (সাঙ্গাই)',
    },
    {
      'hints': [
        'I am the only wild goat found in South India.',
        'I have curved horns and a stocky build.',
        'I live in the high-altitude grassy hills of Nilgiris.',
      ],
      'options': [
        'Nilgiri Tahr (নীলগিরি তহর)',
        'Ibex (আইবেক্স)',
        'Markhor (মারখোর)',
        'Mountain Goat (পাহাড়ি ছাগল)',
      ],
      'answer': 'Nilgiri Tahr (নীলগিরি তহর)',
    },
    {
      'hints': [
        'I am famous as the "Ghost of the Mountains".',
        'I am perfectly camouflaged in the rocky Himalayas.',
        'I cannot roar, but I can hiss and growl.',
      ],
      'options': [
        'Snow Leopard (তুষার চিতা)',
        'Clouded Leopard (মেঘলা চিতা)',
        'Puma (পুমা)',
        'Jaguar (জাগুয়ার)',
      ],
      'answer': 'Snow Leopard (তুষার চিতা)',
    },
    {
      'hints': [
        'I am the state animal of Sikkim.',
        'I spend most of my time in trees eating bamboo.',
        'I have a long, bushy, ringed tail.',
      ],
      'options': [
        'Red Panda (লাল পাণ্ডা)',
        'Giant Panda (পাণ্ডা)',
        'Koala (কোয়ালা)',
        'Lemur (লেমুর)',
      ],
      'answer': 'Red Panda (লাল পাণ্ডা)',
    },
    {
      'hints': [
        'I have a horn-like casque on top of my bill.',
        'I play a vital role in dispersing rainforest seeds.',
        'I am the state bird of Kerala and Arunachal Pradesh.',
      ],
      'options': [
        'Great Hornbill (ধনেশ)',
        'Malabar Pied Hornbill (কালো-সাদা ধনেশ)',
        'Grey Hornbill (ধূসর ধনেশ)',
        'Toucan (টুকান)',
      ],
      'answer': 'Great Hornbill (ধনেশ)',
    },
    {
      'hints': [
        'I am the largest of all wild cattle in the world.',
        'I have massive horns and white "socks" on my legs.',
        'I am found in large herds in Central Indian forests.',
      ],
      'options': [
        'Gaur (গৌর/ইন্ডিয়ান বাইসন)',
        'Wild Buffalo (বন মহিষ)',
        'Yak (চমরী গাই)',
        'Nilgai (নীলগাই)',
      ],
      'answer': 'Gaur (গৌর/ইন্ডিয়ান বাইসন)',
    },
    {
      'hints': [
        'I am a venomous snake known as the "King of Cobras".',
        'I am the only snake in the world that builds nests.',
        'I feed primarily on other snakes.',
      ],
      'options': [
        'King Cobra (রাজগোখরো)',
        'Spectacled Cobra (গোখরো)',
        'Monocled Cobra (কেউটে)',
        'Python (অজগর)',
      ],
      'answer': 'King Cobra (রাজগোখরো)',
    },
  ];

  static const List<String> puzzleSpecies = [
    'Indian Skimmer',
    'Great Indian Bustard',
    'Lesser Adjutant',
    'Red Panda',
    'Indian Pangolin',
    'Himalayan Monal',
    'Snow Leopard',
    'Barasingha',
  ];
}

class NatureGamesScreen extends StatefulWidget {
  const NatureGamesScreen({super.key});

  @override
  State<NatureGamesScreen> createState() => _NatureGamesScreenState();
}

class _NatureGamesScreenState extends State<NatureGamesScreen> {
  // category ('photo'|'audio'|'hint'|'scramble') -> challenge payload
  Map<String, Map<String, dynamic>> _weekly = {};

  @override
  void initState() {
    super.initState();
    _loadWeeklyChallenges();
  }

  void refresh() {
    _loadWeeklyChallenges();
    setState(() {});
  }

  String _currentWeekStart() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadWeeklyChallenges() async {
    try {
      final res = await supabase
          .from('weekly_challenges')
          .select()
          .eq('week_start', _currentWeekStart());
      if (!mounted) return;
      setState(() {
        _weekly = {
          for (final row in res)
            if ((row['category'] ?? '').toString().isNotEmpty)
              (row['category'] as String):
                  Map<String, dynamic>.from(row['payload'] ?? const {}),
        };

      });
    } catch (_) {
      // Table not set up yet or offline — games fall back to built-in pools.
      if (mounted) setState(() {});
    }
  }


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF214D2A), Color(0xFF102016)],
              ),
              border: Border.all(
                color: const Color(0xFF00E676).withValues(alpha: 0.32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00E676).withValues(alpha: 0.12),
                    border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Icon(
                    Icons.park_rounded,
                    color: Color(0xFF81C784),
                    size: 31,
                  ),
                ),
                const SizedBox(width: 15),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'খেলার ছলে প্রকৃতি পাঠ',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Nature Study through Games',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF81C784),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'দেখুন • শুনুন • ভাবুন • চিনুন',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFF00E676), size: 18),
              SizedBox(width: 8),
              Text(
                'Choose a challenge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 7),
              Text(
                '(একটি খেলা বেছে নিন)',
                style: TextStyle(
                  color: Color(0xFF81C784),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (_weekly.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.45)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emoji_events_rounded,
                      color: Color(0xFF00E676), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'এই সপ্তাহের নতুন চ্যালেঞ্জ লাইভ! (This week\'s challenges are live)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 700 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: crossAxisCount == 4 ? 1.05 : 0.96,
                children: [
                  _buildGameCard(
                    context,
                    'আলোকচিত্র চেনা',
                    'Identify from Photos',
                    'assets/images/identify_image.png',
                    const Color(0xFF2E7D32),
                    'দেখে চিনুন',
                        () => _startQuiz(context, 'photo'),
                  ),
                  _buildGameCard(
                    context,
                    'ডাক শুনে চেনা',
                    'Recognize by Call',
                    'assets/images/identify_call.png',
                    const Color(0xFF00897B),
                    'শুনে চিনুন',
                        () => _startQuiz(context, 'audio'),
                  ),
                  _buildGameCard(
                    context,
                    'ইঙ্গিত বুঝে চেনা',
                    'Identify from Hints',
                    'assets/images/identify_clue.png',
                    const Color(0xFF6A1B9A),
                    'ইঙ্গিত ধরুন',
                        () => _startQuiz(context, 'hint'),
                  ),
                  _buildGameCard(
                    context,
                    'টুকরো ছবি জোড়া',
                    'Scrambled Image',
                    'assets/images/zigshaw_puzzle.png',
                    const Color(0xFFE65100),
                    'ছবি মিলিয়ে নিন',
                        () => _startScramble(context),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.school_rounded, color: Color(0xFF81C784), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'প্রতিটি খেলায় প্রকৃতির সঙ্গে একটু পরিচয়, একটু আনন্দ।',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(
      BuildContext context,
      String titleBn,
      String titleEn,
      String imageAsset,
      Color color,
      String action,
      VoidCallback onTap,
      ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withValues(alpha: 0.18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0.07),
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.52)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    height: 110,
                    color: color.withValues(alpha: 0.12),
                    child: Image.asset(
                      imageAsset,
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.image_not_supported_rounded,
                            color: Colors.white70,
                            size: 38,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        titleBn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  titleEn,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    action,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Weekly hint challenges can arrive either as full items or as
  /// indices into the built-in WildlifeGameData.hintQuiz bank.
  List<Map<String, dynamic>>? _hintItemsFrom(Map<String, dynamic> payload) {
    final indices = payload['indices'] as List?;
    if (indices != null && indices.isNotEmpty) {
      const bank = WildlifeGameData.hintQuiz;
      return indices
          .map((i) =>
              Map<String, dynamic>.from(bank[((i as int) % bank.length)]))
          .toList();
    }
    final items = payload['items'] as List?;
    if (items != null && items.isNotEmpty) {
      return items.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return null;
  }

  void _startQuiz(BuildContext context, String type) {
    final payload = _weekly[type];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WildlifeQuizGame(
          type: type,
          weeklySpecies: (type != 'hint' && payload != null)
              ? List<String>.from(payload['species'] ?? const [])
              : null,
          weeklyHintItems: (type == 'hint' && payload != null)
              ? _hintItemsFrom(payload)
              : null,
          weeklySeed: (payload?['seed'] as num?)?.toInt() ?? 0,
        ),
      ),
    );
  }

  void _startScramble(BuildContext context) {
    final payload = _weekly['scramble'];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScrambledImageGame(
          weeklySpecies: payload != null
              ? List<String>.from(payload['species'] ?? const [])
              : null,
          weeklySeed: (payload?['seed'] as num?)?.toInt() ?? 0,
        ),
      ),
    );
  }
}

class WildlifeQuizGame extends StatefulWidget {
  final String type;
  final List<String>? weeklySpecies;
  final List<Map<String, dynamic>>? weeklyHintItems;
  final int weeklySeed;

  const WildlifeQuizGame({
    super.key,
    required this.type,
    this.weeklySpecies,
    this.weeklyHintItems,
    this.weeklySeed = 0,
  });

  @override
  State<WildlifeQuizGame> createState() => _WildlifeQuizGameState();
}

class _WildlifeQuizGameState extends State<WildlifeQuizGame> {
  late List<Map<String, dynamic>> _questions;
  int _currentIndex = 0;
  int _score = 0;
  bool _answered = false;
  bool _loading = true;
  String? _selectedOption;
  String? _mediaError;
  WildlifeMedia? _media;
  AudioPlayer? _quizAudioPlayer;
  bool _audioPlaying = false;
  bool _audioLoading = false;

  @override
  void initState() {
    super.initState();

    _quizAudioPlayer = AudioPlayer();
    _quizAudioPlayer!.setPlayerMode(PlayerMode.mediaPlayer);
    _quizAudioPlayer!.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _audioPlaying = false;
        _audioLoading = false;
      });
    });

    _initQuiz();
  }

  Future<void> _initQuiz() async {
    if (widget.type == 'hint') {
      List<Map<String, dynamic>> raw;
      if (widget.weeklyHintItems != null &&
          widget.weeklyHintItems!.isNotEmpty) {
        raw = widget.weeklyHintItems!
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } else {
        raw = WildlifeGameData.hintQuiz
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      raw.shuffle(math.Random(widget.weeklySeed));

      if (!mounted) return;
      setState(() {
        _questions = raw;
        _loading = false;
      });
      return;
    }

    if (widget.type == 'photo' || widget.type == 'audio') {
      final basePool = widget.type == 'audio'
          ? WildlifeGameData.audioSpecies
          : WildlifeGameData.photoSpecies;

      // Weekly challenges pin the species set served from the server.
      var pool = basePool;
      if (widget.weeklySpecies != null && widget.weeklySpecies!.isNotEmpty) {
        final weekly = basePool
            .where((s) => widget.weeklySpecies!.contains(s.english))
            .toList();
        if (weekly.isNotEmpty) pool = weekly;
      }

      final species = pool.toList()..shuffle(math.Random(widget.weeklySeed));

      _questions = species
          .take(8) // Increased to 8 questions
          .map(
            (s) {
          final distractors = basePool
              .where((x) => x.english != s.english)
              .toList()
            ..shuffle(math.Random(widget.weeklySeed + s.english.hashCode));

          return <String, dynamic>{
            'species': s,
            'options': <String>[
              s.label,
              ...distractors.take(3).map((x) => x.label),
            ]..shuffle(),
          };
        },
      )
          .toList();
    }

    await _loadCurrentMedia();
  }

  Future<void> _loadCurrentMedia() async {
    if (_questions.isEmpty) return;

    if (widget.type == 'hint') {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final species =
        (_questions[_currentIndex]['species'] as WildlifeGameSpecies).english;

    if (mounted) {
      await _quizAudioPlayer?.stop();
      if (mounted) {
        setState(() {
          _loading = true;
          _audioPlaying = false;
          _audioLoading = false;
          _media = null;
          _mediaError = null;
          _answered = false;
          _selectedOption = null;
        });
      }
    }

    WildlifeMedia? media;
    if (widget.type == 'photo') {
      media = await WildlifeMediaService.fetchPhoto(species);
    } else if (widget.type == 'audio') {
      media = await WildlifeMediaService.fetchAudio(species);
    }

    if (!mounted) return;

    if (media == null ||
        (widget.type == 'photo' && media.imageUrl == null) ||
        (widget.type == 'audio' && media.audioUrl == null)) {
      setState(() {
        _loading = false;
        _mediaError = widget.type == 'audio'
            ? 'No suitable Wikimedia Commons bird call was found.\n'
            'Wikimedia Commons-এ উপযুক্ত পাখির ডাক পাওয়া যায়নি।'
            : 'Media for $species is temporarily unavailable.\n'
            'এই প্রজাতির মিডিয়া এই মুহূর্তে পাওয়া যাচ্ছে না।';
      });
      return;
    }

    setState(() {
      _media = media;
      _loading = false;
    });
  }

  void _handleAnswer(String option) {
    if (_answered || _loading || _questions.isEmpty) return;
    _quizAudioPlayer?.stop();
    _audioPlaying = false;
    _audioLoading = false;

    final species = _questions[_currentIndex]['species'];
    final correct = species is WildlifeGameSpecies
        ? species.label
        : _questions[_currentIndex]['answer']?.toString();

    setState(() {
      _selectedOption = option;
      _answered = true;
      if (option == correct) {
        _score++;
      }
    });
  }

  Future<void> _nextQuestion() async {
    if (_currentIndex >= _questions.length - 1) {
      await _showFinalScore();
      return;
    }

    await _quizAudioPlayer?.stop();
    setState(() {
      _currentIndex++;
      _answered = false;
      _selectedOption = null;
      _audioPlaying = false;
      _audioLoading = false;
      _media = null;
      _mediaError = null;
    });

    await _loadCurrentMedia();
  }

  Future<void> _showFinalScore() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('Game Complete! (খেলা শেষ!)'),
        content: Text(
          'Your score: $_score / ${_questions.length}\n'
              'আপনার স্কোর: $_score / ${_questions.length}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text(
              'Back to Games',
              style: TextStyle(color: Color(0xFF00E676)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _quizAudioPlayer?.stop();
    _quizAudioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _questions.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1410),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E676)),
        ),
      );
    }

    final current = _questions[_currentIndex];
    final isHint = widget.type == 'hint';
    final WildlifeGameSpecies? species =
    current['species'] is WildlifeGameSpecies
        ? current['species'] as WildlifeGameSpecies
        : null;

    final String question = isHint
        ? 'Who am I? / আমি কে?'
        : (species?.question ?? 'Identify this species / প্রজাতিটি চিনুন');

    final List<String> options = List<String>.from(current['options'] as List);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        title: Text(
          widget.type == 'photo'
              ? 'IDENTIFY FROM PHOTOS'
              : widget.type == 'audio'
              ? 'RECOGNIZE FROM CALL'
              : 'IDENTIFY FROM HINTS',
        ),
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$_score / ${_currentIndex + (_answered ? 1 : 0)}',
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions.length,
              backgroundColor: Colors.white12,
              color: const Color(0xFF00E676),
            ),
            const SizedBox(height: 22),
            Text(
              question,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            if (widget.type == 'photo')
              _buildPhotoArea()
            else if (widget.type == 'audio')
              _buildAudioArea()
            else
              _buildHintArea(current),
            const SizedBox(height: 22),
            ...options.map(
                  (opt) {
                final correct =
                    species?.label ?? current['answer']?.toString() ?? '';
                final isCorrect = opt == correct;
                final isSelected = opt == _selectedOption;

                Color background = Colors.white10;
                if (_answered) {
                  if (isCorrect) {
                    background = Colors.green.shade800;
                  } else if (isSelected) {
                    background = Colors.red.shade900;
                  }
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: background,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      alignment: Alignment.centerLeft,
                      side: _answered && isCorrect
                          ? const BorderSide(color: Colors.white, width: 2)
                          : null,
                    ),
                    onPressed: () => _handleAnswer(opt),
                    child: Text(
                      opt,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                );
              },
            ),
            if (_answered)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 52),
                ),
                onPressed: _nextQuestion,
                child: Text(
                  _currentIndex == _questions.length - 1
                      ? 'Finish (শেষ করুন)'
                      : 'Next Question (পরবর্তী প্রশ্ন)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioArea() {
    if (_loading || _audioLoading) {
      return Container(
        height: 255,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF164C2A), Color(0xFF0D2115)],
          ),
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.35),
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00E676)),
              SizedBox(height: 14),
              Text(
                'Finding a bird call…\nপাখির ডাক খোঁজা হচ্ছে…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_mediaError != null || _media?.audioUrl == null) {
      return Container(
        height: 255,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFF241916),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.volume_off_rounded,
              color: Colors.orangeAccent,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _mediaError ??
                  'No suitable Wikimedia Commons call was found.\n'
                      'উপযুক্ত পাখির ডাক পাওয়া যায়নি।',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadCurrentMedia,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again / আবার চেষ্টা করুন'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF174D2B), Color(0xFF0B1D12)],
        ),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: _audioPlaying ? 94 : 82,
            height: _audioPlaying ? 94 : 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E676).withValues(
                alpha: _audioPlaying ? 0.22 : 0.12,
              ),
              border: Border.all(
                color: const Color(0xFF00E676).withValues(alpha: 0.65),
                width: 2,
              ),
            ),
            child: Icon(
              _audioPlaying
                  ? Icons.graphic_eq_rounded
                  : Icons.record_voice_over_rounded,
              color: const Color(0xFF00E676),
              size: 42,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Listen carefully',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'মন দিয়ে শুনে পাখিটিকে চিনুন',
            style: TextStyle(color: Color(0xFF9AD6A3), fontSize: 11),
          ),
          const SizedBox(height: 16),
          // Simple tactile waveform.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(19, (i) {
              final heights = [8, 14, 22, 12, 30, 18, 38, 24, 44, 18,
                34, 16, 42, 23, 31, 14, 25, 12, 8];
              return AnimatedContainer(
                duration: Duration(milliseconds: 160 + i * 8),
                curve: Curves.easeInOut,
                width: 3,
                height: _audioPlaying ? heights[i].toDouble() : 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(
                    alpha: _audioPlaying ? 0.78 : 0.28,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final player = _quizAudioPlayer;
                final url = _media?.audioUrl;
                if (player == null || url == null || url.isEmpty) return;

                try {
                  if (_audioPlaying) {
                    await player.pause();
                    if (mounted) {
                      setState(() => _audioPlaying = false);
                    }
                    return;
                  }

                  setState(() => _audioLoading = true);
                  await player.stop();
                  await player.setSource(UrlSource(url));
                  await player.resume();

                  if (mounted) {
                    setState(() {
                      _audioLoading = false;
                      _audioPlaying = true;
                    });
                  }
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    _audioLoading = false;
                    _audioPlaying = false;
                    _mediaError =
                    'This call could not be played on this device.\n'
                        'এই ডাকটি এই ডিভাইসে চালানো যাচ্ছে না।';
                  });
                }
              },
              icon: Icon(
                _audioPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 30,
              ),
              label: Text(
                _audioPlaying
                    ? 'PAUSE CALL (বিরতি দিন)'
                    : 'PLAY BIRD CALL (ডাক শুনুন)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Listen as many times as you need before answering.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 9),
          ),
          const SizedBox(height: 8),
          _buildAttribution(),
        ],
      ),
    );
  }

  Widget _buildPhotoArea() {
    if (_loading) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF00E676)),
        ),
      );
    }

    if (_mediaError != null || _media?.imageUrl == null) {
      return _buildMediaError();
    }

    return Column(
      children: [
        Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: _media!.imageUrl!,
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E676)),
              ),
              errorWidget: (context, url, error) => _buildMediaError(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildAttribution(),
      ],
    );
  }

  Widget _buildHintArea(Map<String, dynamic> current) {
    final hints = List<String>.from(current['hints'] as List);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF81C784).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < hints.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: const Color(0xFF2E7D32),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hints[i],
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaError() {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          _mediaError ??
              'Wildlife media unavailable.\nবন্যপ্রাণের মিডিয়া পাওয়া যায়নি।',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60),
        ),
      ),
    );
  }

  Widget _buildAttribution() {
    final media = _media;
    if (media == null) return const SizedBox.shrink();

    final parts = <String>[
      if (media.source.isNotEmpty) 'Source: ${media.source}',
      if (media.attribution != null && media.attribution!.isNotEmpty)
        media.attribution!,
    ];

    if (parts.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        parts.join(' • '),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 9,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 12. SCRAMBLED IMAGE GAME
//
// The old implementation used a fractional Image widget, which
// made the nine image pieces unreliable. This version renders
// nine true cropped rectangles from ONE source image.
// -------------------------------------------------------------

class ScrambledImageGame extends StatefulWidget {
  final List<String>? weeklySpecies;
  final int weeklySeed;

  const ScrambledImageGame(
      {super.key, this.weeklySpecies, this.weeklySeed = 0});

  @override
  State<ScrambledImageGame> createState() => _ScrambledImageGameState();
}

class _ScrambledImageGameState extends State<ScrambledImageGame> {
  final int _gridSize = 3;
  final math.Random _random = math.Random();

  late List<int> _tiles;
  String? _imageUrl;
  String _species = '';
  String _source = '';
  String? _attribution;
  bool _loading = true;
  bool _solved = false;

  @override
  void initState() {
    super.initState();
    _newPuzzle();
  }

  Future<void> _newPuzzle() async {
    // Weekly challenges pin the species pool served from the server.
    final speciesList = (widget.weeklySpecies != null &&
            widget.weeklySpecies!.isNotEmpty)
        ? widget.weeklySpecies!.toList()
        : WildlifeGameData.puzzleSpecies.toList()
      ..shuffle(_random);

    // Try to pick a species different from the current one if possible
    String species = speciesList.first;
    if (_species.isNotEmpty && speciesList.length > 1) {
      for (final s in speciesList) {
        if (s != _species) {
          species = s;
          break;
        }
      }
    }

    setState(() {
      _loading = true;
      _solved = false;
      _imageUrl = null;
      _species = species;
      _source = '';
      _attribution = null;
      _tiles = List.generate(_gridSize * _gridSize, (i) => i);
    });

    final media = await WildlifeMediaService.fetchPuzzleImage(species);

    if (!mounted) return;

    if (media?.imageUrl == null) {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Puzzle image could not be loaded. Please try again.\n'
                'ছবিটি লোড করা যায়নি। আবার চেষ্টা করুন।',
          ),
        ),
      );
      return;
    }

    final shuffled = List<int>.generate(
      _gridSize * _gridSize,
          (i) => i,
    );

    // Make sure a new puzzle isn't accidentally already solved.
    do {
      shuffled.shuffle(_random);
    } while (_isSolvedList(shuffled));

    setState(() {
      _imageUrl = media!.imageUrl;
      _source = media.source;
      _attribution = media.attribution;
      _loading = false;
      _tiles = shuffled;
    });
  }

  bool _isSolvedList(List<int> list) {
    for (int i = 0; i < list.length; i++) {
      if (list[i] != i) return false;
    }
    return true;
  }

  Future<void> _showSolvedDialog() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('Congratulations! (অভিনন্দন)'),
        content: Text(
          'You restored the image.\n'
              'আপনি ছবিটি জোড়া লাগিয়েছেন।\n\n'
              'Species: $_species',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Stay',
              style: TextStyle(color: Color(0xFF81C784)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _newPuzzle();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
            ),
            child: const Text('New Puzzle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        title: const Text('SCRAMBLED IMAGE'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'New puzzle',
            onPressed: _loading ? null : _newPuzzle,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF00E676),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = math.min(
              constraints.maxWidth - 32,
              constraints.maxHeight * 0.58,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_species.isNotEmpty)
                    Text(
                      _species,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Text(
                    'Drag and drop tiles to rearrange them\nটাইলস টেনে সঠিক জায়গায় বসিয়ে দিন',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: boardSize,
                    height: boardSize,
                    child: _loading
                        ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E676),
                      ),
                    )
                        : _buildPuzzleBoard(boardSize),
                  ),
                  const SizedBox(height: 12),
                  if (_source.isNotEmpty)
                    Text(
                      'Source: $_source'
                          '${_attribution == null ? '' : ' • $_attribution'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _onTileSwap(int fromIndex, int toIndex) {
    if (_loading || _solved) return;

    setState(() {
      final temp = _tiles[fromIndex];
      _tiles[fromIndex] = _tiles[toIndex];
      _tiles[toIndex] = temp;
    });

    if (_isSolvedList(_tiles)) {
      setState(() => _solved = true);
      _showSolvedDialog();
    }
  }

  Widget _buildPuzzleBoard(double boardSize) {
    final tileSize = boardSize / _gridSize;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.55),
          width: 2,
        ),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _tiles.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridSize,
        ),
        itemBuilder: (context, position) {
          final sourceTile = _tiles[position];
          final sourceRow = sourceTile ~/ _gridSize;
          final sourceCol = sourceTile % _gridSize;

          final tileWidget = Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.55),
                width: 1,
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: -sourceCol * tileSize,
                  top: -sourceRow * tileSize,
                  width: boardSize,
                  height: boardSize,
                  child: CachedNetworkImage(
                    imageUrl: _imageUrl!,
                    fit: BoxFit.fill,
                    width: boardSize,
                    height: boardSize,
                    placeholder: (context, url) =>
                    const ColoredBox(color: Colors.white10),
                    errorWidget: (context, url, error) =>
                    const ColoredBox(color: Colors.white10),
                  ),
                ),
              ],
            ),
          );

          return DragTarget<int>(
            onWillAcceptWithDetails: (details) => details.data != position,
            onAcceptWithDetails: (details) =>
                _onTileSwap(details.data, position),
            builder: (context, candidateData, rejectedData) {
              return Draggable<int>(
                data: position,
                feedback: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: tileSize,
                    height: tileSize,
                    child: tileWidget,
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: tileWidget),
                child: tileWidget,
              );
            },
          );
        },
      ),
    );
  }
}

class FullscreenProtectedImageViewer extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final String userEmail;

  const FullscreenProtectedImageViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.userEmail,
  });

  @override
  State<FullscreenProtectedImageViewer> createState() =>
      _FullscreenProtectedImageViewerState();
}

class _FullscreenProtectedImageViewerState
    extends State<FullscreenProtectedImageViewer> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _nextPhoto() {
    if (_currentIndex < widget.photos.length - 1) {
      setState(() {
        _currentIndex++;
      });
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    final signedUrl = supabase.storage
        .from('wildlife_gallery')
        .getPublicUrl(photo['storage_path']);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(
            '${photo['title'] ?? 'Gallery'} (${_currentIndex + 1}/${widget.photos.length})'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          PhotoView(
            imageProvider: CachedNetworkImageProvider(signedUrl),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.contained * 2.5,
          ),
          if (_currentIndex > 0)
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: _prevPhoto,
                  ),
                ),
              ),
            ),
          if (_currentIndex < widget.photos.length - 1)
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.white, size: 20),
                    onPressed: _nextPhoto,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 10. REALISTIC 3D PHYSICAL BOOK PAGE CURL ENGINE (ORIGINAL SMOOTH ANIMATION + SOUND)
// -------------------------------------------------------------
class ProtectedReaderScreen extends StatefulWidget {
  final String magazineId;
  final String title;
  final String userEmail;
  final int initialPage;

  const ProtectedReaderScreen(
      {super.key,
        required this.magazineId,
        required this.title,
        required this.userEmail,
        this.initialPage = 0});

  @override
  State<ProtectedReaderScreen> createState() => _ProtectedReaderScreenState();
}

class _ProtectedReaderScreenState extends State<ProtectedReaderScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _thumbScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final AudioPlayer _pageFlipAudioPlayer = AudioPlayer();

  List<String> _signedUrls = [];
  bool _isLoading = true;
  late int _currentPage;
  bool _showControls = true;

  late AnimationController _animController;
  double _flipProgress = 0.0;
  bool _isDragging = false;

  bool _enablePageFlipAnimation = true;
  bool _enablePageFlipSound = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _animController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
        lowerBound: -1.0,
        upperBound: 1.0,
        value: 0.0);
    _animController.addListener(() {
      setState(() {
        _flipProgress = _animController.value;
      });
    });

    _initAudioEngine();
    _fetchSignedPageUrls().then((_) {
      _saveReadingProgress(_currentPage); // Save initial entry progress
    });
    _loadReaderSettings();
  }

  Future<void> _initAudioEngine() async {
    try {
      await _pageFlipAudioPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _pageFlipAudioPlayer.setVolume(1.0);
      await _pageFlipAudioPlayer.setSource(AssetSource('audio/page_flip.mp3'));
    } catch (_) {}
  }

  @override
  void dispose() {
    _animController.dispose();
    _thumbScrollController.dispose();
    _focusNode.dispose();
    _pageFlipAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enablePageFlipAnimation = prefs.getBool('pref_page_flip_anim') ?? true;
      _enablePageFlipSound = prefs.getBool('pref_page_flip_sound') ?? true;
    });
  }

  Future<void> _saveReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_page_flip_anim', _enablePageFlipAnimation);
    await prefs.setBool('pref_page_flip_sound', _enablePageFlipSound);
  }

  Future<void> _saveReadingProgress(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_read_mag_id', widget.magazineId);
    await prefs.setString('last_read_title', widget.title);
    await prefs.setInt('last_read_page', page);
    await prefs.setInt('last_read_total_pages', _signedUrls.length);
    if (_signedUrls.isNotEmpty) {
      await prefs.setDouble(
          'progress_${widget.magazineId}', (page + 1) / _signedUrls.length);
    }
  }

  Future<void> _fetchSignedPageUrls() async {
    try {
      final pages = await supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', widget.magazineId)
          .order('page_number', ascending: true);
      final List<String> urls = [];
      for (final p in pages) {
        final signedUrl = await supabase.storage
            .from('magazine_pages')
            .createSignedUrl(p['storage_path'], 120);
        urls.add(signedUrl);
      }
      setState(() {
        _signedUrls = urls;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _playPageFlipSound() async {
    if (_enablePageFlipSound) {
      try {
        await _pageFlipAudioPlayer.seek(Duration.zero);
        await _pageFlipAudioPlayer.resume();
      } catch (_) {}
    }
  }

  void _turnNext() {
    if (_currentPage >= _signedUrls.length - 1 || _animController.isAnimating) {
      return;
    }
    _playPageFlipSound();
    if (!_enablePageFlipAnimation) {
      setState(() {
        _currentPage++;
      });
      _saveReadingProgress(_currentPage);
      _syncThumbnails();
      return;
    }
    setState(() {
      _currentPage++;
    });
    _saveReadingProgress(_currentPage);
    _syncThumbnails();

    _animController.value = -1.0;
    _animController.animateTo(0.0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuad);
  }

  void _turnPrev() {
    if (_currentPage <= 0 || _animController.isAnimating) {
      return;
    }
    _playPageFlipSound();
    if (!_enablePageFlipAnimation) {
      setState(() {
        _currentPage--;
      });
      _saveReadingProgress(_currentPage);
      _syncThumbnails();
      return;
    }
    setState(() {
      _currentPage--;
    });
    _saveReadingProgress(_currentPage);
    _syncThumbnails();

    _animController.value = 1.0;
    _animController.animateTo(0.0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuad);
  }

  void _jumpToPage(int index) {
    if (index == _currentPage || _animController.isAnimating) {
      return;
    }
    _playPageFlipSound();
    setState(() {
      _currentPage = index;
    });
    _saveReadingProgress(index);
    _syncThumbnails();
  }

  void _syncThumbnails() {
    if (_thumbScrollController.hasClients) {
      final targetOffset =
          (_currentPage * 68.0) - (MediaQuery.of(context).size.width / 2) + 29;
      _thumbScrollController.animateTo(
        targetOffset.clamp(
            0.0, _thumbScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleHorizontalDragUpdate(
      DragUpdateDetails details, double screenWidth) {
    if (_isDragging && _signedUrls.length > 1) {
      final delta = details.primaryDelta ?? 0.0;
      setState(() {
        _flipProgress += (delta / screenWidth) * 1.35;
        _flipProgress = _flipProgress.clamp(-1.0, 1.0);
        _animController.value = _flipProgress;
      });
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    _isDragging = false;
    if (_flipProgress < -0.18 && _currentPage < _signedUrls.length - 1) {
      _playPageFlipSound();
      _turnNext();
    } else if (_flipProgress > 0.18 && _currentPage > 0) {
      _playPageFlipSound();
      _turnPrev();
    } else {
      _animController.animateTo(0.0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _openReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18221B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF00E676)),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reader Settings',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('(পাঠক সেটিংস)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF81C784))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                activeThumbColor: const Color(0xFF00E676),
                contentPadding: EdgeInsets.zero,
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3D Book Curl Flip Animation'),
                    Text('(কিন্ডল ৩ডি রিয়েল পেজ কার্ল)',
                        style:
                        TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                  ],
                ),
                subtitle: const Text(
                    'Realistic 3D spine and paper curling effect\n(বাস্তবধর্মী বইয়ের পাতার মতো স্পাইন বাঁক ও শেডিং)',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: _enablePageFlipAnimation,
                onChanged: (val) {
                  setModalState(() {
                    _enablePageFlipAnimation = val;
                  });
                  setState(() {
                    _enablePageFlipAnimation = val;
                  });
                  _saveReaderSettings();
                },
              ),
              const Divider(color: Colors.white12),
              SwitchListTile(
                activeThumbColor: const Color(0xFF00E676),
                contentPadding: EdgeInsets.zero,
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Page Flip Sound Effect'),
                    Text('(পৃষ্ঠা ওল্টানোর শব্দ)',
                        style:
                        TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                  ],
                ),
                subtitle: const Text(
                    'Mute audio for silent reading\n(শব্দহীন পাঠের জন্য মিউট করুন)',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: _enablePageFlipSound,
                onChanged: (val) {
                  setModalState(() {
                    _enablePageFlipSound = val;
                  });
                  setState(() {
                    _enablePageFlipSound = val;
                  });
                  _saveReaderSettings();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSinglePageImage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _signedUrls.length) {
      return const SizedBox.shrink();
    }
    return PhotoView(
        imageProvider: CachedNetworkImageProvider(_signedUrls[pageIndex]),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.contained * 1.85);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.pageDown) {
            _turnNext();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            _turnPrev();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _toggleControls();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isLoading
            ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF00E676)))
            : GestureDetector(
          onTap: _toggleControls,
          onHorizontalDragStart: (_) {
            _isDragging = true;
          },
          onHorizontalDragUpdate: (details) {
            _handleHorizontalDragUpdate(details, screenWidth);
          },
          onHorizontalDragEnd: (details) {
            _handleHorizontalDragEnd(details);
          },
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_flipProgress < 0 &&
                  _currentPage < _signedUrls.length - 1)
                _buildSinglePageImage(_currentPage + 1)
              else if (_flipProgress > 0 && _currentPage > 0)
                _buildSinglePageImage(_currentPage - 1)
              else
                _buildSinglePageImage(_currentPage),
              if (_flipProgress != 0.0 && _enablePageFlipAnimation) ...[
                // Soft shadow cast by the curling page onto the page beneath
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: _flipProgress < 0
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          end: Alignment.center,
                          colors: [
                            Colors.black.withValues(
                                alpha: (math.sin(_flipProgress.abs() *
                                    math.pi) *
                                    0.28)
                                    .clamp(0.0, 0.30)),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.35],
                        ),
                      ),
                    ),
                  ),
                ),
                Transform(
                  alignment: _flipProgress < 0
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(_flipProgress * (math.pi / 2.0)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSinglePageImage(_currentPage),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: _flipProgress < 0
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            end: _flipProgress < 0
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            colors: [
                              Colors.black.withValues(
                                  alpha: (_flipProgress.abs() * 0.12)
                                      .clamp(0.0, 0.14)),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.30],
                          ),
                        ),
                      ),
                      // Soft paper curl along the lifting edge: a gentle
                      // specular highlight rolling into a soft shadow,
                      // strongest mid-flip and settling to zero at rest.
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: _flipProgress < 0
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            end: Alignment.center,
                            colors: [
                              Colors.white.withValues(
                                  alpha: (math.sin(_flipProgress.abs() *
                                      math.pi) *
                                      0.16)
                                      .clamp(0.0, 0.18)),
                              Colors.black.withValues(
                                  alpha: (math.sin(_flipProgress.abs() *
                                      math.pi) *
                                      0.24)
                                      .clamp(0.0, 0.26)),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.055, 0.22],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              IgnorePointer(
                child: Center(
                  child: Transform.rotate(
                    angle: -0.45,
                    child: Text(
                      widget.userEmail,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.08),
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
              if (_showControls && _currentPage > 0)
                Positioned(
                  left: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        tooltip: 'Previous Page (পূর্ববর্তী পৃষ্ঠা)',
                        onPressed: _turnPrev,
                      ),
                    ),
                  ),
                ),
              if (_showControls && _currentPage < _signedUrls.length - 1)
                Positioned(
                  right: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white, size: 20),
                        tooltip: 'Next Page (পরবর্তী পৃষ্ঠা)',
                        onPressed: _turnNext,
                      ),
                    ),
                  ),
                ),
              if (_showControls)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AppBar(
                    backgroundColor: Colors.black.withValues(alpha: 0.85),
                    elevation: 0,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.title} (Page ${_signedUrls.isEmpty ? 0 : _currentPage + 1}/${_signedUrls.length})',
                          style: const TextStyle(fontSize: 15),
                        ),
                        Text(
                          '(পৃষ্ঠা ${_signedUrls.isEmpty ? 0 : _currentPage + 1}/${_signedUrls.length})',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF81C784)),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.tune_rounded,
                            color: Color(0xFF00E676)),
                        tooltip: 'Settings (সেটিংস)',
                        onPressed: _openReaderSettings,
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit_rounded),
                        tooltip: 'Toggle Controls (কন্ট্রোল লুকান)',
                        onPressed: _toggleControls,
                      ),
                    ],
                  ),
                ),
              if (_showControls && _signedUrls.isNotEmpty)
                Positioned(
                  bottom: 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    height: 94,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ListView.builder(
                      controller: _thumbScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _signedUrls.length,
                      itemBuilder: (context, index) {
                        final isSelected = index == _currentPage;

                        return Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: isSelected ? 58 : 44,
                            height: isSelected ? 80 : 60,
                            margin:
                            const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF00E676)
                                    : Colors.white24,
                                width: isSelected ? 2.5 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                BoxShadow(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                )
                              ]
                                  : [],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: GestureDetector(
                                onTap: () {
                                  _jumpToPage(index);
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: _signedUrls[index],
                                      fit: BoxFit.cover,
                                      placeholder: (c, u) => Container(
                                          color: Colors.black45),
                                      errorWidget: (c, u, e) =>
                                      const Icon(Icons.broken_image,
                                          size: 14),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        color: isSelected
                                            ? const Color(0xFF00E676)
                                            : Colors.black87,
                                        padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: isSelected ? 11 : 9,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.black
                                                : Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 13. ARANYAK PUBLISHED BOOK — 3D HARDBOUND VIEWER
// -------------------------------------------------------------

const String _aranyakFrontCoverAsset =
    'assets/images/banglar_ubhochar_front.png';
const String _aranyakBackCoverAsset = 'assets/images/banglar_ubhochar_back.png';
const String _aranyakPreviewPdfAsset =
    'assets/books/banglar_ubhochar_preview_enhanced.pdf';

class AranyakHardboundBookCard extends StatefulWidget {
  const AranyakHardboundBookCard({super.key});

  @override
  State<AranyakHardboundBookCard> createState() =>
      _AranyakHardboundBookCardState();
}

class _BookPart {
  final double z;
  final Widget child;
  _BookPart({required this.z, required this.child});
}

class _AranyakHardboundBookCardState extends State<AranyakHardboundBookCard> {
  double _rotationY = 0.0;
  bool _isDragging = false;

  void _updateRotation(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    setState(() {
      _rotationY += (details.primaryDelta ?? 0.0) / width * math.pi;
      _rotationY = _rotationY.clamp(-math.pi, math.pi);
    });
  }

  void _resetRotation() {
    setState(() {
      _rotationY = 0.0;
    });
  }

  void _openInside() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AranyakPdfReaderScreen(
          assetPath: _aranyakPreviewPdfAsset,
          title: 'বাংলার উভচর',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final double width = math.min(
              210.0,
              math.max(170.0, constraints.maxWidth - 48.0),
            );
            const double bookHeight = 280.0;

            return GestureDetector(
              onHorizontalDragStart: (_) {
                _isDragging = true;
              },
              onHorizontalDragUpdate: (details) {
                _updateRotation(details, width);
              },
              onHorizontalDragEnd: (_) {
                _isDragging = false;
              },
              onDoubleTap: _resetRotation,
              child: SizedBox(
                width: width + 40,
                height: bookHeight + 20,
                child: Center(
                  child: _buildThreeDimensionalBook(
                    width: width,
                    height: bookHeight,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 2),
        Text(
          _isDragging
              ? 'Drag to rotate • ঘুরিয়ে দেখুন'
              : 'Swipe / drag to rotate • সামনে ও পিছন দেখুন',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 9),
        ElevatedButton.icon(
          onPressed: _openInside,
          icon: const Icon(Icons.menu_book_rounded, size: 18),
          label: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Look Inside',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '(বইটি দেখুন)',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 9,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            elevation: 5,
          ),
        ),
      ],
    );
  }

  Widget _buildThreeDimensionalBook({
    required double width,
    required double height,
  }) {
    // ---------------------------------------------------------------
    // BOOK DIMENSIONS
    // ---------------------------------------------------------------

    const double bookThickness = 22.0;

    // The hardbound spine is slightly wider than the actual page block.
    const double spineThickness = 27.0;

    // Pages sit slightly inside the two hard covers.
    const double pageThickness = 19.0;

    final double angle = _rotationY;

    final double cosA = math.cos(angle);
    final double sinA = math.sin(angle);

    // Z position after the entire book is rotated around Y.
    double computeZ(double localX, double localZ) {
      return -localX * sinA + localZ * cosA;
    }

    final List<_BookPart> parts = [];

    // ---------------------------------------------------------------
    // BACK COVER
    // ---------------------------------------------------------------

    parts.add(
      _BookPart(
        z: computeZ(0, -bookThickness / 2),
        child: Opacity(
          opacity: (-cosA).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                0.0,
                0.0,
                -bookThickness / 2,
              ),
            child: _coverFace(
              _aranyakBackCoverAsset,
              width,
              height,
              isFront: false,
            ),
          ),
        ),
      ),
    );

    // ---------------------------------------------------------------
    // FRONT COVER
    // ---------------------------------------------------------------

    parts.add(
      _BookPart(
        z: computeZ(0, bookThickness / 2),
        child: Opacity(
          opacity: cosA.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                0.0,
                0.0,
                bookThickness / 2,
              ),
            child: _coverFace(
              _aranyakFrontCoverAsset,
              width,
              height,
              isFront: true,
            ),
          ),
        ),
      ),
    );

    // ---------------------------------------------------------------
    // GREEN HARDBOUND SPINE
    //
    // The spine occupies the LEFT side of the book.
    // It is deliberately thicker than the page block.
    // ---------------------------------------------------------------

    final double spineZFront =
        computeZ(-width / 2, bookThickness / 2);

    final double spineZBack =
        computeZ(-width / 2, -bookThickness / 2);

    parts.add(
      _BookPart(
        z: math.max(spineZFront, spineZBack) + 3.0,
        child: Opacity(
          // Visible equally when rotating left or right.
          // Reaches full opacity quickly so the spine never
          // stays hidden behind the covers at small angles.
          opacity: (sinA.abs() * 3.2).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                -width / 2,
                0.0,
                0.0,
              )
              // Exactly like the working page block: slightly less
              // than 90° keeps the plane non-degenerate in Flutter's
              // pseudo-3D projection pipeline.
              ..rotateY((math.pi / 2) - 0.025),
            child: Container(
              width: spineThickness,
              height: height,
              // Fallback gradient guarantees a green spine is always
              // painted, even before/if the custom painter runs.
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFF123A1A),
                    Color(0xFF245F2D),
                    Color(0xFF3F873F),
                    Color(0xFF2E6F35),
                    Color(0xFF123A1A),
                  ],
                  stops: [
                    0.0,
                    0.22,
                    0.50,
                    0.75,
                    1.0,
                  ],
                ),
              ),
              child: CustomPaint(
                painter: _HardboundSpinePainter(),
              ),
            ),
          ),
        ),
      ),
    );

    // ---------------------------------------------------------------
    // PAGE BLOCK / FORE-EDGE
    //
    // This is slightly narrower than the green hardbound structure.
    // ---------------------------------------------------------------

    final double pageZFront =
        computeZ(width / 2, bookThickness / 2);

    final double pageZBack =
        computeZ(width / 2, -bookThickness / 2);

    parts.add(
      _BookPart(
        z: math.max(pageZFront, pageZBack) + 0.8,
        child: Opacity(
          // IMPORTANT:
          // abs() makes the page block appear in BOTH directions.
          opacity: (sinA.abs() * 2.2).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                width / 2,
                0.0,
                0.0,
              )
              // Slightly less than 90° prevents the page block
              // from looking unnaturally razor-thin.
              ..rotateY((math.pi / 2) - 0.025),
            child: SizedBox(
              width: pageThickness,
              height: height - 7,
              child: CustomPaint(
                painter: _RealisticPageBlockPainter(),
              ),
            ),
          ),
        ),
      ),
    );

    // ---------------------------------------------------------------
    // SORT BY DEPTH
    // ---------------------------------------------------------------

    parts.sort(
      (a, b) => a.z.compareTo(b.z),
    );

    // ---------------------------------------------------------------
    // FINAL 3D BOOK
    // ---------------------------------------------------------------

    return Center(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          // Perspective.
          ..setEntry(3, 2, 0.0012)
          ..rotateY(angle),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: parts
                .map(
                  (part) => part.child,
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _coverFace(
      String asset,
      double width,
      double height, {
        required bool isFront,
      }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 18,
            spreadRadius: 1,
            offset: Offset(7, 9),
          ),
          BoxShadow(
            color: Colors.black38,
            blurRadius: 5,
            offset: Offset(-2, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.fill,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFF536B2F),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    isFront
                        ? 'বাংলার উভচর\nCover image missing'
                        : 'Back cover\nimage missing',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.14),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 14. LOCAL ENHANCED PDF READER
// -------------------------------------------------------------

class AranyakPdfReaderScreen extends StatefulWidget {
  final String assetPath;
  final String title;

  const AranyakPdfReaderScreen({
    super.key,
    required this.assetPath,
    required this.title,
  });

  @override
  State<AranyakPdfReaderScreen> createState() => _AranyakPdfReaderScreenState();
}

class _AranyakPdfReaderScreenState extends State<AranyakPdfReaderScreen> {
  pdfx.PdfDocument? _document;
  int _pageCount = 0;
  int _currentPage = 0;
  bool _loading = true;
  String? _error;
  final Map<int, Uint8List> _pageCache = {};
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _openPdf();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final double offset = _scrollController.offset;
      // Estimate page index based on average height + margin
      // Each page in ListView has margin (24) and some vertical padding
      // This is a rough estimation since pages can have different heights
      final int index = (offset / 450).floor().clamp(0, _pageCount - 1);
      if (index != _currentPage) {
        setState(() {
          _currentPage = index;
        });
      }
    }
  }

  Future<void> _openPdf() async {
    try {
      final ByteData data = await rootBundle.load(widget.assetPath);
      final pdfDocument =
      await pdfx.PdfDocument.openData(data.buffer.asUint8List());

      if (!mounted) {
        await pdfDocument.close();
        return;
      }

      setState(() {
        _document = pdfDocument;
        _pageCount = pdfDocument.pagesCount;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error opening PDF: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<Uint8List?> _renderPage(int pageNumber) async {
    final cached = _pageCache[pageNumber];
    if (cached != null) return cached;

    final document = _document;
    if (document == null) return null;

    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    try {
      final page = await document.getPage(pageNumber);
      if (!mounted) return null;
      final double renderWidth =
      (screenWidth * devicePixelRatio).clamp(900.0, 1800.0);
      final double renderHeight = renderWidth * page.height / page.width;

      final pageImage = await page.render(
        width: renderWidth,
        height: renderHeight,
        format: pdfx.PdfPageImageFormat.jpeg,
        quality: 92,
      );
      await page.close();

      if (pageImage == null) return null;

      final bytes = Uint8List.fromList(pageImage.bytes);
      _pageCache[pageNumber] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _document?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101510),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Enhanced Preview • উন্নত প্রাকদর্শন',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF81C784),
              ),
            ),
          ],
        ),
        actions: [
          if (!_loading && _pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  '${_currentPage + 1} / $_pageCount',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E676)),
            SizedBox(height: 14),
            Text(
              'Opening book preview...\nবইয়ের প্রাকদর্শন খোলা হচ্ছে...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_error != null || _document == null || _pageCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.redAccent,
                size: 52,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to open the preview PDF.\nপ্রাকদর্শন PDF খোলা যায়নি।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 20),
      itemCount: _pageCount,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;

        return FutureBuilder<Uint8List?>(
          future: _renderPage(pageNumber),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Container(
                height: 400,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                  color: Color(0xFF00E676),
                ),
              );
            }

            final bytes = snapshot.data;
            if (bytes == null) {
              return const SizedBox(
                height: 100,
                child: Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              );
            }

            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Container(
                margin: const EdgeInsets.only(bottom: 24, left: 12, right: 12),
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -------------------------------------------------------------
// 15. FREE BOOK PREVIEW SCREEN
// -------------------------------------------------------------
class FreeBookPreviewScreen extends StatelessWidget {
  final String title;
  final List<String> pageUrls;

  const FreeBookPreviewScreen(
      {super.key, required this.title, required this.pageUrls});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text('$title (Preview)'),
      ),
      body: PageView.builder(
        itemCount: pageUrls.length,
        itemBuilder: (context, index) {
          return PhotoView(
            imageProvider: CachedNetworkImageProvider(pageUrls[index]),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.contained * 2.5,
          );
        },
      ),
    );
  }
}

class _HardboundSpinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // -------------------------------------------------------------
    // MAIN GREEN CLOTH
    // -------------------------------------------------------------

    final Paint basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF123A1A),
          Color(0xFF245F2D),
          Color(0xFF3F873F),
          Color(0xFF2E6F35),
          Color(0xFF123A1A),
        ],
        stops: [
          0.0,
          0.22,
          0.50,
          0.75,
          1.0,
        ],
      ).createShader(rect);

    canvas.drawRect(
      rect,
      basePaint,
    );

    // -------------------------------------------------------------
    // SUBTLE CLOTH TEXTURE
    // -------------------------------------------------------------

    final Paint texturePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 0.45;

    for (double x = 1; x < size.width; x += 2.2) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        texturePaint,
      );
    }

    for (double y = 2; y < size.height; y += 3.0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        texturePaint,
      );
    }

    // -------------------------------------------------------------
    // DARK INNER EDGES
    // -------------------------------------------------------------

    final Paint darkEdgePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0x99091F0D),
          Color(0x00091F0D),
          Color(0x00091F0D),
          Color(0x99091F0D),
        ],
        stops: [
          0.0,
          0.18,
          0.82,
          1.0,
        ],
      ).createShader(rect);

    canvas.drawRect(
      rect,
      darkEdgePaint,
    );

    // -------------------------------------------------------------
    // CENTRAL SPINE HIGHLIGHT
    // -------------------------------------------------------------

    final Paint highlightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Color(0x2288C78A),
          Color(0x5588C78A),
          Color(0x2288C78A),
          Colors.transparent,
        ],
        stops: [
          0.20,
          0.38,
          0.50,
          0.62,
          0.80,
        ],
      ).createShader(rect);

    canvas.drawRect(
      rect,
      highlightPaint,
    );

    // -------------------------------------------------------------
    // NARROW RAISED SPINE RIDGE
    // -------------------------------------------------------------

    final double centerX = size.width * 0.5;

    final Paint ridgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(centerX - 1.3, 3),
      Offset(centerX - 1.3, size.height - 3),
      ridgePaint,
    );

    final Paint ridgeShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(centerX + 1.5, 3),
      Offset(centerX + 1.5, size.height - 3),
      ridgeShadowPaint,
    );

    // -------------------------------------------------------------
    // OUTER BORDER
    // -------------------------------------------------------------

    final Paint borderPaint = Paint()
      ..color = const Color(0xAA0B2A12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRect(
      Rect.fromLTWH(
        0.5,
        0.5,
        size.width - 1,
        size.height - 1,
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

class _RealisticPageBlockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // -------------------------------------------------------------
    // BASE PAGE BLOCK
    // -------------------------------------------------------------

    final Paint basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFFD8D5CC),
          Color(0xFFF8F7F1),
          Color(0xFFFFFEF8),
          Color(0xFFE2DED4),
        ],
        stops: [
          0.0,
          0.25,
          0.70,
          1.0,
        ],
      ).createShader(rect);

    canvas.drawRect(
      rect,
      basePaint,
    );

    // -------------------------------------------------------------
    // INDIVIDUAL PAGE EDGES
    //
    // Many very thin lines make it read as compressed sheets.
    // -------------------------------------------------------------

    final Paint pagePaint = Paint()
      ..color = const Color(0x665F5B52)
      ..strokeWidth = 0.35;

    const int pageCount = 90;

    for (int i = 1; i < pageCount; i++) {
      final double y =
          size.height * i / pageCount;

      // Tiny irregularity makes it less computer-perfect.
      final double offset =
          (i % 3) * 0.12;

      canvas.drawLine(
        Offset(0.5, y + offset),
        Offset(size.width - 0.5, y + offset),
        pagePaint,
      );
    }

    // -------------------------------------------------------------
    // SLIGHTLY STRONGER PAGE GROUPS
    // -------------------------------------------------------------

    final Paint groupPaint = Paint()
      ..color = const Color(0x806B675E)
      ..strokeWidth = 0.55;

    for (int i = 10; i < pageCount; i += 10) {
      final double y =
          size.height * i / pageCount;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        groupPaint,
      );
    }

    // -------------------------------------------------------------
    // WARM INNER SHADOW NEAR THE SPINE
    // -------------------------------------------------------------

    final Paint spineSideShadow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0x664A463D),
          Color(0x002E2B26),
        ],
      ).createShader(rect);

    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        size.width * 0.28,
        size.height,
      ),
      spineSideShadow,
    );

    // -------------------------------------------------------------
    // OUTER PAGE EDGE HIGHLIGHT
    // -------------------------------------------------------------

    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..strokeWidth = 0.8;

    canvas.drawLine(
      Offset(size.width - 1.0, 2),
      Offset(size.width - 1.0, size.height - 2),
      highlightPaint,
    );

    // -------------------------------------------------------------
    // TOP AND BOTTOM COMPRESSED SHADOW
    // -------------------------------------------------------------

    final Paint edgeShadow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x554A463D),
          Colors.transparent,
          Colors.transparent,
          Color(0x554A463D),
        ],
        stops: [
          0.0,
          0.08,
          0.92,
          1.0,
        ],
      ).createShader(rect);

    canvas.drawRect(
      rect,
      edgeShadow,
    );

    // -------------------------------------------------------------
    // VERY FINE OUTER BORDER
    // -------------------------------------------------------------

    final Paint borderPaint = Paint()
      ..color = const Color(0x66716D64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    canvas.drawRect(
      Rect.fromLTWH(
        0.3,
        0.3,
        size.width - 0.6,
        size.height - 0.6,
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

// -------------------------------------------------------------
// WHATSAPP LOGO (official asset: assets/images/whatsapp.png)
// -------------------------------------------------------------
class _WhatsAppLogo extends StatelessWidget {
  final double size;

  const _WhatsAppLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/whatsapp.png',
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => const Icon(Icons.chat_rounded,
            color: Color(0xFF25D366), size: 30),
      ),
    );
  }
}
