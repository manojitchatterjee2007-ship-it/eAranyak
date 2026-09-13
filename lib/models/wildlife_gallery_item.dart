class WildlifeGalleryItem {
  final String id;
  final String title;
  final String? caption;
  final String? description;
  final String? location;
  final String? photographerCredit;
  final String? category;
  final int editorialPriority;
  final bool isFeatured;
  final bool isPublished;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String storagePath;
  final String? createdBy;

  WildlifeGalleryItem({
    required this.id,
    required this.title,
    this.caption,
    this.description,
    this.location,
    this.photographerCredit,
    this.category,
    this.editorialPriority = 10,
    this.isFeatured = false,
    this.isPublished = true,
    this.publishedAt,
    required this.createdAt,
    this.updatedAt,
    required this.storagePath,
    this.createdBy,
  });

  factory WildlifeGalleryItem.fromJson(Map<String, dynamic> json) {
    return WildlifeGalleryItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      caption: json['caption']?.toString(),
      description: json['description']?.toString(),
      location: json['location']?.toString(),
      photographerCredit: json['photographer_credit']?.toString(),
      category: json['category']?.toString(),
      editorialPriority: (json['editorial_priority'] as num?)?.toInt() ?? 10,
      isFeatured: json['is_featured'] == true,
      isPublished: json['is_published'] != false,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      storagePath: (json['storage_path'] ?? '').toString(),
      createdBy: json['created_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (caption != null) 'caption': caption,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (photographerCredit != null) 'photographer_credit': photographerCredit,
      if (category != null) 'category': category,
      'editorial_priority': editorialPriority,
      'is_featured': isFeatured,
      'is_published': isPublished,
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
      'storage_path': storagePath,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  String get displayTitle => title.isNotEmpty ? title : (caption ?? 'Untitled Image');
  String get displayDescription => (description != null && description!.isNotEmpty) ? description! : (caption ?? '');
}
