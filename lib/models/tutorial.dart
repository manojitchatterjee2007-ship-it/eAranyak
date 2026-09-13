class Tutorial {
  final String id;
  final String title;
  final String? description;
  final String? snippet;
  final String? thumbnailUrl;
  final String? resourceUrl;
  final String? storagePath;
  final String resourceType; // 'video', 'pdf', 'article', 'external'
  final String? category;
  final String difficulty; // 'beginner', 'intermediate', 'advanced'
  final int? durationMinutes;
  final int editorialPriority;
  final bool isFeatured;
  final bool isPublished;
  final DateTime? scheduledPublishAt;
  final DateTime? expiresAt;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  Tutorial({
    required this.id,
    required this.title,
    this.description,
    this.snippet,
    this.thumbnailUrl,
    this.resourceUrl,
    this.storagePath,
    this.resourceType = 'video',
    this.category,
    this.difficulty = 'beginner',
    this.durationMinutes,
    this.editorialPriority = 10,
    this.isFeatured = false,
    this.isPublished = false,
    this.scheduledPublishAt,
    this.expiresAt,
    this.publishedAt,
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory Tutorial.fromJson(Map<String, dynamic> json) {
    return Tutorial(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description']?.toString(),
      snippet: json['snippet']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      resourceUrl: json['resource_url']?.toString(),
      storagePath: json['storage_path']?.toString(),
      resourceType: (json['resource_type'] ?? 'video').toString(),
      category: json['category']?.toString(),
      difficulty: (json['difficulty'] ?? 'beginner').toString(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      editorialPriority: (json['editorial_priority'] as num?)?.toInt() ?? 10,
      isFeatured: json['is_featured'] == true,
      isPublished: json['is_published'] == true,
      scheduledPublishAt: json['scheduled_publish_at'] != null
          ? DateTime.tryParse(json['scheduled_publish_at'].toString())
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      createdBy: json['created_by']?.toString(),
      updatedBy: json['updated_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (description != null) 'description': description,
      if (snippet != null) 'snippet': snippet,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (resourceUrl != null) 'resource_url': resourceUrl,
      if (storagePath != null) 'storage_path': storagePath,
      'resource_type': resourceType,
      if (category != null) 'category': category,
      'difficulty': difficulty,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      'editorial_priority': editorialPriority,
      'is_featured': isFeatured,
      'is_published': isPublished,
      if (scheduledPublishAt != null) 'scheduled_publish_at': scheduledPublishAt!.toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
      if (createdBy != null) 'created_by': createdBy,
      if (updatedBy != null) 'updated_by': updatedBy,
    };
  }

  bool get isExternal => resourceType == 'external';
}
