import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_review.dart';
import '../models/book_collection.dart';
import '../models/online_book.dart';

class BookReviewService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<BookReview>> fetchReviewsForBook(String bookId) async {
    try {
      final response = await _supabase
          .from('book_reviews')
          .select()
          .eq('book_id', bookId)
          .inFilter('status', ['approved', 'published'])
          .order('is_editorial', ascending: false)
          .order('is_featured', ascending: false)
          .order('created_at', ascending: false);

      return (response as List).map((e) => BookReview.fromMap(e)).toList();
    } catch (e) {
      print('Error fetching book reviews: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchBookRatingSummary(String bookId) async {
    try {
      final response = await _supabase
          .from('book_reviews')
          .select('rating')
          .eq('book_id', bookId)
          .inFilter('status', ['approved', 'published'])
          .not('rating', 'is', null);

      if (response.isEmpty) {
        return {'average': 0.0, 'count': 0, 'distribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}};
      }

      int count = response.length;
      double sum = 0;
      Map<int, int> distribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

      for (var r in response) {
        int rating = r['rating'] as int;
        sum += rating;
        distribution[rating] = (distribution[rating] ?? 0) + 1;
      }

      return {
        'average': sum / count,
        'count': count,
        'distribution': distribution,
      };
    } catch (e) {
      print('Error fetching rating summary: $e');
      return {'average': 0.0, 'count': 0, 'distribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}};
    }
  }

  Future<bool> submitReview({
    required String bookId,
    required String reviewBody,
    int? rating,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase.from('book_reviews').insert({
        'book_id': bookId,
        'user_id': userId,
        'review_body': reviewBody,
        'rating': rating,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      print('Error submitting review: $e');
      return false;
    }
  }

  Future<List<OnlineBook>> fetchRecommendationsForBook(String bookId) async {
    try {
      final response = await _supabase
          .from('book_recommendations')
          .select('recommended_book_id, online_books(*)')
          .eq('book_id', bookId)
          .order('display_order', ascending: true);

      List<OnlineBook> recommendedBooks = [];
      for (var item in response) {
        if (item['online_books'] != null) {
          recommendedBooks.add(OnlineBook.fromMap(item['online_books']));
        }
      }
      return recommendedBooks;
    } catch (e) {
      print('Error fetching recommendations: $e');
      return [];
    }
  }

  Future<List<BookCollection>> fetchCollections() async {
    try {
      final response = await _supabase
          .from('book_collections')
          .select('*, book_collection_items(online_books(*))')
          .eq('is_published', true)
          .order('display_order', ascending: true);

      List<BookCollection> collections = [];
      for (var item in response) {
        var collection = BookCollection.fromMap(item);
        
        List<OnlineBook> books = [];
        var items = item['book_collection_items'] as List?;
        if (items != null) {
          for (var i in items) {
            if (i['online_books'] != null) {
              books.add(OnlineBook.fromMap(i['online_books']));
            }
          }
        }
        collection.books = books;
        collections.add(collection);
      }
      return collections;
    } catch (e) {
      print('Error fetching collections: $e');
      return [];
    }
  }
}
