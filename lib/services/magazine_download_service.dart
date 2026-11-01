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

  /// Checks whether a full magazine issue is stored locally and fully verified.
  static Future<bool> isMagazineDownloaded(String magazineId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
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

  /// Downloads full issue pages sequentially and atomically stores them locally.
  static Future<bool> downloadMagazine({
    required Map<String, dynamic> magazine,
    void Function(MagazineDownloadProgress progress)? onProgress,
  }) async {
    final magazineId = magazine['id']?.toString();
    if (magazineId == null || magazineId.isEmpty) {
      throw ArgumentError('Invalid magazine metadata: missing id');
    }

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
      tempDir = Directory('${baseDir.path}/${magazineId}_tmp_${DateTime.now().millisecondsSinceEpoch}');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      // 2. Download each page image
      for (int i = 0; i < totalPages; i++) {
        final pageItem = pages[i];
        final pageNum = pageItem['page_number'] as int? ?? (i + 1);
        final storagePath = pageItem['storage_path']?.toString();

        if (storagePath == null || storagePath.isEmpty) {
          throw StateError('Page $pageNum has missing storage path.');
        }

        final currentProgress = i / totalPages;
        updateProgress(MagazineDownloadProgress(
          magazineId: magazineId,
          progress: currentProgress,
          currentPage: i + 1,
          totalPages: totalPages,
          statusMessage: 'পৃষ্ঠা $pageNum / $totalPages ডাউনলোড হচ্ছে... (${(currentProgress * 100).round()}%)',
        ));

        // Generate signed URL
        final signedUrl = await ProtectedAssetService.getSignedUrl(
          bucket: 'magazine_pages',
          storagePath: storagePath,
          expiresInSeconds: 300,
        );

        if (signedUrl == null) {
          throw StateError('Unable to generate access token for page $pageNum.');
        }

        final response = await http.get(Uri.parse(signedUrl)).timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException('Network timed out while downloading page $pageNum'),
        );

        if (response.statusCode != 200 || response.bodyBytes.length < 512) {
          throw HttpException('Download failed for page $pageNum (HTTP ${response.statusCode})');
        }

        final targetFile = File('${tempDir.path}/page_$pageNum.jpg');
        await targetFile.writeAsBytes(response.bodyBytes, flush: true);
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

      // 4. Atomic move to final directory
      final finalDir = await getMagazineDirectory(magazineId);
      if (await finalDir.exists()) {
        await finalDir.delete(recursive: true);
      }
      await tempDir.rename(finalDir.path);
      tempDir = null; // Successfully transferred

      // 5. Update SharedPreferences metadata
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_mag_$magazineId', true);

      List<String> downloadedIds = prefs.getStringList('downloaded_magazine_ids') ?? [];
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
    } catch (e) {
      debugPrint('[MagazineDownloadService] Download failed for $magazineId: $e');

      // Cleanup temp directory on failure
      if (tempDir != null && await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }

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
    }
  }

  /// Removes local files and bookshelf registration for a magazine.
  static Future<void> removeMagazine(String magazineId) async {
    try {
      final magDir = await getMagazineDirectory(magazineId);
      if (await magDir.exists()) {
        await magDir.delete(recursive: true);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('downloaded_mag_$magazineId');
      await prefs.remove('mag_meta_$magazineId');
      await prefs.remove('mag_pages_count_$magazineId');

      final downloadedIds = prefs.getStringList('downloaded_magazine_ids') ?? [];
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
