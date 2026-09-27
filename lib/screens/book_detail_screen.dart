import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/online_book.dart';
import '../models/book_review.dart';
import '../services/online_book_service.dart';
import '../services/book_review_service.dart';
import '../services/analytics_service.dart';
import '../services/sound_service.dart';
import '../widgets/keyboard_press_effect.dart';
import 'magazine_reader_screen.dart';

class BookDetailScreen extends StatefulWidget {
  final OnlineBook book;
  final String userEmail;

  const BookDetailScreen({
    super.key,
    required this.book,
    required this.userEmail,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  final OnlineBookService _bookService = OnlineBookService();
  final BookReviewService _reviewService = BookReviewService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isOnBookshelf = false;
  bool _loadingState = true;
  bool _actionLoading = false;

  List<BookReview> _reviews = [];
  List<OnlineBook> _recommendations = [];
  Map<String, dynamic> _ratingSummary = {};
  bool _reviewsLoading = true;

  @override
  void initState() {
    super.initState();
    _checkBookshelfStatus();
    _loadReviewsAndRecommendations();
  }

  Future<void> _loadReviewsAndRecommendations() async {
    final reviews = await _reviewService.fetchReviewsForBook(widget.book.id);
    final summary = await _reviewService.fetchBookRatingSummary(widget.book.id);
    final recs = await _reviewService.fetchRecommendationsForBook(widget.book.id);
    
    if (mounted) {
      setState(() {
        _reviews = reviews;
        _ratingSummary = summary;
        _recommendations = recs;
        _reviewsLoading = false;
      });
    }
  }

  Future<void> _checkBookshelfStatus() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _loadingState = false);
      return;
    }
    final bookIds = await _bookService.fetchUserBookshelfBookIds(userId);
    if (mounted) {
      setState(() {
        _isOnBookshelf = bookIds.contains(widget.book.id);
        _loadingState = false;
      });
    }
  }

  Future<void> _toggleBookshelf() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('বুকশেলফে যোগ করতে অনুগ্রহ করে লগইন করুন।')),
      );
      return;
    }

    setState(() => _actionLoading = true);
    SoundService.playButtonSound();

    if (_isOnBookshelf) {
      final success = await _bookService.removeFromBookshelf(userId, widget.book.id);
      if (!mounted) return;
      if (success) {
        setState(() {
          _isOnBookshelf = false;
          _actionLoading = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('বুকশেলফ থেকে বইটি সরিয়ে নেওয়া হয়েছে।')),
        );
      } else {
        setState(() => _actionLoading = false);
      }
    } else {
      final success = await _bookService.addToBookshelf(userId, widget.book.id);
      if (!mounted) return;
      if (success) {
        setState(() {
          _isOnBookshelf = true;
          _actionLoading = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📚 সফলভাবে আপনার বুকশেলফে যোগ করা হয়েছে!')),
        );
      } else {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _readBook() async {
    SoundService.playButtonSound();
    final nav = Navigator.of(context);
    await _analyticsService.logEvent(
      contentType: 'online_book',
      contentId: widget.book.id,
      eventType: 'read',
    );

    // Open existing ProtectedReaderScreen (3D reader)
    nav.push(
      MaterialPageRoute(
        builder: (_) => ProtectedReaderScreen(
          magazineId: widget.book.id,
          title: widget.book.title,
          userEmail: widget.userEmail,
        ),
      ),
    );
  }

  Future<void> _orderBook() async {
    SoundService.playButtonSound();
    await _analyticsService.logEvent(
      contentType: 'online_book',
      contentId: widget.book.id,
      eventType: 'order_click',
    );

    final orderUrl = widget.book.orderUrl;
    if (orderUrl != null && orderUrl.trim().isNotEmpty) {
      final uri = Uri.parse(orderUrl.trim().startsWith('http') ? orderUrl.trim() : 'https://${orderUrl.trim()}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Default WhatsApp Order Fallback
    final waUrl = 'https://wa.me/919432569171?text=${Uri.encodeComponent('নমস্কার, আমি "${widget.book.title}" বইটি অর্ডার করতে চাই।')}';
    final waUri = Uri.parse(waUrl);
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: Text(book.title, style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00E676)),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Cover Image
            Center(
              child: Container(
                height: 280,
                width: 190,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: book.thumbnailUrl != null && book.thumbnailUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: book.thumbnailUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(color: Color(0xFF00E676)),
                          ),
                          errorWidget: (_, __, ___) => const Icon(Icons.book, size: 64, color: Colors.white38),
                        )
                      : const Icon(Icons.book, size: 64, color: Colors.white38),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title & Author
            Text(
              book.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'লেখক: ${book.author ?? 'অন্যান্য'}',
              style: const TextStyle(color: Color(0xFF81C784), fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              'প্রকাশক: ${book.publisher}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Price Row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'মূল্য: ₹${book.price.toStringAsFixed(0)}',
                  style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (book.isDiscounted) ...[
                  const SizedBox(width: 12),
                  Text(
                    '₹${book.originalPrice!.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white38, decoration: TextDecoration.lineThrough, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.redAccent, width: 0.8),
                    ),
                    child: Text(
                      '${book.discountPercentage}% ছাড়',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 16),

            // Description
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'বইয়ের বিবরণ (Description)',
                style: TextStyle(color: Color(0xFF00E676), fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                book.description ?? 'কোনো বিবরণ দেওয়া নেই।',
                style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.6),
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            _loadingState
                ? const CircularProgressIndicator(color: Color(0xFF00E676))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Read Book Button
                      KeyboardPressEffect(
                        onTap: _readBook,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E676).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.menu_book_rounded, color: Colors.black, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '📖 বইটি পড়ুন (Read Book)',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Add/Remove Bookshelf Button
                      KeyboardPressEffect(
                        onTap: _actionLoading ? () {} : _toggleBookshelf,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _isOnBookshelf ? const Color(0xFF1E2E23) : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isOnBookshelf ? const Color(0xFF00E676) : Colors.white24,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isOnBookshelf ? Icons.check_circle_rounded : Icons.bookmark_add_rounded,
                                color: _isOnBookshelf ? const Color(0xFF00E676) : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isOnBookshelf ? '✓ বুকশেলফে আছে (Remove)' : '📚 আমার বুকশেলফে যোগ করুন',
                                style: TextStyle(
                                  color: _isOnBookshelf ? const Color(0xFF00E676) : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Order Physical Copy Button (if available)
                      if (book.isAvailable)
                        KeyboardPressEffect(
                          onTap: _orderBook,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shopping_cart_rounded, color: Color(0xFFFFD54F), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  '🛒 প্রিন্টেড কপি অর্ডার করুন',
                                  style: TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
            const SizedBox(height: 40),
            
            // Reviews and Recommendations Section
            if (!_reviewsLoading) ...[
              _buildEditorialReview(),
              const SizedBox(height: 24),
              _buildRatingSummary(),
              const SizedBox(height: 24),
              _buildReaderReviews(),
              const SizedBox(height: 16),
              _buildReviewButton(),
              const SizedBox(height: 24),
              _buildRecommendationCarousel(),
            ] else
               const Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorialReview() {
    final editorialReviews = _reviews.where((r) => r.isEditorial).toList();
    if (editorialReviews.isEmpty) return const SizedBox.shrink();

    final rev = editorialReviews.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16251A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF81C784).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star, color: Color(0xFFFFD54F), size: 18),
              SizedBox(width: 8),
              Text('সম্পাদকের মতামত', style: TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          if (rev.reviewTitle != null)
            Text(rev.reviewTitle!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          if (rev.reviewTitle != null) const SizedBox(height: 6),
          Text(rev.reviewBody, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildRatingSummary() {
    if (_ratingSummary['count'] == 0) return const SizedBox.shrink();
    
    final double avg = _ratingSummary['average'] ?? 0.0;
    final int count = _ratingSummary['count'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('রেটিং', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(avg.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(5, (index) => Icon(
                    index < avg.round() ? Icons.star : Icons.star_border,
                    color: const Color(0xFFFFD54F),
                    size: 16,
                  )),
                ),
                Text('$count টি রেটিং', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReaderReviews() {
    final readerReviews = _reviews.where((r) => !r.isEditorial).toList();
    if (readerReviews.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('পাঠকদের মতামত', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        ...readerReviews.take(3).map((rev) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.white38, size: 16),
                    const SizedBox(width: 8),
                    Text('পাঠক', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (rev.rating != null)
                      Row(
                        children: List.generate(5, (index) => Icon(
                          index < rev.rating! ? Icons.star : Icons.star_border,
                          color: const Color(0xFFFFD54F),
                          size: 12,
                        )),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (rev.reviewTitle != null)
                  Text(rev.reviewTitle!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                if (rev.reviewTitle != null) const SizedBox(height: 4),
                Text(rev.reviewBody, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        )).toList(),
      ],
    );
  }

  Widget _buildReviewButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _showReviewDialog,
        icon: const Icon(Icons.rate_review, color: Color(0xFF00E676), size: 18),
        label: const Text('আপনার মতামত দিন', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }

  void _showReviewDialog() {
    final TextEditingController bodyController = TextEditingController();
    int selectedRating = 5;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF18221B),
              title: const Text('মতামত দিন', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) => IconButton(
                      icon: Icon(
                        index < selectedRating ? Icons.star : Icons.star_border,
                        color: const Color(0xFFFFD54F),
                      ),
                      onPressed: () => setDialogState(() => selectedRating = index + 1),
                    )),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'বইটি সম্পর্কে আপনার মতামত লিখুন...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                  onPressed: () async {
                    if (bodyController.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    final success = await _reviewService.submitReview(
                      bookId: widget.book.id,
                      reviewBody: bodyController.text.trim(),
                      rating: selectedRating,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? 'আপনার মতামত পর্যালোচনার জন্য পাঠানো হয়েছে।' : 'মতামত পাঠাতে সমস্যা হয়েছে।')),
                      );
                    }
                  },
                  child: const Text('জমা দিন', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildRecommendationCarousel() {
    if (_recommendations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('আপনার ভালো লাগতে পারে', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _recommendations.length,
            itemBuilder: (context, index) {
              final rec = _recommendations[index];
              return GestureDetector(
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => BookDetailScreen(book: rec, userEmail: widget.userEmail)),
                  );
                },
                child: Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: rec.thumbnailUrl ?? '',
                          height: 130,
                          width: 110,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: Colors.white10, height: 130, width: 110, child: const Icon(Icons.book, color: Colors.white38)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rec.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.2),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
