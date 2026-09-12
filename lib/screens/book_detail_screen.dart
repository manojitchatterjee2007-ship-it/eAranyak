import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/online_book.dart';
import '../services/online_book_service.dart';
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
  final AnalyticsService _analyticsService = AnalyticsService();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isOnBookshelf = false;
  bool _loadingState = true;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBookshelfStatus();
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
          ],
        ),
      ),
    );
  }
}
