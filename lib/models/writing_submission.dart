class CommunityArticleImage {
  final String id;
  final String articleId;
  final String imageUrl;
  final String? storagePath;
  final String? caption;
  final int displayOrder;

  CommunityArticleImage({
    required this.id,
    required this.articleId,
    required this.imageUrl,
    this.storagePath,
    this.caption,
    this.displayOrder = 0,
  });

  factory CommunityArticleImage.fromJson(Map<String, dynamic> json) {
    return CommunityArticleImage(
      id: (json['id'] ?? '').toString(),
      articleId: (json['article_id'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
      storagePath: json['storage_path']?.toString(),
      caption: json['caption']?.toString(),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'article_id': articleId,
      'image_url': imageUrl,
      if (storagePath != null) 'storage_path': storagePath,
      if (caption != null) 'caption': caption,
      'display_order': displayOrder,
    };
  }
}

class WritingSubmission {
  final String id;
  final String userId;
  final String authorName;
  final String title;
  final String articleContent;
  final int wordCount;
  final String status; // 'pending', 'pending_review', 'approved', 'published', 'unpublished', 'rejected'
  final List<String> photoUrls;
  final List<CommunityArticleImage> communityImages;
  final DateTime submittedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;
  final int editorialPriority;
  final bool isPublished;
  final String? excerpt;
  final String category;

  WritingSubmission({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.title,
    required this.articleContent,
    required this.wordCount,
    this.status = 'pending',
    this.photoUrls = const [],
    this.communityImages = const [],
    required this.submittedAt,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    this.editorialPriority = 0,
    this.isPublished = false,
    this.excerpt,
    this.category = 'nature',
  });

  factory WritingSubmission.fromJson(Map<String, dynamic> json) {
    final statusVal = (json['status'] ?? 'pending').toString();
    final isPub = json['is_published'] == true || statusVal == 'published';

    final parsedPhotoUrls = (json['photo_urls'] as List?)
            ?.map((e) => e.toString())
            .where((url) => url.isNotEmpty)
            .toList() ??
        const <String>[];

    final parsedImages = (json['community_article_images'] as List?)
            ?.map((e) => CommunityArticleImage.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <CommunityArticleImage>[];

    return WritingSubmission(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      articleContent: (json['article_content'] ?? '').toString(),
      wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
      status: statusVal,
      photoUrls: parsedPhotoUrls,
      communityImages: parsedImages,
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'].toString()) ?? DateTime.now()
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'].toString())
          : null,
      reviewedBy: json['reviewed_by']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      editorialPriority: (json['editorial_priority'] as num?)?.toInt() ?? 0,
      isPublished: isPub,
      excerpt: json['excerpt']?.toString(),
      category: (json['category'] ?? 'nature').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'author_name': authorName,
      'title': title,
      'article_content': articleContent,
      'word_count': wordCount,
      'status': status,
      'photo_urls': photoUrls,
      'submitted_at': submittedAt.toIso8601String(),
      'editorial_priority': editorialPriority,
      'is_published': isPublished,
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
      if (reviewedAt != null) 'reviewed_at': reviewedAt!.toIso8601String(),
      if (reviewedBy != null) 'reviewed_by': reviewedBy,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (excerpt != null) 'excerpt': excerpt,
      'category': category,
    };
  }

  /// Helper getter for primary cover photo or empty string
  String get coverPhotoUrl {
    if (communityImages.isNotEmpty) {
      return communityImages.first.imageUrl;
    }
    if (photoUrls.isNotEmpty) {
      return photoUrls.first;
    }
    return '';
  }

  /// Excerpt fallback if explicit excerpt is null
  String get displayExcerpt {
    if (excerpt != null && excerpt!.trim().isNotEmpty) {
      return excerpt!.trim();
    }
    if (articleContent.length > 150) {
      return '${articleContent.substring(0, 150)}...';
    }
    return articleContent;
  }
}
