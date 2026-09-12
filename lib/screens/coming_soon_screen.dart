import 'package:flutter/material.dart';
import '../widgets/keyboard_press_effect.dart';
import '../services/sound_service.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String titleBengali;
  final String descriptionBengali;
  final IconData icon;
  final String? assetPath;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.titleBengali,
    required this.descriptionBengali,
    required this.icon,
    this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon Container with subtle glow
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
                  child: assetPath != null
                      ? Image.asset(
                          assetPath!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        )
                      : Icon(
                          icon,
                          size: 52,
                          color: const Color(0xFF00E676),
                        ),
                ),
              ),
              const SizedBox(height: 28),

              // Bengali Title
              Text(
                titleBengali,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),

              // English Title Suffix
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF81C784),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),

              // Bengali Description
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF18221B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  descriptionBengali,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // "শীঘ্রই আসছে..." Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E676)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: Color(0xFF00E676),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'শীঘ্রই আসছে... (Coming Soon)',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // Go Back Button
              KeyboardPressEffect(
                onTap: () {
                  SoundService.playButtonSound();
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
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
