import 'dart:async';
import 'package:flutter/material.dart';
import '../models/content_protection_models.dart';
import '../services/content_protection_service.dart';
import '../services/protection_session_service.dart';
import 'capture_blocked_overlay.dart';
import 'protected_watermark.dart';

/// Visual container that wraps protected views with watermark overlay,
/// capture blocking, and lifecycle obscurity handlers.
class ProtectedContent extends StatefulWidget {
  final Widget child;
  final String userIdentity;
  final ContentProtectionScope scope;
  final String contentId;
  final bool enableWatermark;
  final double watermarkOpacity;

  const ProtectedContent({
    super.key,
    required this.child,
    required this.userIdentity,
    required this.scope,
    required this.contentId,
    this.enableWatermark = true,
    this.watermarkOpacity = 0.08,
  });

  @override
  State<ProtectedContent> createState() => _ProtectedContentState();
}

class _ProtectedContentState extends State<ProtectedContent>
    with WidgetsBindingObserver {
  bool _isAppInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ContentProtectionService.enable(
      scope: widget.scope,
      contentId: widget.contentId,
      userId: widget.userIdentity,
      enableWatermark: widget.enableWatermark,
      watermarkOpacity: widget.watermarkOpacity,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ContentProtectionService.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    setState(() {
      _isAppInBackground = (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CaptureState>(
      valueListenable: ContentProtectionService.captureStateNotifier,
      builder: (context, captureState, child) {
        final bool isCaptureActive =
            captureState == CaptureState.captured || captureState == CaptureState.recording;

        if (isCaptureActive || _isAppInBackground) {
          return const CaptureBlockedOverlay();
        }

        final session = ProtectionSessionService.currentSession;

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (widget.enableWatermark)
              ProtectedWatermark(
                identity: widget.userIdentity,
                sessionId: session?.sessionId,
                opacity: widget.watermarkOpacity,
              ),
          ],
        );
      },
    );
  }
}
