import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/content_protection_models.dart';
import 'protection_session_service.dart';

/// Central platform-agnostic Content Protection Service.
///
/// Pure service / orchestrator. NOT a Flutter Widget.
/// Manages native platform protection (Windows, Android, iOS, macOS, Linux, Web),
/// state changes, capture state stream, and audit logging.
class ContentProtectionService {
  static const MethodChannel _channel =
      MethodChannel('com.example.earanyak/content_protection');

  static bool _enabled = false;
  static ContentProtectionConfig? _activeConfig;

  static final ValueNotifier<CaptureState> _captureStateNotifier =
      ValueNotifier<CaptureState>(CaptureState.normal);

  static bool get isEnabled => _enabled;
  static ContentProtectionConfig? get activeConfig => _activeConfig;
  static ValueNotifier<CaptureState> get captureStateNotifier =>
      _captureStateNotifier;

  /// Initializes channel listener for platform events (e.g. screenshot taken, capture state changed).
  static void initialize() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onCaptureStateChanged':
        final bool isCaptured = call.arguments['isCaptured'] ?? false;
        final newState = isCaptured ? CaptureState.captured : CaptureState.normal;
        _captureStateNotifier.value = newState;

        if (isCaptured) {
          unawaited(ProtectionSessionService.logSecurityEvent(
            'screen_recording_detected',
            {'active_scope': _activeConfig?.scope.name},
          ));
        }
        break;

      case 'onScreenshotDetected':
        _captureStateNotifier.value = CaptureState.screenshotDetected;
        unawaited(ProtectionSessionService.logSecurityEvent(
          'screenshot_detected',
          {'active_scope': _activeConfig?.scope.name},
        ));

        // Reset back to normal after brief notification
        Future.delayed(const Duration(seconds: 2), () {
          if (_captureStateNotifier.value == CaptureState.screenshotDetected) {
            _captureStateNotifier.value = CaptureState.normal;
          }
        });
        break;
    }
  }

  /// Enables protection for the specified scope and content ID.
  static Future<void> enable({
    required ContentProtectionScope scope,
    required String contentId,
    String? userId,
    bool enableWatermark = true,
    bool enableCaptureBlocking = true,
    double watermarkOpacity = 0.08,
  }) async {
    _activeConfig = ContentProtectionConfig(
      scope: scope,
      contentId: contentId,
      userId: userId,
      enableWatermark: enableWatermark,
      enableCaptureBlocking: enableCaptureBlocking,
      watermarkOpacity: watermarkOpacity,
    );

    _enabled = true;
    _captureStateNotifier.value = CaptureState.normal;

    // Start protection session
    await ProtectionSessionService.startSession(
      scope: scope,
      contentId: contentId,
      userId: userId,
    );

    // Call platform native protection
    try {
      await _channel.invokeMethod('enableProtection', {
        'scope': scope.name,
        'contentId': contentId,
      });
    } on MissingPluginException {
      // Best effort fallback on unsupported runner
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ContentProtectionService] Native enable error: $e');
      }
    }
  }

  /// Disables protection and restores normal platform behavior.
  static Future<void> disable() async {
    if (!_enabled) return;

    _enabled = false;
    _activeConfig = null;
    _captureStateNotifier.value = CaptureState.normal;

    await ProtectionSessionService.endSession();

    try {
      await _channel.invokeMethod('disableProtection');
    } on MissingPluginException {
      // Best effort fallback
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ContentProtectionService] Native disable error: $e');
      }
    }
  }
}
