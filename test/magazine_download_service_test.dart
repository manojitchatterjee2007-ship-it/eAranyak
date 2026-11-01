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

  group('MagazineDownloadService Tests', () {
    const testMagId = 'test-mag-123';
    late Directory testDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testDir = await Directory.systemTemp.createTemp('mag_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(testDir);
    });

    tearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('isMagazineDownloaded returns false when not downloaded', () async {
      final downloaded = await MagazineDownloadService.isMagazineDownloaded(testMagId);
      expect(downloaded, isFalse);
    });

    test('isMagazineDownloaded returns true when valid files and manifest exist', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_mag_$testMagId', true);

      final dir = await MagazineDownloadService.getMagazineDirectory(testMagId);
      await dir.create(recursive: true);

      // Create dummy pages
      final page1 = File('${dir.path}/page_1.jpg');
      await page1.writeAsBytes(List.filled(1024, 42)); // > 512 bytes

      final page2 = File('${dir.path}/page_2.jpg');
      await page2.writeAsBytes(List.filled(1024, 42)); // > 512 bytes

      final manifest = File('${dir.path}/manifest.json');
      await manifest.writeAsString(jsonEncode({
        'id': testMagId,
        'title': 'Test Issue',
        'total_pages': 2,
        'downloaded_at': DateTime.now().toIso8601String(),
      }));

      final downloaded = await MagazineDownloadService.isMagazineDownloaded(testMagId);
      expect(downloaded, isTrue);

      final files = await MagazineDownloadService.getLocalPageFiles(testMagId);
      expect(files, isNotNull);
      expect(files!.length, 2);
      expect(files[0].path.endsWith('page_1.jpg'), isTrue);
      expect(files[1].path.endsWith('page_2.jpg'), isTrue);
    });

    test('isMagazineDownloaded returns false if a page is corrupted or missing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_mag_$testMagId', true);

      final dir = await MagazineDownloadService.getMagazineDirectory(testMagId);
      await dir.create(recursive: true);

      // Page 1 is too small (< 512 bytes)
      final page1 = File('${dir.path}/page_1.jpg');
      await page1.writeAsBytes(List.filled(100, 42));

      final manifest = File('${dir.path}/manifest.json');
      await manifest.writeAsString(jsonEncode({
        'id': testMagId,
        'title': 'Corrupted Issue',
        'total_pages': 1,
      }));

      final downloaded = await MagazineDownloadService.isMagazineDownloaded(testMagId);
      expect(downloaded, isFalse);
    });

    test('removeMagazine cleans up files and preferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('downloaded_mag_$testMagId', true);
      await prefs.setStringList('downloaded_magazine_ids', [testMagId]);
      await prefs.setString('mag_meta_$testMagId', jsonEncode({'id': testMagId}));

      final dir = await MagazineDownloadService.getMagazineDirectory(testMagId);
      await dir.create(recursive: true);
      final dummy = File('${dir.path}/manifest.json');
      await dummy.writeAsString('{}');

      expect(await dir.exists(), isTrue);

      await MagazineDownloadService.removeMagazine(testMagId);

      expect(await dir.exists(), isFalse);
      expect(prefs.getBool('downloaded_mag_$testMagId'), isNull);
      expect(prefs.getStringList('downloaded_magazine_ids'), isEmpty);
      expect(prefs.getString('mag_meta_$testMagId'), isNull);
    });
  });
}
