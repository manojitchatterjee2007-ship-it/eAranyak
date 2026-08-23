import 'dart:async';
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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

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
            payload: latest.toString(),
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


// BACKGROUND MULTI-TASK UPLOAD MANAGER
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
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
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {} catch (_) {}
        }
      },
    );

    Workmanager().initialize(callbackDispatcher);
    Workmanager().registerPeriodicTask(
      "wildlife_news_fetch_task",
      "fetchWildlifeNewsBackground",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  runApp(const EAranyakApp());
}

final supabase = Supabase.instance.client;

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
      home: const AuthGate(),
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

  final GlobalKey<_BookshelfScreenState> _bookshelfKey =
  GlobalKey<_BookshelfScreenState>();
  final GlobalKey<_WildlifeGalleryScreenState> _galleryKey =
  GlobalKey<_WildlifeGalleryScreenState>();
  final GlobalKey<_HomeScreenState> _homeKey = GlobalKey<_HomeScreenState>();

  @override
  void initState() {
    super.initState();
    _initAndPlayBirdCall();
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
                  _switchTab(3);
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
            child: Opacity(
              opacity: 0.22,
              child: Image.asset('assets/images/tribute_bg.jpg',
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  errorBuilder: (c, e, s) => const SizedBox.shrink()),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0D1410).withValues(alpha: 0.40),
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

  final List<String> _animalAudioAssets = [
    'audio/tiger_roar.mp3',
    'audio/elephant_trumpet.mp3',
    'audio/deer_call.mp3',
    'audio/owl_hoot.mp3',
  ];

  final List<Map<String, dynamic>> _masterNewsPool = [
    {
      'title': 'গাছ লাগানোর ভুল পদক্ষেপে সাভানা ঘাসজমির পাখি বিপন্ন',
      'source': 'Mongabay India',
      'source_url':
      'https://india.mongabay.com/2026/07/when-trees-replace-grasslands-specialist-birds-lose-their-habitat/',
      'date_str': '০২ জুলাই, ২০২৬',
      'category': 'birds',
      'snippet':
      'মহারাষ্ট্রের সাভানা অঞ্চলে কৃত্রিম বনসৃজনের ফলে ভারতীয় কোর্সার ও টনি পিপিট পাখিদের বাসস্থান হারিয়ে যাওয়ার বৈজ্ঞানিক প্রমাণ...',
      'content':
      'ভারতের প্রাকৃতিক বাস্তুতন্ত্রে সাভানা ও উন্মুক্ত ঘাসজমিকে বহু দশক ধরে ব্রিটিশ ঔপনিবেশিক আমলের অবৈজ্ঞানিক ধারণা অনুযায়ী অনাবাদি বা পতিত জমি হিসেবে গণ্য করে অবাধ বৃক্ষরোপণ করা হয়েছে।\n\nসম্প্রতি পরিবেশ বিজ্ঞানী সিমরিন সিরুর পরিচালিত বিস্তারিত মাঠপর্যায়ের গবেষণায় স্পষ্ট প্রমাণিত হয়েছে যে, মহারাষ্ট্রের প্রাচীন সাভানা ঘাসজমিতে গ্লিরিসিডিয়ার মতো বিদেশি প্রজাতির গাছের কৃত্রিম বাগান গড়ে তোলার ফলে ঘাসজমির নিজস্ব বিশেষজ্ঞ পাখি প্রজাতি মারাত্মকভাবে বাস্তুচ্যুত হচ্ছে।'
    },
    {
      'title': 'সুরক্ষিত অরণ্যের বাইরেই কারাকালের তিন-চতুর্থাংশ বাসভূমি',
      'source': 'Mongabay India',
      'source_url':
      'https://india.mongabay.com/2026/07/caracal-prefer-ravines-open-natural-ecosystems-over-protected-areas/',
      'date_str': '০৯ জুলাই, ২০২৬',
      'category': 'carnivore',
      'snippet':
      'রণথম্বোর-ধোলপুর অঞ্চলে চম্বলের গভীর গিরিখাত ও কাঁটাঝোপ কারাকালের অস্তিত্ব রক্ষার মূল চাবিকাঠি...',
      'content':
      'ভারতের অন্যতম রহস্যময়, ক্ষিপ্র ও চরম বিপন্ন বন্য মার্জার প্রজাতি কারাকালের ওপর ন্যাশনাল টাইগার কনজারভেশন অথরিটি (NTCA) ও ওয়াইল্ডলাইফ ইনস্টিটিউট অফ ইন্ডিয়ার (WII) গবেষণায় অত্যন্ত উদ্বেগজনক তথ্য উঠে এসেছে।'
    },
    {
      'title': 'মেঘালয়ের খাসি পাহাড়ে শিকারী কলসি উদ্ভিদের বিবর্তন ও সংকট',
      'source': 'Sanctuary Nature Foundation',
      'source_url':
      'https://www.sanctuarynaturefoundation.org/article/predatory-pitcher-plants',
      'date_str': 'ফেব্রুয়ারি ২০২৪',
      'category': 'flora',
      'snippet':
      'ভারতের একমাত্র পতঙ্গভুক কলসি উদ্ভিদ নেপেন্থেস খাসিয়ানার অতিবেগুনি আলোর ফাঁদ ও ঔষধি গুরুত্ব...',
      'content':
      'মেঘালয়ের খাসি, জয়ন্তীয়া ও দক্ষিণ গারো পাহাড়ের অত্যন্ত পুষ্টিহীন, অম্লীয় ও নাইট্রোজেন-ঘাটতিযুক্ত পাহাড়ি মাটিতে টিকে থাকতে লক্ষ কোটি বছরের বিবর্তনে পতঙ্গ শিকারের অদ্ভুত রূপান্তর ঘটিয়েছে ভারতের একমাত্র আদিম কলসি উদ্ভিদ নেপেন্থেস খাসিয়ানা।'
    },
    {
      'title': 'শিল্পীদের তুলি ও প্রকৃতি সংরক্ষণের সুপ্রাচীন আত্মিক বন্ধন',
      'source': 'Sanctuary Nature Foundation',
      'source_url':
      'https://www.sanctuarynaturefoundation.org/article/your-canvas-awaits',
      'date_str': '১৮ জুন, ২০২৬',
      'category': 'art_eco',
      'snippet':
      'প্রাচীন গুহাচিত্র থেকে আধুনিক তথ্যচিত্র: শিল্প কীভাবে সংরক্ষণ আন্দোলনের মূল চালিকাশক্তি...',
      'content':
      'মানুষ ও বন্যপ্রাণের নিবিড় সহাবস্থানের ইতিহাস প্রায় ৫১ হাজার বছর আগের গুহাচিত্র থেকেই শিল্পের মাধ্যমে মূর্ত হয়ে উঠেছে।'
    },
    {
      'title': 'পরিবেশ রক্ষার লড়াইয়ে বিশ্ববরেণ্য অগ্রদূতদের ঐতিহাসিক পদচিহ্ন',
      'source': 'Sanctuary Nature Foundation',
      'source_url':
      'https://www.sanctuarynaturefoundation.org/article/on-the-shoulders-of-giants',
      'date_str': '০২ মে, ২০২৬',
      'category': 'history',
      'snippet':
      'র‌্যাচেল কার্সনের সাইলেন্ট স্প্রিং থেকে সুন্দরলাল বহুগুণার চিপকো আন্দোলন: এক অবিস্মরণীয় বিপ্লব...',
      'content':
      'আধুনিক পৃথিবীর পরিবেশ সংরক্ষণ আন্দোলন নিছক সরকারি সিদ্ধান্ত নয়, বরং কয়েকজন নির্ভীক বিজ্ঞানপ্রেমী ও সমাজসংস্কারকের আজীবন সংগ্রামের ওপর ভিত্তি করে গড়ে উঠেছে।'
    }
  ];

  List<Map<String, dynamic>> _visibleNews = [];

  @override
  void initState() {
    super.initState();
    _refreshVisibleNewsWindow();
    loadData();
    _loadContinueReadingSession();
    _startAutoNewsShufflingTimer();
  }

  @override
  void dispose() {
    _autoShuffleTimer?.cancel();
    _notificationAudioPlayer.dispose();
    super.dispose();
  }

  void _refreshVisibleNewsWindow() {
    final shuffled = List<Map<String, dynamic>>.from(_masterNewsPool)
      ..shuffle();
    setState(() {
      _visibleNews = shuffled.take(5).toList();
    });
  }

  void _startAutoNewsShufflingTimer() {
    _autoShuffleTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _triggerAnimalAcousticAlert();
      _refreshVisibleNewsWindow();
    });
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
    } catch (_) {}
  }

  Widget _buildSchematicIcon(Map<String, dynamic> item) {
    final String title = (item['title'] ?? '').toString().toLowerCase();
    final String category = (item['category'] ?? '').toString().toLowerCase();

    IconData icon = Icons.park_rounded;
    Color primary = const Color(0xFF00E676);
    Color secondary = const Color(0xFF142419);

    if (category == 'birds' || title.contains('পাখি')) {
      icon = Icons.flutter_dash_rounded;
      primary = const Color(0xFF64B5F6);
      secondary = const Color(0xFF0D253A);
    } else if (category == 'carnivore' || title.contains('কারাকাল')) {
      icon = Icons.pets_rounded;
      primary = const Color(0xFFFFB74D);
      secondary = const Color(0xFF33200A);
    } else if (category == 'flora' || title.contains('উদ্ভিদ')) {
      icon = Icons.eco_rounded;
      primary = const Color(0xFF81C784);
      secondary = const Color(0xFF162D1C);
    }

    return Container(
      width: 90,
      height: double.infinity,
      decoration: BoxDecoration(
        color: secondary,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
        border:
        Border(right: BorderSide(color: primary.withValues(alpha: 0.25))),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
              size: const Size(90, 180),
              painter: SchematicGridPainter(accentColor: primary)),
          Icon(icon, size: 40, color: primary),
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
                    Text('Current Happenings & Wildlife News',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(left: 28),
                  child: Text(
                      '(চলতি ঘটনা ও বন্যপ্রাণ বার্তা - প্রতি ২ মিনিটে ৫টি নির্বাচিত খবর)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 175,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _visibleNews.length,
              itemBuilder: (context, index) {
                final item = _visibleNews[index];

                return Container(
                  width: 320,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: Card(
                    color: const Color(0xFF18221B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Colors.white12)),
                    elevation: 4,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    NewsDetailScreen(newsItem: item)));
                      },
                      child: Row(
                        children: [
                          _buildSchematicIcon(item),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E7D32),
                                          borderRadius:
                                          BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item['source']?.toString() ?? '',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Text(
                                        item['date_str']?.toString() ?? '',
                                        style: const TextStyle(
                                            fontSize: 9, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(item['title'] ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Text(item['snippet'] ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.white60)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_issues.first['title'] ?? 'eআরণ্যক',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                        '${_issues.first['issue_date']} • Total ${_issues.first['total_pages']} Pages',
                        style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black),
                      icon: const Icon(Icons.chrome_reader_mode_rounded),
                      label: const Text(
                          'Read Full Issue (সম্পূর্ণ সংখ্যাটি পড়ুন)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProtectedReaderScreen(
                                magazineId: _issues.first['id'],
                                title: _issues.first['title'],
                                userEmail: widget.userEmail),
                          ),
                        ).then((_) => _loadContinueReadingSession());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
      }
    } catch (_) {}
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
                      );
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
                                      child: Text(
                                        '${mag['issue_date']}\n${mag['total_pages']} Pages',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 9,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
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
  const WildlifeGalleryScreen(
      {super.key, required this.userEmail, required this.isAdmin});

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

      _titleCtrl.clear();
      _captionCtrl.clear();
      loadPhotos();
    } catch (_) {}
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
                child: InkWell(
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
class NewsDetailScreen extends StatelessWidget {
  final Map<String, dynamic> newsItem;
  const NewsDetailScreen({super.key, required this.newsItem});

  Future<void> _launchSourceUrl(BuildContext context) async {
    final urlStr = newsItem['source_url']?.toString();
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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                const SizedBox(width: 12),
                const Icon(Icons.access_time_rounded,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(newsItem['date_str']?.toString() ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              newsItem['title']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF18221B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.3)),
              ),
              child: Text(
                newsItem['snippet']?.toString() ?? '',
                style: const TextStyle(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF81C784),
                    height: 1.5),
              ),
            ),
            const Divider(color: Colors.white24, height: 36),
            Text(
              newsItem['content']?.toString() ?? '',
              style: const TextStyle(
                  fontSize: 16, color: Colors.white70, height: 1.85),
            ),
            const SizedBox(height: 36),
            InkWell(
              onTap: () {
                _launchSourceUrl(context);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF142419),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, color: Color(0xFF00E676)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Original Source: ${newsItem['source']}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                          const Text(
                              'Click here to read full original report in browser ↗\n(ব্রাউজারে সম্পূর্ণ মূল প্রতিবেদনটি পড়তে এখানে ট্যাপ করুন)',
                              style:
                              TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
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
  }
}

// -------------------------------------------------------------
// 9. FULLSCREEN PROTECTED IMAGE VIEWER WITH ARROWS
// -------------------------------------------------------------
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
// 10. REALISTIC PHYSICAL PAGE CURL (TRUE 3D PERSPECTIVE) – FIXED
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
    with TickerProviderStateMixin {
  final ScrollController _thumbScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final AudioPlayer _pageFlipAudioPlayer = AudioPlayer();

  List<String> _signedUrls = [];
  bool _isLoading = true;
  int _pageIndex = 0;
  bool _showControls = true;

  // --- 3D Flip State ---
  late AnimationController _flipController;
  late Animation<double> _flipCurved;
  bool _isFlipping = false;
  bool _flipForward = true;
  int _flipFrontPage = 0;
  int _flipBackPage = 0;

  bool _enablePageFlipAnimation = true;
  bool _enablePageFlipSound = true;

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.initialPage;
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    // easeInOut gives a natural paper-like rhythm: slow lift-off,
    // smooth mid-air curl, gentle settle.
    _flipCurved = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOut,
    );
    _flipController.addStatusListener(_onFlipStatus);

    _initAudioEngine();
    _fetchSignedPageUrls();
    _loadReaderSettings();
  }

  void _onFlipStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _pageIndex = _flipBackPage;
        _isFlipping = false;
      });
      _saveReadingProgress(_pageIndex);
      _syncThumbnails();
      _flipController.reset();
    }
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
    _flipController.dispose();
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

  // ---- Logic for Turning Pages ----
  void _turnNext() {
    if (_isFlipping || _pageIndex >= _signedUrls.length - 1) return;

    if (!_enablePageFlipAnimation) {
      _jumpToPage(_pageIndex + 1);
      return;
    }

    _playPageFlipSound();
    setState(() {
      _isFlipping = true;
      _flipForward = true;
      _flipFrontPage = _pageIndex;
      _flipBackPage = _pageIndex + 1;
    });
    _flipController.forward();
  }

  void _turnPrev() {
    if (_isFlipping || _pageIndex <= 0) return;

    if (!_enablePageFlipAnimation) {
      _jumpToPage(_pageIndex - 1);
      return;
    }

    _playPageFlipSound();
    setState(() {
      _isFlipping = true;
      _flipForward = false;
      _flipFrontPage = _pageIndex;
      _flipBackPage = _pageIndex - 1;
    });
    _flipController.forward();
  }

  void _jumpToPage(int index) {
    if (_isFlipping || index == _pageIndex) return;
    _playPageFlipSound();
    setState(() {
      _pageIndex = index;
    });
    _saveReadingProgress(index);
    _syncThumbnails();
  }

  void _syncThumbnails() {
    if (_thumbScrollController.hasClients) {
      final targetOffset = (_pageIndex * 68.0) - (MediaQuery.of(context).size.width / 2) + 29;
      _thumbScrollController.animateTo(
        targetOffset.clamp(0.0, _thumbScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
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

  // ---- Build a single page image ----
  Widget _buildSinglePageImage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _signedUrls.length) {
      return const SizedBox.shrink();
    }
    return PhotoView(
        imageProvider: CachedNetworkImageProvider(_signedUrls[pageIndex]),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.contained * 1.85);
  }

  // ===========================================================
  //  SINGLE-PAGE 3D PAGE-CURL FLIP READER
  //  Hinge is on the left edge for forward turns, right edge for
  //  backward turns. The turning leaf is a single page that curls
  //  in 3D, with a sweeping soft shadow cast on the page beneath
  //  and a glossy sheen on the curling leaf itself.
  // ===========================================================
  Widget _buildFlipReader() {
    if (_signedUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!_isFlipping) {
      return _buildSinglePageImage(_pageIndex);
    }

    return AnimatedBuilder(
      animation: _flipCurved,
      builder: (context, child) {
        final double t = _flipCurved.value; // 0.0 -> 1.0
        final double angle = t * math.pi;   // 0 -> 180°

        // Which face of the flipping page is currently visible.
        // First half: front face (page we are leaving). Second half:
        // back face (page we are arriving at) shown mirrored.
        final bool showFrontFace = t <= 0.5;

        // Rotation sign: forward turns hinge on the RIGHT and the page
        // lifts OUT toward the viewer (negative rotateY brings the free
        // edge toward +Z). Backward mirrors on the LEFT.
        final double rotation = _flipForward ? -angle : angle;

        // "Lift" of the paper: peaks at the halfway point (90°) and
        // falls back to zero at both ends, modelling paper rising off
        // the page and settling back down.
        final double lift = math.sin(t * math.pi);

        // Perspective vanishing point depth (smaller value = stronger 3D
        // push toward the viewer; larger = flatter, more 2D).
        const double perspective = 0.0018;

        // How far the leaf lifts toward the viewer at 90°. Reduced so
        // the page stays near the surface instead of flying at the reader.
        final double zLift = lift * 30.0;

        // A small sideways drift so the curl looks like it is being
        // pulled, not just rotated rigidly. Follows the swing direction:
        // forward drifts right (+), backward drifts left (-).
        final double drift = (_flipForward ? 1 : -1) * lift * 4.0;

        // Curl in the Z axis — the paper bend. Higher = more visible curl.
        final double curlZ = (_flipForward ? -1 : 1) * lift * 0.12;

        // A secondary X-axis curl offset that adds a “wave” to the page
        // edge, making it look like soft paper rather than a rigid card.
        final double curlY = (_flipForward ? -1 : 1) * lift * 0.28;

        // Shadow strength on the page beneath: strongest at mid-flip.
        final double shadowAmt = (0.5 - (t - 0.5).abs()) * 2.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Base page — the page we are revealing underneath.
            _buildSinglePageImage(_flipBackPage),

            // 2. Soft shadow cast onto the base page by the curling
            //    leaf. The gradient sweeps from the hinge edge inward.
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: _flipForward
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    end: _flipForward
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.45 * shadowAmt),
                      Colors.black.withValues(alpha: 0.18 * shadowAmt),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

            // 3. The flipping leaf — a single page curled in 3D.
            Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, perspective) // camera perspective (flatter)
                ..translateByDouble(drift, 0.0, zLift, 1.0)
                ..rotateY(rotation)
                ..rotateZ(curlZ)
                ..rotateX(curlY),
              alignment: _flipForward
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Visible face of the leaf.
                  showFrontFace
                      ? _buildSinglePageImage(_flipFrontPage)
                      : Transform(
                    transform: Matrix4.rotationY(math.pi),
                    alignment: Alignment.center,
                    child: _buildSinglePageImage(_flipBackPage),
                  ),

                  // Glossy sheen + inner curl shadow on the leaf itself.
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: _flipForward
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          end: _flipForward
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.22 * shadowAmt),
                            Colors.white.withValues(alpha: 0.14 * shadowAmt),
                            Colors.black.withValues(alpha: 0.22 * shadowAmt),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildFlipReader(),

              // Watermark
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

              // Navigation arrows (back)
              if (_showControls && _pageIndex > 0)
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

              // Navigation arrows (forward)
              if (_showControls && _pageIndex < _signedUrls.length - 1)
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

              // Top AppBar (controls)
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
                          '${widget.title} (Page ${_signedUrls.isEmpty ? 0 : _pageIndex + 1}/${_signedUrls.length})',
                          style: const TextStyle(fontSize: 15),
                        ),
                        Text(
                          '(পৃষ্ঠা ${_signedUrls.isEmpty ? 0 : _pageIndex + 1}/${_signedUrls.length})',
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

              // Thumbnail strip
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
                        final isSelected = index == _pageIndex;

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
