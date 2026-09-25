import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/content_protection_models.dart';

/// Manages short-lived, authenticated protection sessions and audit events.
class ProtectionSessionService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static ProtectionSession? _currentSession;

  static ProtectionSession? get currentSession => _currentSession;

  /// Starts a new protection session for the specified scope and content.
  static Future<ProtectionSession> startSession({
    required ContentProtectionScope scope,
    required String contentId,
    String? userId,
    Duration duration = const Duration(hours: 2),
  }) async {
    final now = DateTime.now().toUtc();
    final effectiveUserId = userId ?? _supabase.auth.currentUser?.id;
    final sessionId = 'sess_${now.millisecondsSinceEpoch}_${(1000 + (now.microsecond % 9000))}';

    final session = ProtectionSession(
      sessionId: sessionId,
      scope: scope,
      contentId: contentId,
      userId: effectiveUserId,
      createdAt: now,
      expiresAt: now.add(duration),
    );

    _currentSession = session;

    // Log session asynchronously to server if authenticated
    unawaited(_logSessionToServer(session));

    return session;
  }

  /// Ends the current protection session.
  static Future<void> endSession() async {
    final session = _currentSession;
    _currentSession = null;

    if (session != null) {
      unawaited(_logSecurityEvent('session_ended', {
        'session_id': session.sessionId,
        'content_id': session.contentId,
      }));
    }
  }

  /// Logs a security event (e.g. screenshot, capture detected, rate limit).
  static Future<void> logSecurityEvent(
    String eventType,
    Map<String, dynamic> details,
  ) async {
    await _logSecurityEvent(eventType, details);
  }

  static Future<void> _logSessionToServer(ProtectionSession session) async {
    try {
      if (_supabase.auth.currentUser != null) {
        await _supabase.from('protection_sessions').insert(session.toJson());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProtectionSessionService] Session log notice: $e');
      }
    }
  }

  static Future<void> _logSecurityEvent(
    String eventType,
    Map<String, dynamic> details,
  ) async {
    try {
      final user = _supabase.auth.currentUser;
      final payload = ProtectionSecurityEvent(
        eventType: eventType,
        sessionId: _currentSession?.sessionId,
        userId: user?.id,
        details: details,
      ).toJson();

      if (user != null) {
        await _supabase.from('protection_security_events').insert(payload);
      }
    } catch (_) {
      // Security logging fail-safe
    }
  }
}
