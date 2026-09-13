class AppNotificationImage {
  final String id;
  final String notificationId;
  final String imageUrl;
  final String? storagePath;
  final String? caption;
  final int displayOrder;
  final bool isPrimary;

  AppNotificationImage({
    required this.id,
    required this.notificationId,
    required this.imageUrl,
    this.storagePath,
    this.caption,
    this.displayOrder = 0,
    this.isPrimary = false,
  });

  factory AppNotificationImage.fromJson(Map<String, dynamic> json) {
    return AppNotificationImage(
      id: (json['id'] ?? '').toString(),
      notificationId: (json['notification_id'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
      storagePath: json['storage_path']?.toString(),
      caption: json['caption']?.toString(),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isPrimary: json['is_primary'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'notification_id': notificationId,
      'image_url': imageUrl,
      if (storagePath != null) 'storage_path': storagePath,
      if (caption != null) 'caption': caption,
      'display_order': displayOrder,
      'is_primary': isPrimary,
    };
  }
}

class AppNotificationItem {
  final String id;
  final String title;
  final String? snippet;
  final String? content;
  final String notificationType; // 'text', 'image', 'pdf'
  final String? thumbnailUrl;
  final String? pdfUrl;
  final int editorialPriority;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final List<AppNotificationImage> images;

  // Phase 7B-1 fields:
  final String category;
  final DateTime? eventDate;
  final String? venue;
  final String? registrationUrl;
  final String? contactInfo;
  final bool isFeatured;

  AppNotificationItem({
    required this.id,
    required this.title,
    this.snippet,
    this.content,
    required this.notificationType,
    this.thumbnailUrl,
    this.pdfUrl,
    this.editorialPriority = 0,
    this.isPublished = false,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.images = const [],
    this.category = 'General',
    this.eventDate,
    this.venue,
    this.registrationUrl,
    this.contactInfo,
    this.isFeatured = false,
  });

  factory AppNotificationItem.fromJson(Map<String, dynamic> json) {
    final parsedImages = (json['app_notification_images'] as List?)
            ?.map((e) => AppNotificationImage.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <AppNotificationImage>[];

    return AppNotificationItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      snippet: json['snippet']?.toString(),
      content: json['content']?.toString(),
      notificationType: (json['notification_type'] ?? 'text').toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      pdfUrl: json['pdf_url']?.toString(),
      editorialPriority: (json['editorial_priority'] as num?)?.toInt() ?? 0,
      isPublished: json['is_published'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      images: parsedImages,
      category: (json['category'] ?? 'General').toString(),
      eventDate: json['event_date'] != null
          ? DateTime.tryParse(json['event_date'].toString())
          : null,
      venue: json['venue']?.toString(),
      registrationUrl: json['registration_url']?.toString(),
      contactInfo: json['contact_info']?.toString(),
      isFeatured: json['is_featured'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (snippet != null) 'snippet': snippet,
      if (content != null) 'content': content,
      'notification_type': notificationType,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (pdfUrl != null) 'pdf_url': pdfUrl,
      'editorial_priority': editorialPriority,
      'is_published': isPublished,
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
      'category': category,
      if (eventDate != null) 'event_date': eventDate!.toIso8601String(),
      if (venue != null) 'venue': venue,
      if (registrationUrl != null) 'registration_url': registrationUrl,
      if (contactInfo != null) 'contact_info': contactInfo,
      'is_featured': isFeatured,
    };
  }

  /// Primary image or thumbnail URL helper
  String get displayThumbnail {
    if (thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty) {
      return thumbnailUrl!.trim();
    }
    if (images.isNotEmpty) {
      final primary = images.firstWhere((img) => img.isPrimary, orElse: () => images.first);
      return primary.imageUrl;
    }
    return '';
  }

  /// Display snippet fallback
  String get displaySnippet {
    if (snippet != null && snippet!.trim().isNotEmpty) {
      return snippet!.trim();
    }
    if (content != null && content!.trim().isNotEmpty) {
      if (content!.length > 140) {
        return '${content!.substring(0, 140)}...';
      }
      return content!.trim();
    }
    if (notificationType == 'pdf') {
      return 'বিজ্ঞপ্তি PDF ডকুমেন্ট দেখতে ট্যাপ করুন।';
    }
    if (notificationType == 'image') {
      return 'বিজ্ঞপ্তির ছবিসমূহ দেখতে ট্যাপ করুন।';
    }
    return title;
  }

  bool get isEvent => category.toLowerCase() == 'event';
}

typedef AppNotification = AppNotificationItem;
