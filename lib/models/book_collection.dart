import 'online_book.dart';

class BookCollection {
  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final int displayOrder;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Populated when items are fetched
  List<OnlineBook> books;

  BookCollection({
    required this.id,
    required this.title,
    this.description,
    this.coverUrl,
    this.displayOrder = 0,
    this.isPublished = false,
    required this.createdAt,
    required this.updatedAt,
    this.books = const [],
  });

  factory BookCollection.fromMap(Map<String, dynamic> map) {
    return BookCollection(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      coverUrl: map['cover_url']?.toString(),
      displayOrder: map['display_order'] != null ? int.tryParse(map['display_order'].toString()) ?? 0 : 0,
      isPublished: map['is_published'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
