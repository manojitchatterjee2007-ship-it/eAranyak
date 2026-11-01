/// Freshness window used by the public wildlife news feed.
const newsFreshnessDays = int.fromEnvironment(
  'NEWS_FRESHNESS_DAYS',
  defaultValue: 30,
);

DateTime? newsPublisherDate(Map<String, dynamic> item) {
  final sourceDate = item['source_published_at']?.toString();
  if (sourceDate != null && sourceDate.trim().isNotEmpty) {
    return DateTime.tryParse(sourceDate)?.toUtc();
  }

  // Human-curated pieces can lack a publisher timestamp; their editorial
  // publication time is the deliberate fallback. Automated undated stories
  // stay out of the default feed.
  if (item['publication_source'] == 'editorial') {
    final editorialDate = item['published_at']?.toString();
    if (editorialDate != null && editorialDate.trim().isNotEmpty) {
      return DateTime.tryParse(editorialDate)?.toUtc();
    }
  }
  return null;
}

bool isRecentPublicNews(
  Map<String, dynamic> item, {
  DateTime? now,
  int freshnessDays = newsFreshnessDays,
}) {
  if (item['is_published'] != true ||
      item['processing_status'] != 'published') {
    return false;
  }
  final publishedAt = newsPublisherDate(item);
  if (publishedAt == null) return false;
  final current = (now ?? DateTime.now()).toUtc();
  return !publishedAt.isAfter(current) &&
      !publishedAt.isBefore(current.subtract(Duration(days: freshnessDays)));
}
