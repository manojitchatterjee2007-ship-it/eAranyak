class Podcast {
  final String id;
  final String title;
  final int? episodeNumber;
  final String? description;
  final String? snippet;
  final String? thumbnailUrl;
  final String? audioUrl;
  final String? storagePath;
  final int? durationSeconds;
  final String? category;
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

  Podcast({
    required this.id,
    required this.title,
    this.episodeNumber,
    this.description,
    this.snippet,
    this.thumbnailUrl,
    this.audioUrl,
    this.storagePath,
    this.durationSeconds,
    this.category,
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

  factory Podcast.fromJson(Map<String, dynamic> json) {
    return Podcast(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      episodeNumber: (json['episode_number'] as num?)?.toInt(),
      description: json['description']?.toString(),
      snippet: json['snippet']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      audioUrl: json['audio_url']?.toString(),
      storagePath: json['storage_path']?.toString(),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      category: json['category']?.toString(),
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
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (description != null) 'description': description,
      if (snippet != null) 'snippet': snippet,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (storagePath != null) 'storage_path': storagePath,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (category != null) 'category': category,
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

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds! <= 0) return 'Duration unknown';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
