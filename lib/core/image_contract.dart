/// Image Contract for News and Daily Wildlife image processing and filtering.
/// Cline should consume these contracts to locate original vs processed images
/// and compute unique cache keys.
library;

class ImageContract {
  /// Generates a cache key for News images ensuring processing is scoped to article & source image.
  static String getNewsCacheKey(Map<String, dynamic> newsItem) {
    final id = (newsItem['id'] ?? newsItem['article_id'] ?? 'unknown').toString();
    final sourceImageHash = (newsItem['image_url'] ?? newsItem['original_image_url'] ?? '').toString().hashCode;
    return 'news_${id}_$sourceImageHash';
  }

  /// Retrieves the canonical original image URL for a News article.
  static String? getNewsOriginalImageUrl(Map<String, dynamic> newsItem) {
    final url = (newsItem['original_image_url'] ?? newsItem['image_url'])?.toString().trim();
    return (url != null && url.isNotEmpty) ? url : null;
  }

  /// Retrieves the processed watercolor thumbnail URL for compact News cards (if server-side exists).
  static String? getNewsProcessedThumbnailUrl(Map<String, dynamic> newsItem) {
    final url = (newsItem['processed_thumbnail_url'] ?? newsItem['thumbnail_url'])?.toString().trim();
    return (url != null && url.isNotEmpty) ? url : null;
  }

  /// Generates a cache key for Daily Wildlife feature images.
  static String getDailyWildlifeCacheKey(String featureId, String? originalImageUrl) {
    final sourceHash = (originalImageUrl ?? '').hashCode;
    return 'daily_wildlife_${featureId}_$sourceHash';
  }
}
