import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

/// Verified image processing pipeline for Daily Wildlife.
class DailyWildlifeArtService {
  DailyWildlifeArtService._();

  static const int maxSidePx = 480;

  static String _sanitize(String key) =>
      key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  static Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/daily_wildlife_oil');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _cachedFile(String cacheKey) async {
    final dir = await _cacheDir();
    return File('${dir.path}/${_sanitize(cacheKey)}.jpg');
  }

  /// Returns a cached processed file for [cacheKey], or null when no
  /// verified source image is available.
  static Future<File?> oilPaintedFile({
    required String cacheKey,
    required String? sourceImageUrl,
  }) async {
    if (sourceImageUrl == null || sourceImageUrl.trim().isEmpty) return null;
    final file = await _cachedFile(cacheKey);
    if (await file.exists()) {
      final len = await file.length();
      if (len > 2048) return file;
      try {
        await file.delete();
      } catch (_) {}
    }

    Uint8List sourceBytes;
    try {
      final res = await http
          .get(Uri.parse(sourceImageUrl.trim()))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200 || res.bodyBytes.length < 2048) return null;
      sourceBytes = res.bodyBytes;
    } catch (_) {
      return null;
    }

    try {
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) return null;

      final resized = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? maxSidePx : null,
        height: decoded.height >= decoded.width ? maxSidePx : null,
      );

      final jpgBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      if (jpgBytes.length < 2048) return null;

      await file.writeAsBytes(jpgBytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Clears one record's cached derivative (useful after an image changes).
  static Future<void> evict(String cacheKey) async {
    try {
      final file = await _cachedFile(cacheKey);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Best-effort warm-up without blocking UI.
  static void prewarm({
    required String cacheKey,
    required String? sourceImageUrl,
  }) {
    unawaited(oilPaintedFile(
      cacheKey: cacheKey,
      sourceImageUrl: sourceImageUrl,
    ).then((_) {
      debugPrint('DailyWildlifeArt: prewarmed $cacheKey');
    }).catchError((_) => null));
  }
}
