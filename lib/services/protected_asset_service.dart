import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles authenticated, short-lived asset URL generation and anti-scraping controls.
class ProtectedAssetService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Client-side rate-limiting tracker
  static final List<DateTime> _requestTimestamps = [];
  static const int _maxRequestsPerMinute = 120; // Max page/image requests per min

  // Short-lived in-memory URL cache: storagePath -> (signedUrl, expiresAt)
  static final Map<String, _CachedSignedUrl> _urlCache = {};

  /// Checks if request rate is within safe bounds to block rapid automated scraping.
  static bool _checkRateLimit() {
    final now = DateTime.now();
    _requestTimestamps.removeWhere(
        (ts) => now.difference(ts) > const Duration(minutes: 1));

    if (_requestTimestamps.length >= _maxRequestsPerMinute) {
      if (kDebugMode) {
        debugPrint('[ProtectedAssetService] Rate limit threshold reached');
      }
      return false;
    }

    _requestTimestamps.add(now);
    return true;
  }

  /// Obtains a short-lived signed URL for a protected storage asset.
  /// [expiresInSeconds] defaults to 120 seconds for maximum security.
  static Future<String?> getSignedUrl({
    required String bucket,
    required String storagePath,
    int expiresInSeconds = 120,
  }) async {
    if (storagePath.trim().isEmpty) return null;

    if (!_checkRateLimit()) {
      throw Exception('Rate limit exceeded for asset requests. Please slow down.');
    }

    // Check memory cache
    final cached = _urlCache[storagePath];
    if (cached != null && !cached.isExpiringSoon) {
      return cached.signedUrl;
    }

    try {
      final signedUrl = await _supabase.storage
          .from(bucket)
          .createSignedUrl(storagePath.trim(), expiresInSeconds);

      final expiresAt = DateTime.now().add(Duration(seconds: expiresInSeconds));
      _urlCache[storagePath] = _CachedSignedUrl(signedUrl, expiresAt);

      return signedUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProtectedAssetService] Error obtaining signed URL: $e');
      }
      return null;
    }
  }

  /// Prefetches signed URLs for a batch of assets (e.g. magazine pages).
  static Future<Map<String, String>> getBatchSignedUrls({
    required String bucket,
    required List<String> storagePaths,
    int expiresInSeconds = 120,
  }) async {
    final Map<String, String> result = {};

    for (final path in storagePaths) {
      final url = await getSignedUrl(
        bucket: bucket,
        storagePath: path,
        expiresInSeconds: expiresInSeconds,
      );
      if (url != null) {
        result[path] = url;
      }
    }

    return result;
  }

  /// Clears in-memory asset URL cache on logout or session end.
  static void clearCache() {
    _urlCache.clear();
    _requestTimestamps.clear();
  }
}

class _CachedSignedUrl {
  final String signedUrl;
  final DateTime expiresAt;

  _CachedSignedUrl(this.signedUrl, this.expiresAt);

  /// True if expired or expiring in less than 20 seconds
  bool get isExpiringSoon =>
      DateTime.now().add(const Duration(seconds: 20)).isAfter(expiresAt);
}
