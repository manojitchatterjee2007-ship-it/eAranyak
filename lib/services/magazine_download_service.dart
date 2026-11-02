import '../core/prefs_helper.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config.dart';
import 'protected_asset_service.dart';

class MagazineDownloadProgress {
  final String magazineId;
  final double progress; // 0.0 to 1.0
  final int currentPage;
  final int totalPages;
  final String statusMessage;
  final bool isCompleted;
  final String? error;

  const MagazineDownloadProgress({
    required this.magazineId,
    required this.progress,
    required this.currentPage,
    required this.totalPages,
    required this.statusMessage,
    this.isCompleted = false,
    this.error,
  });

  MagazineDownloadProgress copyWith({
    double? progress,
    int? currentPage,
    int? totalPages,
    String? statusMessage,
    bool? isCompleted,
    String? error,
  }) {
    return MagazineDownloadProgress(
      magazineId: magazineId,
      progress: progress ?? this.progress,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      statusMessage: statusMessage ?? this.statusMessage,
      isCompleted: isCompleted ?? this.isCompleted,
      error: error ?? this.error,
    );
  }
}

class MagazineDownloadService {
  static final ValueNotifier<Map<String, MagazineDownloadProgress>> progressNotifier =
      ValueNotifier<Map<String, MagazineDownloadProgress>>({});

  static final Set<String> _activeDownloads = {};

  static bool isDownloading(String magazineId) => _activeDownloads.contains(magazineId);

