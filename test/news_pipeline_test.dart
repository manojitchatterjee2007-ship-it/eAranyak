import 'package:flutter_test/flutter_test.dart';
import 'package:earanyak/services/news_freshness_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);

  group('News Freshness & Feed Policy', () {
    test('isRecentPublicNews includes published articles within 30 days', () {
      final validArticle = {
        'id': 'news-101',
        'is_published': true,
        'processing_status': 'published',
        'source_published_at': '2026-10-25T10:00:00Z',
        'bengali_headline': 'সুন্দরবনে নতুন বাঘের শুমারি',
        'bengali_body': 'সুন্দরবনে বাঘের সংখ্যা বৃদ্ধি পেয়েছে।',
        'image_url': 'https://example.com/tiger.jpg',
      };
      expect(isRecentPublicNews(validArticle, now: now), isTrue);
    });

    test('isRecentPublicNews excludes unpublished or non-published status', () {
      final unpubArticle = {
        'id': 'news-102',
        'is_published': false,
        'processing_status': 'published',
        'source_published_at': '2026-10-25T10:00:00Z',
      };
      final pendingArticle = {
        'id': 'news-103',
        'is_published': true,
        'processing_status': 'pending',
        'source_published_at': '2026-10-25T10:00:00Z',
      };
      expect(isRecentPublicNews(unpubArticle, now: now), isFalse);
      expect(isRecentPublicNews(pendingArticle, now: now), isFalse);
    });

    test('isRecentPublicNews excludes articles older than 30 days', () {
      final staleArticle = {
        'id': 'news-104',
        'is_published': true,
        'processing_status': 'published',
        'source_published_at': '2026-09-01T10:00:00Z',
      };
      expect(isRecentPublicNews(staleArticle, now: now), isFalse);
    });

    test('isRecentPublicNews excludes future-dated articles', () {
      final futureArticle = {
        'id': 'news-105',
        'is_published': true,
        'processing_status': 'published',
        'source_published_at': '2026-11-01T10:00:00Z',
      };
      expect(isRecentPublicNews(futureArticle, now: now), isFalse);
    });

    test('newsPublisherDate uses source_published_at as priority', () {
      final article = {
        'source_published_at': '2026-10-20T00:00:00Z',
        'published_at': '2026-10-21T00:00:00Z',
        'publication_source': 'automated',
      };
      final parsed = newsPublisherDate(article);
      expect(parsed, equals(DateTime.utc(2026, 10, 20)));
    });

    test('newsPublisherDate falls back to published_at only for editorial source', () {
      final editorial = {
        'source_published_at': null,
        'published_at': '2026-10-21T00:00:00Z',
        'publication_source': 'editorial',
      };
      final automated = {
        'source_published_at': null,
        'published_at': '2026-10-21T00:00:00Z',
        'publication_source': 'automated',
      };
      expect(newsPublisherDate(editorial), equals(DateTime.utc(2026, 10, 21)));
      expect(newsPublisherDate(automated), isNull);
    });
  });
}
