import 'package:flutter/material.dart';

/// Overlay widget displayed when screen capture or screen recording is active.
class CaptureBlockedOverlay extends StatelessWidget {
  final VoidCallback? onRetry;

  const CaptureBlockedOverlay({
    super.key,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D140F),
      padding: const EdgeInsets.all(28.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 2),
              ),
              child: const Icon(
                Icons.screen_lock_portrait_rounded,
                color: Colors.redAccent,
                size: 54,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Protected Content\nসুরক্ষিত সামগ্রী',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Displaying protected eআরণ্যক content is disabled while screen capture or recording is active.\n\nস্ক্রিন রেকর্ড বা ক্যাপচার সক্রিয় থাকায় সংরক্ষিত সামগ্রী প্রদর্শন বন্ধ রয়েছে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'Resume Viewing (পুনরায় শুরু করুন)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
