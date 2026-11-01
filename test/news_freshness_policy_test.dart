import 'package:flutter_test/flutter_test.dart';
import 'package:earanyak/services/news_freshness_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);

  test('includes recent published articles and respects timezone offsets', () {
    expect(
      isRecentPublicNews(
        {
          'is_published': true,
          'processing_status': 'published',
          'source_published_at': '2026-10-01T18:00:00-05:00',
        },
        now: now,
      ),
      isTrue,
    );
  });

  test('excludes stale, future, malformed, and missing publisher dates', () {
    for (final date in [
      '2026-09-01T00:00:00Z',
      '2026-10-28T00:00:00Z',
      'not-a-date',
      '',
    ]) {
      expect(
        isRecentPublicNews(
          {
            'is_published': true,
            'processing_status': 'published',
            'source_published_at': date,
          },
          now: now,
        ),
        isFalse,
        reason: date,
      );
    }
    expect(
      isRecentPublicNews({
        'is_published': false,
        'processing_status': 'published',
        'source_published_at': now.toIso8601String(),
      }, now: now),
      isFalse,
    );
  });

  test('uses editorial publication time only for curated undated stories', () {
    expect(
      isRecentPublicNews(
        {
          'is_published': true,
          'processing_status': 'published',
          'publication_source': 'editorial',
          'published_at': '2026-10-20T00:00:00Z',
        },
        now: now,
      ),
      isTrue,
    );
    expect(
      isRecentPublicNews(
        {
          'is_published': true,
          'processing_status': 'published',
          'publication_source': 'automated',
          'published_at': '2026-10-20T00:00:00Z',
        },
        now: now,
      ),
      isFalse,
    );
    expect(
      isRecentPublicNews(
        {
          'is_published': true,
          'processing_status': 'pending',
          'source_published_at': now.toIso8601String(),
        },
        now: now,
      ),
      isFalse,
    );
  });
}
