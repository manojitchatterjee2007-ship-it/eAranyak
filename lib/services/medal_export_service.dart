import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

import 'medal_composer_service.dart';

/// Outcome of a save or share attempt, surfaced to the participant as explicit
/// success or error feedback.
class MedalExportOutcome {
  final bool success;

  /// Human-readable bilingual message for a snackbar.
  final String message;

  /// Set on success: the gallery URI (save) or the share status (share).
  final String? location;

  const MedalExportOutcome._({
    required this.success,
    required this.message,
    this.location,
  });

  factory MedalExportOutcome.ok(String message, {String? location}) =>
      MedalExportOutcome._(success: true, message: message, location: location);

  factory MedalExportOutcome.failed(String message) =>
      MedalExportOutcome._(success: false, message: message);
}

/// Saves and shares generated medal PNGs.
///
/// Generated files live in the OS temporary directory and are pruned on every
/// new export so repeated generations cannot accumulate duplicates.
class MedalExportService {
  const MedalExportService._();

  static const String _albumPath = 'eAranyak/Medals';
  static const String _fileNamePrefix = 'earanyak_kishor_medal';
  static const int _maxRetainedFiles = 6;

  /// The MIME type used for both the gallery save and the share sheet.
  static const String pngMimeType = 'image/png';

  /// Writes [pngBytes] to the OS temp dir and verifies the file really exists
  /// and is a valid PNG before returning it.
  ///
  /// Returns null when the write could not be verified.
  static Future<File?> _writeVerifiedTempPng(
    Uint8List pngBytes, {
    required bool withBackground,
  }) async {
    final dir = await getTemporaryDirectory();
    final suffix = withBackground ? 'composed' : 'medal';
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('${dir.path}/$_fileNamePrefix$suffix$stamp.png');

    await file.writeAsBytes(pngBytes, flush: true);

    // Verify on disk: existence, non-zero length and the PNG magic number.
    if (!await file.exists()) return null;
    if (await file.length() < 8) return null;
    final handle = await file.open();
    try {
      final header = await handle.read(8);
      final isPng = header.length == 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47;
      if (!isPng) {
        await file.delete();
        return null;
      }
    } finally {
      await handle.close();
    }
    return file;
  }

  /// Deletes older generated medal files so the temp dir cannot grow unbounded.
  static Future<void> _pruneTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final matches = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.contains(_fileNamePrefix) && f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) =>
            b.statSync().modified.compareTo(a.statSync().modified));
      for (final stale in matches.skip(_maxRetainedFiles)) {
        try {
          await stale.delete();
        } catch (_) {
          // Best effort: a locked file must not abort the export.
        }
      }
    } catch (_) {
      // Pruning is an optimisation; never fail an export because of it.
    }
  }

  /// Saves [pngBytes] into the device gallery under `eAranyak/Medals`.
  ///
  /// Success is only reported when the platform returns a real saved URI, so a
  /// mere method call can never be mistaken for a completed download.
  static Future<MedalExportOutcome> saveToGallery(
    Uint8List pngBytes, {
    required int level,
    required bool withBackground,
  }) async {
    if (pngBytes.isEmpty) {
      return MedalExportOutcome.failed(
        'মেডেল তৈরি করা যায়নি। (The medal image could not be generated.)',
      );
    }
    try {
      final suffix = withBackground ? '_bg' : '';
      final result = await SaverGallery.saveImage(
        pngBytes,
        fileName: '${_fileNamePrefix}_level${level.clamp(1, 999)}$suffix.png',
        albumPath: _albumPath,
        quality: 100,
        skipIfExists: false,
      );

      final savedUri = result.savedUri;
      if (result.isSuccess && savedUri != null && savedUri.isNotEmpty) {
        await _pruneTempFiles();
        return MedalExportOutcome.ok(
          'মেডেল সেভ হয়েছে — গ্যালারিতে দেখুন।\n'
          '(Medal saved to your gallery.)',
          location: savedUri,
        );
      }
      return MedalExportOutcome.failed(
        'সেভ করা যায়নি: ${result.errorMessage ?? 'unknown error'}\n'
        '(Save failed: ${result.errorMessage ?? 'unknown error'})',
      );
    } catch (e) {
      return MedalExportOutcome.failed(
        'সেভ করা যায়নি। স্টোরেজ অনুমতি পরীক্ষা করুন।\n'
        '(Could not save the medal. Please check storage permission.)',
      );
    }
  }

  /// Opens the native share sheet with the actual generated PNG bytes.
  ///
  /// The bytes are first materialised into a verified temporary file so the
  /// share sheet receives real image data rather than a bare path string.
  static Future<MedalExportOutcome> shareImage(
    MedalRenderResult render, {
    required int level,
  }) async {
    if (render.pngBytes.isEmpty) {
      return MedalExportOutcome.failed(
        'শেয়ার করার জন্য ছবি তৈরি হয়নি।\n(No image available to share.)',
      );
    }
    try {
      final file = await _writeVerifiedTempPng(
        render.pngBytes,
        withBackground: render.width != render.height,
      );
      if (file == null) {
        return MedalExportOutcome.failed(
          'শেয়ার ফাইল তৈরি করা যায়নি।\n'
          '(Could not prepare the image file for sharing.)',
        );
      }

      final xFile = XFile.fromData(
        render.pngBytes,
        mimeType: pngMimeType,
        path: file.path,
        name: 'earanyak_kishor_medal_level$level.png',
      );

      final outcome = await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          subject: 'eআরণ্যক — কিশোর আরণ্যক পদক (Level $level)',
          text: 'আমি eআরণ্যক কিশোর আরণ্যক স্তর $level সম্পূর্ণ করেছি! '
              'প্রকৃতির বন্ধু, আগামীর রক্ষক। 🌿\n'
              '(I completed eAranyak Kishor Aranyak Level $level!)',
        ),
      );

      await _pruneTempFiles();
      return MedalExportOutcome.ok(
        'শেয়ার উইন্ডো খোলা হয়েছে।\n(Share sheet opened.)',
        location: outcome.status.name,
      );
    } catch (e) {
      return MedalExportOutcome.failed(
        'শেয়ার করা যায়নি।\n(Could not share the medal.)',
      );
    }
  }

  /// Saves then shares, reporting whichever step failed.
  static Future<MedalExportOutcome> saveAndShare(
    MedalRenderResult render, {
    required int level,
  }) async {
    final saved = await saveToGallery(
      render.pngBytes,
      level: level,
      withBackground: render.width != render.height,
    );
    if (!saved.success) return saved;
    return shareImage(render, level: level);
  }
}



