import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/online_book.dart';

class OnlineBookService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch published online books for public view
  Future<List<OnlineBook>> fetchPublishedBooks() async {
    try {
      final res = await _supabase
          .from('online_books')
          .select()
          .eq('is_published', true)
          .order('editorial_priority', ascending: false)
          .order('published_at', ascending: false);

      final List<dynamic> list = res as List<dynamic>;
      final now = DateTime.now();

      return list
          .map((m) => OnlineBook.fromMap(Map<String, dynamic>.from(m)))
          .where((b) {
        if (b.scheduledPublishAt != null && b.scheduledPublishAt!.isAfter(now)) {
          return false;
        }
        if (b.expiresAt != null && b.expiresAt!.isBefore(now)) {
          return false;
        }
        return true;
      }).toList();
    } catch (e) {
      debugPrint('[OnlineBookService] fetchPublishedBooks error: $e');
      return [];
    }
  }

  /// Fetch all online books for admin
  Future<List<OnlineBook>> fetchAllBooks({String filter = 'all'}) async {
    try {
      var query = _supabase.from('online_books').select();

      if (filter == 'published') {
        query = _supabase.from('online_books').select().eq('is_published', true);
      } else if (filter == 'draft') {
        query = _supabase.from('online_books').select().eq('is_published', false);
      } else if (filter == 'unavailable') {
        query = _supabase.from('online_books').select().eq('is_available', false);
      }

      final res = await query
          .order('editorial_priority', ascending: false)
          .order('created_at', ascending: false);

      final List<dynamic> list = res as List<dynamic>;
      return list
          .map((m) => OnlineBook.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('[OnlineBookService] fetchAllBooks error: $e');
      return [];
    }
  }

  /// Create a new online book with cover upload
  Future<OnlineBook> createBook({
    required String title,
    String? author,
    required String publisher,
    String? description,
    required double price,
    double? originalPrice,
    String currency = 'INR',
    String? orderUrl,
    bool isAvailable = true,
    int editorialPriority = 0,
    bool isPublished = false,
    DateTime? scheduledPublishAt,
    DateTime? expiresAt,
    PlatformFile? coverFile,
  }) async {
    String? thumbnailUrl;
    String? storagePath;

    // file_picker 13.x removed `PlatformFile.bytes`; the cover bytes are read on
    // demand. An unreadable file keeps the old null-bytes behaviour (no upload).
    if (coverFile != null) {
      Uint8List? coverBytes;
      try {
        coverBytes = await coverFile.readAsBytes();
      } catch (_) {
        coverBytes = null;
      }

      if (coverBytes != null && coverBytes.isNotEmpty) {
        final fileExt = coverFile.extension ?? 'jpg';
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_cover.$fileExt';
        storagePath = 'books/covers/$fileName';

        await _supabase.storage.from('online-books').uploadBinary(
              storagePath,
              coverBytes,
              fileOptions: FileOptions(
                contentType: 'image/$fileExt',
                upsert: true,
              ),
            );

        thumbnailUrl = _supabase.storage
            .from('online-books')
            .getPublicUrl(storagePath);
      }
    }

    final userId = _supabase.auth.currentUser?.id;
    final now = DateTime.now().toIso8601String();

    final data = {
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
      'created_at': now,
      'updated_at': now,
      'published_at': isPublished ? now : null,
      'created_by': userId,
      'updated_by': userId,
    };

    final res = await _supabase
        .from('online_books')
        .insert(data)
        .select()
        .single();

    return OnlineBook.fromMap(Map<String, dynamic>.from(res));
  }

  /// Update an existing online book
  Future<void> updateBook({
    required String id,
    required String title,
    String? author,
    required String publisher,
    String? description,
    required double price,
    double? originalPrice,
    String currency = 'INR',
    String? orderUrl,
    bool isAvailable = true,
    int editorialPriority = 0,
    bool isPublished = false,
    DateTime? scheduledPublishAt,
    DateTime? expiresAt,
    PlatformFile? newCoverFile,
    String? existingStoragePath,
    String? existingThumbnailUrl,
  }) async {
    String? thumbnailUrl = existingThumbnailUrl;
    String? storagePath = existingStoragePath;

    // file_picker 13.x removed `PlatformFile.bytes`; the cover bytes are read on
    // demand. An unreadable file keeps the old null-bytes behaviour (no upload).
    if (newCoverFile != null) {
      Uint8List? coverBytes;
      try {
        coverBytes = await newCoverFile.readAsBytes();
      } catch (_) {
        coverBytes = null;
      }

      if (coverBytes != null && coverBytes.isNotEmpty) {
        final fileExt = newCoverFile.extension ?? 'jpg';
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_cover.$fileExt';
        storagePath = 'books/covers/$fileName';

        await _supabase.storage.from('online-books').uploadBinary(
              storagePath,
              coverBytes,
              fileOptions: FileOptions(
                contentType: 'image/$fileExt',
                upsert: true,
              ),
            );

        thumbnailUrl = _supabase.storage
            .from('online-books')
            .getPublicUrl(storagePath);
      }
    }

    final userId = _supabase.auth.currentUser?.id;
    final now = DateTime.now().toIso8601String();

    final data = {
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
      'updated_at': now,
      'published_at': isPublished ? now : null,
      'updated_by': userId,
    };

    await _supabase.from('online_books').update(data).eq('id', id);
  }

  /// Toggle publish status
  Future<void> setPublishStatus(String id, bool publish) async {
    final now = DateTime.now().toIso8601String();
    await _supabase.from('online_books').update({
      'is_published': publish,
      'published_at': publish ? now : null,
      'updated_at': now,
    }).eq('id', id);
  }

  /// Delete an online book
  Future<void> deleteBook(String id, {String? storagePath}) async {
    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        await _supabase.storage.from('online-books').remove([storagePath]);
      } catch (_) {}
    }
    await _supabase.from('online_books').delete().eq('id', id);
  }

  /// Fetch bookshelf book IDs for a user
  Future<List<String>> fetchUserBookshelfBookIds(String userId) async {
    try {
      final res = await _supabase
          .from('user_bookshelf')
          .select('book_id')
          .eq('user_id', userId);
      return (res as List<dynamic>).map((e) => e['book_id'].toString()).toList();
    } catch (e) {
      debugPrint('[OnlineBookService] fetchUserBookshelfBookIds error: $e');
      return [];
    }
  }

  /// Fetch full bookshelf online books for a user
  Future<List<OnlineBook>> fetchUserBookshelfBooks(String userId) async {
    try {
      final res = await _supabase
          .from('user_bookshelf')
          .select('book_id, online_books(*)')
          .eq('user_id', userId)
          .order('added_at', ascending: false);

      final List<dynamic> list = res as List<dynamic>;
      List<OnlineBook> books = [];
      for (final item in list) {
        final bookMap = item['online_books'];
        if (bookMap != null) {
          books.add(OnlineBook.fromMap(Map<String, dynamic>.from(bookMap)));
        }
      }
      return books;
    } catch (e) {
      debugPrint('[OnlineBookService] fetchUserBookshelfBooks error: $e');
      return [];
    }
  }

  /// Add book to user bookshelf
  Future<bool> addToBookshelf(String userId, String bookId) async {
    try {
      await _supabase.from('user_bookshelf').upsert({
        'user_id': userId,
        'book_id': bookId,
        'added_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,book_id');
      return true;
    } catch (e) {
      debugPrint('[OnlineBookService] addToBookshelf error: $e');
      return false;
    }
  }

  /// Remove book from user bookshelf
  Future<bool> removeFromBookshelf(String userId, String bookId) async {
    try {
      await _supabase
          .from('user_bookshelf')
          .delete()
          .eq('user_id', userId)
          .eq('book_id', bookId);
      return true;
    } catch (e) {
      debugPrint('[OnlineBookService] removeFromBookshelf error: $e');
      return false;
    }
  }
}
