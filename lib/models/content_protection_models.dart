/// Scope of content being protected.
enum ContentProtectionScope {
  magazine,
  gallery,
  bookPreview,
  custom,
}

/// Capture or recording state reported by native platforms or runtime detectors.
enum CaptureState {
  normal,
  captured,
  recording,
  screenshotDetected,
  blocked,
}

/// Configuration options for active protection sessions.
class ContentProtectionConfig {
  final ContentProtectionScope scope;
  final String contentId;
  final String? userId;
  final bool enableWatermark;
  final bool enableCaptureBlocking;
  final bool blurInAppSwitcher;
  final double watermarkOpacity;

  const ContentProtectionConfig({
    required this.scope,
    required this.contentId,
    this.userId,
    this.enableWatermark = true,
    this.enableCaptureBlocking = true,
    this.blurInAppSwitcher = true,
    this.watermarkOpacity = 0.08,
  });
}

/// Active protection session information.
class ProtectionSession {
  final String sessionId;
  final ContentProtectionScope scope;
  final String contentId;
  final String? userId;
  final DateTime createdAt;
  final DateTime expiresAt;

  ProtectionSession({
    required this.sessionId,
    required this.scope,
    required this.contentId,
    this.userId,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'scope': scope.name,
        'content_id': contentId,
        'user_id': userId,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };
}

/// Details of a security event (e.g. screenshot attempt, capture state change).
class ProtectionSecurityEvent {
  final String eventType;
  final String? sessionId;
  final String? userId;
  final Map<String, dynamic> details;
  final DateTime timestamp;

  ProtectionSecurityEvent({
    required this.eventType,
    this.sessionId,
    this.userId,
    required this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'event_type': eventType,
        'session_id': sessionId,
        'user_id': userId,
        'details': details,
        'timestamp': timestamp.toIso8601String(),
      };
}
