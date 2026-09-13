import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/animated_logo.dart';
import '../widgets/nature_background.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'login_screen.dart';
import 'user_bookshelf_screen.dart';
import 'nature_games_screen.dart';
import 'wildlife_gallery_screen.dart';
import 'admin_dashboard_screen.dart';
import 'online_book_store_screen.dart';
import 'podcast_screen.dart';
import 'vlog_screen.dart';
import 'tutorial_screen.dart';

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
  String _fullName = '';
  String _mobileNumber = '';
  String _appVersion = '2.1.0';
  bool _isAdmin = false;

  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<UserBookshelfScreenState> _bookshelfKey =
  GlobalKey<UserBookshelfScreenState>();
  final GlobalKey<WildlifeGalleryScreenState> _galleryKey =
  GlobalKey<WildlifeGalleryScreenState>();
  final GlobalKey<NatureGamesScreenState> _gamesKey =
  GlobalKey<NatureGamesScreenState>();

  @override
  void initState() {
    super.initState();
    _initAndPlayBirdCall();
    _fetchProfile();
    _initPackageInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final raw = PendingDeepLink.take();
      if (raw != null) {
        unawaited(handleNotificationPayload(raw));
      }
    });
  }

  Future<void> _fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('full_name, mobile_number, role')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _fullName = res['full_name'] ?? '';
          _mobileNumber = res['mobile_number'] ?? '';
          _isAdmin = res['role'] == 'admin';
        });
      }
    } catch (_) {}
  }

  Future<void> _initPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {}
  }

  Future<void> _initAndPlayBirdCall() async {
    if (SoundService.isMuted) return;
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
    if (index == 3) {
      _gamesKey.currentState?.refresh();
    }
    if (index == 4) {
      _galleryKey.currentState?.loadPhotos();
    }
  }

  void _openProfileDialog() {
    final nameCtrl = TextEditingController(text: _fullName);
    final mobileCtrl = TextEditingController(text: _mobileNumber);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF142419),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E676), width: 2.5),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.eco, color: Color(0xFF00E676), size: 34),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'আপনার প্রোফাইল আপডেট করুন',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const Text(
                  '(Update Your Profile)',
                  style: TextStyle(color: Color(0xFF81C784), fontSize: 11),
                ),
                const SizedBox(height: 20),

                // Name
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'পুরো নাম (Full Name)',
                    labelStyle: TextStyle(color: Color(0xFF00E676)),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person, color: Color(0xFF00E676)),
                    suffixIcon: Icon(Icons.edit, color: Colors.white54, size: 18),
                  ),
                ),
                const SizedBox(height: 14),

                // Mobile
                TextField(
                  controller: mobileCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'মোবাইল নম্বর (Mobile Number)',
                    labelStyle: TextStyle(color: Color(0xFF00E676)),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone, color: Color(0xFF00E676)),
                    suffixIcon: Icon(Icons.edit, color: Colors.white54, size: 18),
                  ),
                ),
                const SizedBox(height: 14),

                // Email (Read only)
                TextField(
                  enabled: false,
                  controller: TextEditingController(text: widget.userEmail),
                  style: const TextStyle(color: Colors.white70),
                  decoration: const InputDecoration(
                    labelText: 'ইমেল (Email)',
                    labelStyle: TextStyle(color: Colors.white54),
                    helperText: 'Email cannot be changed here',
                    helperStyle: TextStyle(color: Colors.grey, fontSize: 10),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 24),

                // Update Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDlgState(() => isSaving = true);
                            final messenger = ScaffoldMessenger.of(context);
                            final nav = Navigator.of(context);
                            try {
                              final user = supabase.auth.currentUser;
                              if (user != null) {
                                await supabase.from('profiles').upsert({
                                  'id': user.id,
                                  'full_name': nameCtrl.text.trim(),
                                  'mobile_number': mobileCtrl.text.trim(),
                                  'updated_at': DateTime.now().toIso8601String(),
                                });
                                await _fetchProfile();
                                if (mounted) {
                                  nav.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('প্রোফাইল আপডেট সম্পন্ন হয়েছে!')),
                                  );
                                }
                              }
                            } catch (e) {
                              setDlgState(() => isSaving = false);
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('আপডেট (Update)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 12),

                // Delete Account Text Button
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteAccount();
                  },
                  child: const Text('ডিলিট অ্যাকাউন্ট (Delete Account)', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('🗑 Delete Account (অ্যাকাউন্ট মুছে ফেলুন)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to completely delete your eআরণ্যক account and all data from servers?\n(আপনি কি নিশ্চিত যে আপনার অ্যাকাউন্ট এবং সমস্ত তথ্য সম্পূর্ণভাবে মুছে ফেলতে চান?)',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel (বাতিল)', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('profiles').delete().eq('id', user.id);
        await supabase.auth.signOut();
      }
    } catch (_) {}
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout (প্রস্থান)',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to sign out?\n(আপনি কি নিশ্চিতভাবে সাইন আউট করতে চান?)',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playButtonSound();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel (বাতিল)',
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              SoundService.playButtonSound();
              Navigator.pop(ctx);
              try {
                await supabase.auth.signOut();
              } catch (_) {}
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Logout (প্রস্থান)',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF18221B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Image.asset('assets/images/settings.png',
                      width: 40,
                      height: 40,
                      filterQuality: FilterQuality.medium),
                  const SizedBox(width: 10),
                  const Text('Settings',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(left: 50),
                child: Text('(সেটিংস)',
                    style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: SoundService.keyPressSoundNotifier,
                builder: (context, enabled, child) {
                  return SwitchListTile(
                    activeThumbColor: const Color(0xFF00E676),
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset('assets/images/baya_weaver_nest_button.png',
                          width: 24,
                          height: 24,
                          filterQuality: FilterQuality.medium),
                    ),
                    title: const Text('Key Press Sound'),
                    subtitle: const Text('(কী প্রেস সাউন্ড / বোতামের শব্দ)',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    value: enabled,
                    onChanged: (val) async {
                      await SoundService.setKeyPressSoundEnabled(val);
                      SoundService.playButtonSound();
                      setModalState(() {});
                    },
                  );
                },
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.asset('assets/images/contact.png',
                      width: 24,
                      height: 24,
                      filterQuality: FilterQuality.medium),
                ),
                title: const Text('Contact & Feedback'),
                subtitle: const Text('(যোগাযোগ ও মতামত)',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: () async {
                  SoundService.playButtonSound();
                  Navigator.pop(ctx);
                  final uri = Uri.parse('mailto:ekhonaranyak.edit@gmail.com');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.asset('assets/images/log_out.png',
                      width: 24,
                      height: 24,
                      filterQuality: FilterQuality.medium),
                ),
                title: const Text('Logout',
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                subtitle: const Text('(প্রস্থান)',
                    style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                onTap: () {
                  SoundService.playButtonSound();
                  Navigator.pop(ctx);
                  _confirmSignOut();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                SoundService.playButtonSound();
                Navigator.pop(ctx);
              },
              child: const Text('Close (বন্ধ করুন)',
                  style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _openAboutUsDialog() {
    SoundService.playButtonSound();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            Image.asset('assets/images/about_us.png',
                width: 72, height: 72, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            const SizedBox(height: 12),
            const Text('About us - আমাদের সম্বন্ধে',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'eআরণ্যক - প্রকৃতি, বন্যপ্রাণী এবং পরিবেশ সম্পর্কে জানার, শেখার ও ভালোবাসার একটি ডিজিটাল উদ্যোগ। আমাদের লক্ষ্য হলো বাংলাভাষী মানুষের কাছে প্রকৃতির বিস্ময়কর জগৎকে সহজ, আকর্ষণীয় এবং আনন্দদায়কভাবে পৌঁছে দেওয়া। ছবি, লেখা, পাখির ডাক, খেলা এবং বিভিন্ন শিক্ষামূলক উপস্থাপনার মাধ্যমে আমরা মানুষ ও প্রকৃতির মধ্যে আরও গভীর সংযোগ গড়ে তুলতে চাই।',
            style: TextStyle(fontSize: 15, color: Colors.white70, height: 1.6),
            textAlign: TextAlign.justify,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playButtonSound();
              Navigator.pop(ctx);
            },
            child: const Text('বন্ধ করুন (Close)',
                style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF141F17),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 50, bottom: 20, left: 16, right: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E2E23), Color(0xFF141F17)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              children: [
                const AnimatedEAranyakLogo(size: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'eআরণ্যক',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fullName.isNotEmpty ? 'স্বাগত, $_fullName' : 'স্বাগতম',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.userEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_note_rounded, color: Colors.white70, size: 20),
                      onPressed: _openProfileDialog,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Edit Profile',
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      onPressed: _deleteAccount,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Delete Account',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: Image.asset('assets/images/baya_weaver_nest_button.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Home'),
                  subtitle: const Text('(নীড়)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchTab(0);
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/bookworm_bookshelf.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('My Bookshelf'),
                  subtitle: const Text('(📖 আমার বুকশেলফ)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchTab(1);
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/library.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Library'),
                  subtitle: const Text('(📚 লাইব্রেরি)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchTab(2);
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/gallery.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Wildlife Gallery'),
                  subtitle: const Text('(চিত্রশালা)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchTab(4);
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/red_panda_games.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Nature Games'),
                  subtitle: const Text('(খেলার ছলে প্রকৃতি পাঠ)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchTab(3);
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/book_store.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Online Book Store'),
                  subtitle: const Text('(🛒 অনলাইন বই ঘর)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineBookStoreScreen()));
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/podcast.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Podcast'),
                  subtitle: const Text('(🎧 পডকাস্ট)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PodcastScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/nature_log.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Nature Vlogs'),
                  subtitle: const Text('(▶️ প্রকৃতির দর্পণ)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VlogScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/tutorials.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Tutorials'),
                  subtitle: const Text('(🎓 টিউটোরিয়াল)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TutorialScreen(),
                      ),
                    );
                  },
                ),
                if (_isAdmin)
                  ListTile(
                    leading: Image.asset('assets/images/owl_editor_glasses.png',
                        width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                    title: const Text('Editor Mode'),
                    subtitle: const Text('(সম্পাদক মোড)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(5);
                    },
                  ),
                ListTile(
                  leading: Image.asset('assets/images/about_us.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('About us - আমাদের সম্বন্ধে'),
                  onTap: () {
                    Navigator.pop(context);
                    _openAboutUsDialog();
                  },
                ),
                ListTile(
                  leading: Image.asset('assets/images/settings.png',
                      width: 48, height: 48, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                  title: const Text('Settings'),
                  subtitle: const Text('(সেটিংস)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _openSettingsDialog();
                  },
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Version $_appVersion',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomeScreen(
        key: _homeKey,
        userEmail: widget.userEmail,
        onNavigateToTab: (index) => _switchTab(index),
        fullName: _fullName,
      ),
      UserBookshelfScreen(key: _bookshelfKey, userEmail: widget.userEmail),
      LibraryScreen(userEmail: widget.userEmail),
      NatureGamesScreen(key: _gamesKey),
      WildlifeGalleryScreen(
          key: _galleryKey,
          userEmail: widget.userEmail,
          isAdmin: _isAdmin),
      if (_isAdmin)
        AdminDashboardScreen(
          onUploadComplete: () {
            _homeKey.currentState?.loadData();
          },
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.85),
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Image.asset('assets/images/options.png',
                width: 48,
                height: 48,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium),
            tooltip: 'Options / বিকল্প',
            onPressed: () {
              SoundService.playButtonSound();
              Scaffold.of(ctx).openDrawer();
            },
          ),
        ),
        title: const AnimatedEAranyakLogo(size: 56),
        actions: [
          IconButton(
            icon: Image.asset('assets/images/refresh.png',
                width: 36,
                height: 36,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium),
            tooltip: 'Refresh / রিফ্রেশ করুন',
            onPressed: () {
              SoundService.playButtonSound();
              _homeKey.currentState?.loadData();
              _bookshelfKey.currentState?.loadMagazines();
              _galleryKey.currentState?.loadPhotos();
              _gamesKey.currentState?.refresh();
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          const Positioned.fill(
            child: Opacity(
              opacity: 0.45,
              child: NatureBackgroundSwitcher(),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x260D1410), // 0.15 alpha
                    Color(0x0D0D1410), // 0.05 alpha
                    Color(0x590D1410), // 0.35 alpha
                    Color(0xBF0D1410), // 0.75 alpha
                  ],
                  stops: [0.0, 0.45, 0.85, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: IndexedStack(
              index: _currentIndex,
              children: pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0D1410),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          SoundService.playButtonSound();
          _switchTab(index);
        },
        items: [
          BottomNavigationBarItem(
              icon: Image.asset('assets/images/baya_weaver_nest_button.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  opacity: const AlwaysStoppedAnimation(.6)),
              activeIcon: Image.asset('assets/images/baya_weaver_nest_button.png',
                  width: 32, height: 32, fit: BoxFit.contain),
              label: 'Home\n(নীড়)'),
          BottomNavigationBarItem(
              icon: Image.asset('assets/images/bookworm_bookshelf.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  opacity: const AlwaysStoppedAnimation(.6)),
              activeIcon: Image.asset('assets/images/bookworm_bookshelf.png',
                  width: 32, height: 32, fit: BoxFit.contain),
              label: 'My Bookshelf\n(আমার বইয়ের তাক)'),
          BottomNavigationBarItem(
              icon: Image.asset('assets/images/library.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  opacity: const AlwaysStoppedAnimation(.6)),
              activeIcon: Image.asset('assets/images/library.png',
                  width: 32, height: 32, fit: BoxFit.contain),
              label: 'Library\n(লাইব্রেরি)'),
          BottomNavigationBarItem(
              icon: Image.asset('assets/images/red_panda_games.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  opacity: const AlwaysStoppedAnimation(.6)),
              activeIcon: Image.asset('assets/images/red_panda_games.png',
                  width: 32, height: 32, fit: BoxFit.contain),
              label: 'Games\n(খেলা)'),
          BottomNavigationBarItem(
              icon: Image.asset('assets/images/gallery.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  opacity: const AlwaysStoppedAnimation(.6)),
              activeIcon: Image.asset('assets/images/gallery.png',
                  width: 32, height: 32, fit: BoxFit.contain),
              label: 'Gallery\n(চিত্রশালা)'),
          if (_isAdmin)
            BottomNavigationBarItem(
                icon: Image.asset('assets/images/owl_editor_glasses.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                    opacity: const AlwaysStoppedAnimation(.6)),
                activeIcon: Image.asset('assets/images/owl_editor_glasses.png',
                    width: 32, height: 32, fit: BoxFit.contain),
                label: 'Editor\n(সম্পাদক)'),
        ],
      ),
    );
  }
}
