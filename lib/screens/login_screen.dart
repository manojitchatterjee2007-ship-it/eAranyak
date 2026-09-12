import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../widgets/animated_logo.dart';
import '../widgets/keyboard_press_effect.dart';

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

  @override
  void dispose() {
    _phoneOrEmailCtrl.dispose();
    _optionalEmailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
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
      backgroundColor: const Color(0xFF0D1410),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AnimatedEAranyakLogo(size: 160),
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
                        onPressed: () {
                          SoundService.playButtonSound();
                          _forgotPassword();
                        },
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
                height: 62,
                child: KeyboardPressEffect(
                  onTap: _isLoading
                      ? null
                      : () {
                          _submitAuth();
                        },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_isSignUp ? 'Register' : 'Login',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                              Text(_isSignUp ? '(নিবন্ধন করুন)' : '(প্রবেশ করুন)',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white70)),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  SoundService.playButtonSound();
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
    );
  }
}
