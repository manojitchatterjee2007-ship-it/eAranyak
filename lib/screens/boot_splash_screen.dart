import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../widgets/animated_logo.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'main_navigation_shell.dart';

class BootSplash extends StatefulWidget {
  const BootSplash({super.key});

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctrl;

  /// Local welcome-tone player. Kept strictly local to this screen so it can
  /// never overlap podcast/background audio: the player is created here,
  /// loops while the welcome screen is visible, and is stopped + disposed
  /// the moment the screen is disposed (i.e. when navigating to Home).
  AudioPlayer? _welcomePlayer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startWelcomeTone();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        // Hold the welcome message on screen for ~4.5-5s total
        // (1.2s logo animation + 3.6s readable pause) so users can
        // comfortably read it before transitioning to Home.
        Future.delayed(const Duration(milliseconds: 3600), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => const AuthGate()));
          }
        });
      }
    });
    _ctrl.forward();
  }

  /// Starts the looping welcome tone. Wrapped in try/catch so an audio
  /// failure can never block or delay app launch.
  Future<void> _startWelcomeTone() async {
    try {
      final player = AudioPlayer();
      _welcomePlayer = player;
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setVolume(1.0);
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('audio/welcome_tone.mp3'));
    } catch (e) {
      debugPrint('Welcome tone error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final player = _welcomePlayer;
    if (player == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // App backgrounded while the welcome screen is visible: silence the
      // tone; do not keep it running in the background.
      try {
        player.stop();
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      // Only resume if the welcome screen is still on screen.
      if (mounted && !_leaving) {
        try {
          player.resume();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _leaving = true;
    WidgetsBinding.instance.removeObserver(this);
    // Disposing the player stops playback immediately — the welcome sound
    // never continues into HomeScreen, and no player object is leaked.
    try {
      _welcomePlayer?.dispose();
    } catch (_) {}
    _welcomePlayer = null;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Larger logo on the welcome screen
          const AnimatedEAranyakLogo(size: 200),
          const SizedBox(height: 28),
          // Line 1: brand name
          const Text(
            'এখন আরণ্যক',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          // Thin decorative divider (1 -> 2)
          const SizedBox(height: 18),
          _splashDivider(),
          const SizedBox(height: 18),
          // Line 2: tagline
          const Text(
            'বাংলা ভাষায় অরণ্যযাপন',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF00E676),
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          // Thin decorative divider (2 -> 3)
          const SizedBox(height: 18),
          _splashDivider(),
          const SizedBox(height: 18),
          // Line 3: attribution with logo
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRect(
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 0.90,
                  heightFactor: 0.90,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      -1,  0,  0,  0, 255,
                       0, -1,  0,  0, 255,
                       0,  0, -1,  0, 255,
                      -0.33, -0.33, -0.33, 0, 255,
                    ]),
                    child: Image.asset(
                      'assets/images/logo.jpeg',
                      height: 30,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const Text(
                ' পত্রিকার একটি ডিজিটাল নিবেদন',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  }

  /// Thin horizontal decorative line: fades in/out from both ends,
  /// centred — matches the elegant divider style of the reference.
  static Widget _splashDivider() => Container(
        height: 1,
        width: 190,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF00E676).withValues(alpha: 0.0),
              const Color(0xFF00E676).withValues(alpha: 0.75),
              const Color(0xFF00E676).withValues(alpha: 0.0),
            ],
          ),
        ),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        return ProfileCheckGate(userId: session.user.id, email: session.user.email ?? '');
      },
    );
  }
}

class ProfileCheckGate extends StatefulWidget {
  final String userId;
  final String email;
  const ProfileCheckGate({super.key, required this.userId, required this.email});

  @override
  State<ProfileCheckGate> createState() => _ProfileCheckGateState();
}

class _ProfileCheckGateState extends State<ProfileCheckGate> {
  bool _loading = true;
  String? _fullName;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      final res = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', widget.userId)
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _fullName = res?['full_name'];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1410),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
      );
    }

    if (_fullName == null || _fullName!.isEmpty) {
      return OnboardingScreen(
        userId: widget.userId, 
        onComplete: () {
          setState(() => _loading = true);
          _checkProfile();
        }
      );
    }

    return MainNavigationShell(userEmail: widget.email.toLowerCase().trim());
  }
}
