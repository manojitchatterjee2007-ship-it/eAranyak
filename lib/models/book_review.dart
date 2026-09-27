class BookReview {
  final String id;
  final String bookId;
  final String userId;
  final String? reviewTitle;
  final String reviewBody;
  final int? rating;
  final String status;
  final bool isEditorial;
  final bool isFeatured;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;

  // Transient fields for display
  String? userName;
  String? userAvatarUrl;

  BookReview({
    required this.id,
    required this.bookId,
    required this.userId,
    this.reviewTitle,
    required this.reviewBody,
    this.rating,
    required this.status,
    this.isEditorial = false,
    this.isFeatured = false,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.userName,
    this.userAvatarUrl,
  });

  factory BookReview.fromMap(Map<String, dynamic> map) {
    return BookReview(
      id: map['id']?.toString() ?? '',
      bookId: map['book_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      reviewTitle: map['review_title']?.toString(),
      reviewBody: map['review_body']?.toString() ?? '',
      rating: map['rating'] != null ? int.tryParse(map['rating'].toString()) : null,
      status: map['status']?.toString() ?? 'pending',
      isEditorial: map['is_editorial'] == true,
      isFeatured: map['is_featured'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
      publishedAt: map['published_at'] != null ? DateTime.tryParse(map['published_at'].toString()) : null,
      userName: map['user_name']?.toString(), // Can be joined from profiles
      userAvatarUrl: map['user_avatar_url']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'user_id': userId,
      'review_title': reviewTitle,
      'review_body': reviewBody,
      'rating': rating,
      'status': status,
      'is_editorial': isEditorial,
      'is_featured': isFeatured,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'published_at': publishedAt?.toIso8601String(),
    };
  }
}
