import 'package:flutter/material.dart';

/// Dynamic session-bound watermark widget for eআরণ্যক protected content.
class ProtectedWatermark extends StatelessWidget {
  final String identity;
  final String? sessionId;
  final double opacity;

  const ProtectedWatermark({
    super.key,
    required this.identity,
    this.sessionId,
    this.opacity = 0.08,
  });

  String _formatDate() {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    return '$day/$month/${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final userLabel = identity.trim().isEmpty ? 'READER' : identity.trim();
    final sessLabel = sessionId != null ? ' • SESS: ${sessionId!.substring(0, sessionId!.length.clamp(0, 10))}' : '';
    final dateLabel = _formatDate();

    final line1 = 'eআরণ্যক  •  $userLabel$sessLabel  •  $dateLabel  •  PROTECTED';
    final line2 = 'PROTECTED • eআরণ্যক • COPYRIGHT RESERVED • $userLabel';
    final line3 = 'eআরণ্যক • READER: $userLabel • $dateLabel';

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Transform.rotate(
                      angle: -0.42,
                      child: Text(
                        line1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(opacity),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -constraints.maxWidth * 0.1,
                  right: -constraints.maxWidth * 0.1,
                  top: constraints.maxHeight * 0.20,
                  child: Transform.rotate(
                    angle: -0.42,
                    child: Text(
                      line2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(opacity * 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -constraints.maxWidth * 0.1,
                  right: -constraints.maxWidth * 0.1,
                  top: constraints.maxHeight * 0.75,
                  child: Transform.rotate(
                    angle: -0.42,
                    child: Text(
                      line3,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(opacity * 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