  static Future<Directory> _getBaseDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final base = Directory('${appDocDir.path}/magazines');
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return base;
  }

  static Future<Directory> getMagazineDirectory(String magazineId) async {
    final base = await _getBaseDirectory();
    return Directory('${base.path}/$magazineId');
  }

  // Helper to prevent Pigeon InstanceManager crashes during concurrent SharedPreferences access
  static Future<SharedPreferences> _getPrefsSafely() async {
    for (int i = 0; i < 3; i++) {
      try {
        return await PrefsHelper.getPrefs();
      } catch (e) {
        if (i == 2) rethrow;
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    throw Exception('Failed to get SharedPreferences');
  }

  /// Checks whether a full magazine issue is stored locally and fully verified.
  static Future<bool> isMagazineDownloaded(String magazineId) async {
    try {
      final prefs = await _getPrefsSafely();
      final isFlagged = prefs.getBool('downloaded_mag_$magazineId') ?? false;
      if (!isFlagged) return false;

      final magDir = await getMagazineDirectory(magazineId);
      if (!await magDir.exists()) return false;

      final manifestFile = File('${magDir.path}/manifest.json');
      if (!await manifestFile.exists()) return false;

      final manifestRaw = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
      final totalPages = manifest['total_pages'] as int? ?? 0;
      if (totalPages <= 0) return false;

      for (int i = 1; i <= totalPages; i++) {
        final pageFile = File('${magDir.path}/page_$i.jpg');
        if (!await pageFile.exists() || await pageFile.length() < 512) {
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[MagazineDownloadService] Check error for $magazineId: $e');
      return false;
    }
  }

  /// Returns sorted list of local page image files if downloaded; otherwise null.
  static Future<List<File>?> getLocalPageFiles(String magazineId) async {
    try {
      final isReady = await isMagazineDownloaded(magazineId);
      if (!isReady) return null;

      final magDir = await getMagazineDirectory(magazineId);
      final manifestFile = File('${magDir.path}/manifest.json');
      final manifestRaw = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
      final totalPages = manifest['total_pages'] as int;

      final List<File> files = [];
      for (int i = 1; i <= totalPages; i++) {
        final f = File('${magDir.path}/page_$i.jpg');
        if (await f.exists()) {
          files.add(f);
        } else {
          return null; // missing page file
        }
      }
      return files.isNotEmpty ? files : null;
    } catch (e) {
      debugPrint('[MagazineDownloadService] getLocalPageFiles error: $e');
      return null;
    }
  }

  /// Downloads single page bytes with retry logic and fallback mechanisms.
  static Future<Uint8List> _downloadPageBytesWithRetry({
    required String storagePath,
    required int pageNum,
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // Strategy A: Direct authenticated Supabase storage download
        try {
          final bytes = await supabase.storage
              .from('magazine_pages')
              .download(storagePath)
              .timeout(const Duration(seconds: 30));
          if (bytes.length >= 512) {
            return bytes;
          }
        } catch (e) {
          lastError = e;
        }

        // Strategy B: Fallback to signed URL + HTTP GET
        final signedUrl = await ProtectedAssetService.getSignedUrl(
          bucket: 'magazine_pages',
          storagePath: storagePath,
          expiresInSeconds: 600,
        );

        if (signedUrl != null && signedUrl.isNotEmpty) {
          final response = await http.get(Uri.parse(signedUrl)).timeout(
            const Duration(seconds: 30),
          );
          if (response.statusCode == 200 && response.bodyBytes.length >= 512) {
            return response.bodyBytes;
          }
          lastError = HttpException('HTTP ${response.statusCode} for page $pageNum');
        } else {
          lastError ??= StateError('Unable to generate access token for page $pageNum');
        }
      } catch (e) {
        lastError = e;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    throw lastError ?? HttpException('Failed to download page $pageNum after $maxAttempts attempts');
  }

  /// Downloads full issue pages with parallel pooling, retry, and atomic disk persistence.
  static Future<bool> downloadMagazine({
    required Map<String, dynamic> magazine,
    void Function(MagazineDownloadProgress progress)? onProgress,
  }) async {
    final magazineId = magazine['id']?.toString();
    if (magazineId == null || magazineId.isEmpty) {
      throw ArgumentError('Invalid magazine metadata: missing id');
    }

    if (_activeDownloads.contains(magazineId)) {
      debugPrint('[MagazineDownloadService] Download already active for $magazineId, ignoring duplicate trigger.');
      return true;
    }
    _activeDownloads.add(magazineId);

    final title = formatMagazineTitle(magazine['title']?.toString());

    void updateProgress(MagazineDownloadProgress p) {
      final current = Map<String, MagazineDownloadProgress>.from(progressNotifier.value);
      current[magazineId] = p;
      progressNotifier.value = current;
      onProgress?.call(p);
    }

    updateProgress(MagazineDownloadProgress(
      magazineId: magazineId,
      progress: 0.0,
      currentPage: 0,
      totalPages: 0,
      statusMessage: 'ডাউনলোড শুরু হচ্ছে... (Connecting...)',
    ));

    Directory? tempDir;

    try {
      // 1. Fetch magazine pages catalog from Supabase
      final pagesRes = await supabase
          .from('magazine_pages')
          .select()
          .eq('magazine_id', magazineId)
          .order('page_number', ascending: true);

      final pages = List<Map<String, dynamic>>.from(pagesRes);
      if (pages.isEmpty) {
        throw StateError('এই ম্যাগাজিনের কোনো পৃষ্ঠা পাওয়া যায়নি। (No pages found on server)');
      }

      final totalPages = pages.length;
      final baseDir = await _getBaseDirectory();
      tempDir = Directory('${baseDir.path}/${magazineId}_tmp');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      int completedPages = 0;

      // Check existing files in temp directory to enable resuming
      for (int i = 0; i < totalPages; i++) {
        final existing = File('${tempDir.path}/page_${i + 1}.jpg');
        if (existing.existsSync() && existing.lengthSync() >= 512) {
          completedPages++;
        }
      }

      if (completedPages > 0) {
        final p = completedPages / totalPages;
        updateProgress(MagazineDownloadProgress(
          magazineId: magazineId,
          progress: p,
          currentPage: completedPages,
          totalPages: totalPages,
          statusMessage: 'ডাউনলোড পুনরুদ্ধার হচ্ছে... ($completedPages/$totalPages)',
        ));
      }

      // 2. Download missing pages with concurrency pool
      const int concurrency = 3;
      for (int i = 0; i < totalPages; i += concurrency) {
        final end = (i + concurrency < totalPages) ? i + concurrency : totalPages;
        final chunkIndices = List.generate(end - i, (k) => i + k);

        await Future.wait(chunkIndices.map((idx) async {
          final pageItem = pages[idx];
          final pageTargetNum = idx + 1;
          final storagePath = pageItem['storage_path']?.toString();

          if (storagePath == null || storagePath.isEmpty) {
            throw StateError('Page $pageTargetNum has missing storage path.');
          }

          final targetFile = File('${tempDir!.path}/page_$pageTargetNum.jpg');
          if (!await targetFile.exists() || await targetFile.length() < 512) {
            final bytes = await _downloadPageBytesWithRetry(
              storagePath: storagePath,
              pageNum: pageTargetNum,
            );
            await targetFile.writeAsBytes(bytes, flush: true);
          }

          completedPages++;
          final currentProgress = (completedPages / totalPages).clamp(0.0, 1.0);
          updateProgress(MagazineDownloadProgress(
            magazineId: magazineId,
            progress: currentProgress,
            currentPage: completedPages,
            totalPages: totalPages,
            statusMessage: 'পৃষ্ঠা $completedPages / $totalPages ডাউনলোড হচ্ছে... (${(currentProgress * 100).round()}%)',
          ));
        }));
      }

      // 3. Write manifest.json
      final manifest = {
        'id': magazineId,
        'title': title,
        'issue_date': magazine['issue_date']?.toString() ?? '',
        'total_pages': totalPages,
        'downloaded_at': DateTime.now().toIso8601String(),
        'meta': magazine,
      };
      final manifestFile = File('${tempDir.path}/manifest.json');
      await manifestFile.writeAsString(jsonEncode(manifest), flush: true);

      // 4. Robust transfer to final directory
      final finalDir = await getMagazineDirectory(magazineId);
      if (!await finalDir.exists()) {
        await finalDir.create(recursive: true);
      }

      final tempEntities = tempDir.listSync();
      for (final entity in tempEntities) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
          final dest = File('${finalDir.path}/$fileName');
          if (await dest.exists()) {
            try {
              await dest.delete();
            } catch (_) {}
          }
          try {
            await entity.rename(dest.path);
          } catch (_) {
            await entity.copy(dest.path);
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }

      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      tempDir = null; // Successfully transferred

      // 5. Update SharedPreferences metadata
      final prefs = await _getPrefsSafely();
      await prefs.setBool('downloaded_mag_$magazineId', true);

      List<String> downloadedIds = List<String>.from(prefs.getStringList('downloaded_magazine_ids') ?? []);
      if (!downloadedIds.contains(magazineId)) {
        downloadedIds.add(magazineId);
        await prefs.setStringList('downloaded_magazine_ids', downloadedIds);
      }
      await prefs.setString('mag_meta_$magazineId', jsonEncode(magazine));
      await prefs.setInt('mag_pages_count_$magazineId', totalPages);

      updateProgress(MagazineDownloadProgress(
        magazineId: magazineId,
        progress: 1.0,
        currentPage: totalPages,
        totalPages: totalPages,
        statusMessage: 'ডাউনলোড সফলভাবে সম্পন্ন হয়েছে! (Download complete)',
        isCompleted: true,
      ));

      debugPrint('[MagazineDownloadService] Magazine $magazineId downloaded successfully ($totalPages pages).');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[MagazineDownloadService] Download failed for $magazineId: $e\n$stackTrace');

      final errorMsg = e is SocketException
          ? 'ইন্টারনেট সংযোগ বিচ্ছিন্ন হয়েছে। (Network disconnected)'
          : e is TimeoutException
              ? 'সার্ভার সাড়া দেয়নি, সময় অতিক্রান্ত হয়েছে। (Request timed out)'
              : e.toString();

      updateProgress(MagazineDownloadProgress(
        magazineId: magazineId,
        progress: 0.0,
        currentPage: 0,
        totalPages: 0,
        statusMessage: 'ডাউনলোড ব্যর্থ হয়েছে। (Download failed)',
        isCompleted: false,
        error: errorMsg,
      ));

      return false;
    } finally {
      _activeDownloads.remove(magazineId);
    }
  }

  /// Removes local files and bookshelf registration for a magazine.
  static Future<void> removeMagazine(String magazineId) async {
    try {
      final magDir = await getMagazineDirectory(magazineId);
      if (await magDir.exists()) {
        await magDir.delete(recursive: true);
      }

      final baseDir = await _getBaseDirectory();
      final tempDir = Directory('${baseDir.path}/${magazineId}_tmp');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }

      final prefs = await _getPrefsSafely();
      await prefs.remove('downloaded_mag_$magazineId');
      await prefs.remove('mag_meta_$magazineId');
      await prefs.remove('mag_pages_count_$magazineId');

      final downloadedIds = List<String>.from(prefs.getStringList('downloaded_magazine_ids') ?? []);
      downloadedIds.remove(magazineId);
      await prefs.setStringList('downloaded_magazine_ids', downloadedIds);

      final current = Map<String, MagazineDownloadProgress>.from(progressNotifier.value);
      current.remove(magazineId);
      progressNotifier.value = current;

      debugPrint('[MagazineDownloadService] Removed magazine $magazineId');
    } catch (e) {
      debugPrint('[MagazineDownloadService] Error removing magazine $magazineId: $e');
    }
  }
}
