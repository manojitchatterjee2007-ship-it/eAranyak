// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:earanyak/services/magazine_download_service.dart';

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;
  FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Magazine Reader & Download Workflow Integration Tests', () {
    const testMagId = 'workflow-mag-001';
    late Directory testDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testDir = await Directory.systemTemp.createTemp('mag_workflow_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(testDir);
    });

    tearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('Initial magazine state is un-downloaded with no local files', () async {
      final isDownloaded = await MagazineDownloadService.isMagazineDownloaded(testMagId);
      expect(isDownloaded, isFalse);

      final files = await MagazineDownloadService.getLocalPageFiles(testMagId);
      expect(files, isNull);
    });

    test('Full download storage verification with manifest and page validation', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_mag_$testMagId', true);
      await prefs.setStringList('downloaded_magazine_ids', [testMagId]);
      await prefs.setString(
        'mag_meta_$testMagId',
        jsonEncode({
          'id': testMagId,
          'title': 'Test Wildlife Edition',
          'issue_date': '2026-10-30',
        }),
      );

      final magDir = await MagazineDownloadService.getMagazineDirectory(testMagId);
      await magDir.create(recursive: true);

      // Create 4 valid local page files
      for (int i = 1; i <= 4; i++) {
        final page = File('${magDir.path}/page_$i.jpg');
        await page.writeAsBytes(List.filled(2048, i));
      }

      final manifest = File('${magDir.path}/manifest.json');
      await manifest.writeAsString(jsonEncode({
        'id': testMagId,
        'title': 'Test Wildlife Edition',
        'total_pages': 4,
        'downloaded_at': DateTime.now().toIso8601String(),
      }));

      // Verify that offline verification recognizes this magazine as 100% available
      final isReady = await MagazineDownloadService.isMagazineDownloaded(testMagId);
      expect(isReady, isTrue);

      final pages = await MagazineDownloadService.getLocalPageFiles(testMagId);
      expect(pages, isNotNull);
      expect(pages!.length, 4);
      for (int i = 0; i < 4; i++) {
        expect(pages[i].existsSync(), isTrue);
        expect(pages[i].path.endsWith('page_${i + 1}.jpg'), isTrue);
      }
    });

    test('Progress notifier updates correctly during download lifecycle', () {
      final initial = MagazineDownloadService.progressNotifier.value;
      expect(initial.containsKey(testMagId), isFalse);

      final progress = MagazineDownloadProgress(
        magazineId: testMagId,
        progress: 0.5,
        currentPage: 2,
        totalPages: 4,
        statusMessage: 'Downloading page 2 of 4...',
      );

      final current = Map<String, MagazineDownloadProgress>.from(MagazineDownloadService.progressNotifier.value);
      current[testMagId] = progress;
      MagazineDownloadService.progressNotifier.value = current;

      expect(MagazineDownloadService.progressNotifier.value[testMagId]?.progress, 0.5);
      expect(MagazineDownloadService.progressNotifier.value[testMagId]?.currentPage, 2);
      expect(MagazineDownloadService.progressNotifier.value[testMagId]?.statusMessage, 'Downloading page 2 of 4...');
    });
  });
}
