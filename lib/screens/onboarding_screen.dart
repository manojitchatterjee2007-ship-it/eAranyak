import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../widgets/animated_logo.dart';
import '../widgets/keyboard_press_effect.dart';

class OnboardingScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.userId, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('অনুগ্রহ করে আপনার পুরো নাম লিখুন (Please enter your full name)')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await supabase.from('profiles').upsert({
        'id': widget.userId,
        'full_name': name,
        'updated_at': DateTime.now().toIso8601String(),
      });
      
      await supabase.auth.updateUser(
        UserAttributes(data: {'full_name': name}),
      );
      
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        await Permission.notification.request();
        if (defaultTargetPlatform == TargetPlatform.android) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }

      widget.onComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AnimatedEAranyakLogo(size: 120),
              const SizedBox(height: 32),
              const Text(
                'স্বাগতম (Welcome!)',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'শুরু করার আগে আপনার প্রোফাইলটি গুছিয়ে নিন।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'আপনার পুরো নাম (Full Name)',
                  labelStyle: TextStyle(color: Color(0xFF00E676)),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E676))),
                  prefixIcon: Icon(Icons.person, color: Color(0xFF00E676)),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_active, color: Color(0xFF00E676)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'নতুন খবর ও গুরুত্বপূর্ণ আপডেট পেতে নোটিফিকেশন চালু করুন।',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.battery_saver, color: Color(0xFF00E676)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'নির্ভরযোগ্য নোটিফিকেশন পেতে অ্যাপটিকে ব্যাটারি অপ্টিমাইজেশন থেকে বাদ দিন।',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: KeyboardPressEffect(
                  onTap: _isLoading ? null : _submit,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('চালিয়ে যান (Continue)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('সিস্টেম সেটিংস খুলুন (Open Settings)', style: TextStyle(color: Color(0xFF81C784))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
