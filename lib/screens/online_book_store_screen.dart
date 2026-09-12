import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/online_book.dart';
import '../services/online_book_service.dart';
import '../services/analytics_service.dart';
import '../widgets/keyboard_press_effect.dart';

class OnlineBookStoreScreen extends StatefulWidget {
  const OnlineBookStoreScreen({super.key});

  @override
  State<OnlineBookStoreScreen> createState() => _OnlineBookStoreScreenState();
}

class _OnlineBookStoreScreenState extends State<OnlineBookStoreScreen> {
  final OnlineBookService _bookService = OnlineBookService();
  final AnalyticsService _analyticsService = AnalyticsService();
  List<OnlineBook> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() => _loading = true);
    final books = await _bookService.fetchPublishedBooks();
    if (mounted) {
      setState(() {
        _books = books;
        _loading = false;
      });
    }
  }

  Future<void> _handleOrderClick(OnlineBook book) async {
    await _analyticsService.logEvent(
      contentType: 'online_book',
      contentId: book.id,
      eventType: 'order_click',
    );

    final orderUrl = book.orderUrl;
    if (orderUrl != null && orderUrl.trim().isNotEmpty) {
      final uri = Uri.parse(orderUrl.trim().startsWith('http') ? orderUrl.trim() : 'https://${orderUrl.trim()}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Default WhatsApp Order Fallback if no specific URL configured
    final waUrl = 'https://wa.me/919432569171?text=${Uri.encodeComponent('নমস্কার, আমি "${book.title}" ছবিটি/বইটি অর্ডার করতে চাই।')}';
    final waUri = Uri.parse(waUrl);
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    }
  }

  void _showBookDetailModal(OnlineBook book) {
    _analyticsService.logEvent(
      contentType: 'online_book',
      contentId: book.id,
      eventType: 'open',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          book.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (book.thumbnailUrl != null && book.thumbnailUrl!.isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: book.thumbnailUrl!,
                      height: 220,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                      ),
                      errorWidget: (_, __, ___) => const Icon(Icons.book, size: 60, color: Colors.white38),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                'লেখক: ${book.author ?? 'অন্যান্য'}',
                style: const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                'প্রকাশক: ${book.publisher}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'মূল্য: ₹${book.price.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (book.isDiscounted) ...[
                    const SizedBox(width: 10),
                    Text(
                      '₹${book.originalPrice!.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white38, decoration: TextDecoration.lineThrough, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.redAccent, width: 0.8),
                      ),
                      child: Text(
                        '${book.discountPercentage}% ছাড়',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Text(
                book.description ?? 'কোনো বিবরণ দেওয়া নেই।',
                style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বন্ধ করুন', style: TextStyle(color: Colors.white54)),
          ),
          if (book.isAvailable)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              onPressed: () {
                Navigator.pop(ctx);
                _handleOrderClick(book);
              },
              icon: const Icon(Icons.shopping_cart_rounded, color: Colors.black, size: 18),
              label: const Text('🛒 অর্ডার করুন', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: const Text('📚 অনলাইন বই ঘর (Online Book Store)'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: const Color(0xFF00E676),
        onRefresh: _loadBooks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Store Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E2E23), Color(0xFF142419)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('📚 ', style: TextStyle(fontSize: 24)),
                        Expanded(
                          child: Text(
                            'এখন আরণ্যক অনলাইন বই ঘর',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      'এখন আরণ্যকের সহযোগিতায় ও অন্যান্য প্রকাশনা থেকে প্রকাশিত প্রকৃতি ও বন্যপ্রাণ ভিত্তিক বইসমূহ সংগ্রহ করুন।',
                      style: TextStyle(color: Color(0xFF81C784), fontSize: 12.5, height: 1.4),
                    ),

                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                )
              else if (_books.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF18221B),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.library_books_outlined, size: 48, color: Colors.white38),
                      SizedBox(height: 12),
                      Text(
                        'আপাতত কোনো বই তালিকাভুক্ত নেই।\nশীঘ্রই নতুন বই আসছে!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 600;
                    final crossAxisCount = isWide ? 2 : 1;

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        mainAxisExtent: 165,
                      ),
                      itemCount: _books.length,
                      itemBuilder: (context, index) {
                        final book = _books[index];
                        return _buildBookCard(book);
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookCard(OnlineBook book) {
    return Card(
      color: const Color(0xFF18221B),
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Color(0xFF2A3D2D)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showBookDetailModal(book),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Book Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 95,
                  height: double.infinity,
                  child: book.thumbnailUrl != null && book.thumbnailUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: book.thumbnailUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: const Color(0xFF121B12),
                            child: const Center(child: CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 2)),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF121B12),
                            child: const Icon(Icons.book, color: Colors.white24, size: 36),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF121B12),
                          child: const Icon(Icons.book, color: Colors.white24, size: 36),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Book Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'লেখক: ${book.author ?? 'অন্যান্য'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF81C784), fontSize: 11),
                    ),
                    Text(
                      'প্রকাশক: ${book.publisher}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    const Spacer(),

                    // Price & Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹${book.price.toStringAsFixed(0)}',
                              style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (book.isDiscounted)
                              Text(
                                '₹${book.originalPrice!.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.white38, decoration: TextDecoration.lineThrough, fontSize: 10),
                              ),
                          ],
                        ),
                        if (book.isAvailable)
                          KeyboardPressEffect(
                            onTap: () => _handleOrderClick(book),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shopping_cart_rounded, size: 14, color: Colors.black),
                                  SizedBox(width: 4),
                                  Text(
                                    'অর্ডার',
                                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('স্টক শেষ', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
