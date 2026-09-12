class OnlineBook {
  final String id;
  final String title;
  final String? author;
  final String publisher;
  final String? description;
  final double price;
  final double? originalPrice;
  final String currency;
  final String? thumbnailUrl;
  final String? storagePath;
  final String? orderUrl;
  final bool isAvailable;
  final int editorialPriority;
  final bool isPublished;
  final DateTime? scheduledPublishAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final String? createdBy;
  final String? updatedBy;

  OnlineBook({
    required this.id,
    required this.title,
    this.author,
    required this.publisher,
    this.description,
    required this.price,
    this.originalPrice,
    this.currency = 'INR',
    this.thumbnailUrl,
    this.storagePath,
    this.orderUrl,
    this.isAvailable = true,
    this.editorialPriority = 0,
    this.isPublished = false,
    this.scheduledPublishAt,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory OnlineBook.fromMap(Map<String, dynamic> map) {
    return OnlineBook(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      author: map['author']?.toString(),
      publisher: map['publisher']?.toString() ?? 'Ekhon Aranyak',
      description: map['description']?.toString(),
      price: (map['price'] is num) ? (map['price'] as num).toDouble() : double.tryParse(map['price']?.toString() ?? '0') ?? 0.0,
      originalPrice: (map['original_price'] is num) ? (map['original_price'] as num).toDouble() : (map['original_price'] != null ? double.tryParse(map['original_price'].toString()) : null),
      currency: map['currency']?.toString() ?? 'INR',
      thumbnailUrl: map['thumbnail_url']?.toString(),
      storagePath: map['storage_path']?.toString(),
      orderUrl: map['order_url']?.toString(),
      isAvailable: map['is_available'] == true,
      editorialPriority: (map['editorial_priority'] is int) ? map['editorial_priority'] as int : int.tryParse(map['editorial_priority']?.toString() ?? '0') ?? 0,
      isPublished: map['is_published'] == true,
      scheduledPublishAt: map['scheduled_publish_at'] != null ? DateTime.tryParse(map['scheduled_publish_at'].toString()) : null,
      expiresAt: map['expires_at'] != null ? DateTime.tryParse(map['expires_at'].toString()) : null,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
      publishedAt: map['published_at'] != null ? DateTime.tryParse(map['published_at'].toString()) : null,
      createdBy: map['created_by']?.toString(),
      updatedBy: map['updated_by']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'publisher': publisher,
      'description': description,
      'price': price,
      'original_price': originalPrice,
      'currency': currency,
      'thumbnail_url': thumbnailUrl,
      'storage_path': storagePath,
      'order_url': orderUrl,
      'is_available': isAvailable,
      'editorial_priority': editorialPriority,
      'is_published': isPublished,
      'scheduled_publish_at': scheduledPublishAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'published_at': publishedAt?.toIso8601String(),
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  bool get isDiscounted => originalPrice != null && originalPrice! > price;

  int get discountPercentage => isDiscounted ? (((originalPrice! - price) / originalPrice!) * 100).round() : 0;
}
