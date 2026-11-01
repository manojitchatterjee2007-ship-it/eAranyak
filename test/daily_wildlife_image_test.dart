import 'package:flutter_test/flutter_test.dart';
import 'package:earanyak/models/daily_wildlife_feature.dart';

void main() {
  group('DailyWildlifeFeature Image Contract Tests', () {
    test('Correctly computes unique image cache key based on record id and original image', () {
      final feature = DailyWildlifeFeature(
        id: 'feat-101',
        featureDate: DateTime.parse('2026-10-18'),
        status: 'published',
        title: 'Gangetic River Dolphin',
        commonName: 'Gangetic River Dolphin',
        scientificName: 'Platanista gangetica',
        originalImageUrl: 'https://example.com/storage/v1/daily_sources/dolphin.jpg',
        watercolourImageUrl: 'https://example.com/storage/v1/daily_sources/dolphin_art.jpg',
      );

      final key1 = feature.imageCacheKey;
      expect(key1, contains('daily_wildlife_feat-101'));

      final updatedFeature = DailyWildlifeFeature(
        id: 'feat-101',
        featureDate: DateTime.parse('2026-10-18'),
        status: 'published',
        title: 'Gangetic River Dolphin',
        commonName: 'Gangetic River Dolphin',
        scientificName: 'Platanista gangetica',
        originalImageUrl: 'https://example.com/storage/v1/daily_sources/dolphin_new.jpg',
        watercolourImageUrl: 'https://example.com/storage/v1/daily_sources/dolphin_art.jpg',
      );

      final key2 = updatedFeature.imageCacheKey;
      expect(key1, isNot(equals(key2)));
    });

    test('Identifies when provenance or title contains cross-species mismatch', () {
      final feature = DailyWildlifeFeature(
        id: 'feat-102',
        featureDate: DateTime.parse('2026-10-18'),
        status: 'published',
        title: 'Gangetic River Dolphin',
        commonName: 'Gangetic River Dolphin',
        scientificName: 'Platanista gangetica',
        originalImageUrl: 'https://commons.wikimedia.org/wiki/File:Bengal_tiger_in_Gangetic_delta.jpg',
        imageProvenance: '{"provider":"Wikimedia Commons","source_url":"https://commons.wikimedia.org/wiki/File:Bengal_tiger.jpg"}',
      );

      expect(feature.hasCrossSpeciesMismatch, isTrue);
    });

    test('Valid species image passes cross-species mismatch check', () {
      final feature = DailyWildlifeFeature(
        id: 'feat-103',
        featureDate: DateTime.parse('2026-10-18'),
        status: 'published',
        title: 'Gangetic River Dolphin',
        commonName: 'Gangetic River Dolphin',
        scientificName: 'Platanista gangetica',
        originalImageUrl: 'https://commons.wikimedia.org/wiki/File:Platanista_gangetica.jpg',
        imageProvenance: '{"provider":"Wikimedia Commons","source_url":"https://commons.wikimedia.org/wiki/File:Platanista_gangetica.jpg"}',
      );

      expect(feature.hasCrossSpeciesMismatch, isFalse);
    });
  });
}
