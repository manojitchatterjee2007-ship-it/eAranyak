import 'package:flutter/material.dart';

import '../widgets/keyboard_press_effect.dart';
import '../services/sound_service.dart';

/// About Us page — a mix of the old dialog write-up (exact same text)
/// and the current page look (glowing icon container, page navigation).
class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'About Us',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon Container with subtle glow (current look)
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF142419),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.25),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/about_us.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title — same as the old dialog
              const Text(
                'About us - আমাদের সম্বন্ধে',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 20),

              // Write-up — EXACT same text as the previous version
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF18221B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  'eআরণ্যক - প্রকৃতি, বন্যপ্রাণী এবং পরিবেশ সম্পর্কে জানার, শেখার ও ভালোবাসার একটি ডিজিটাল উদ্যোগ। আমাদের লক্ষ্য হলো বাংলাভাষী মানুষের কাছে প্রকৃতির বিস্ময়কর জগৎকে সহজ, আকর্ষণীয় এবং আনন্দদায়কভাবে পৌঁছে দেওয়া। ছবি, লেখা, পাখির ডাক, খেলা এবং বিভিন্ন শিক্ষামূলক উপস্থাপনার মাধ্যমে আমরা মানুষ ও প্রকৃতির মধ্যে আরও গভীর সংযোগ গড়ে তুলতে চাই।',
                  textAlign: TextAlign.justify,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 32),

              // Go Back Button (current look)
              KeyboardPressEffect(
                onTap: () {
                  SoundService.playButtonSound();
                  Navigator.pop(context);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'ফিরে যান (Back)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
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
