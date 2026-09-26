import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../widgets/keyboard_press_effect.dart';
import '../services/sound_service.dart';
import '../models/about_us_content.dart';

class AboutUsScreen extends StatefulWidget {
  const AboutUsScreen({super.key});

  @override
  State<AboutUsScreen> createState() => _AboutUsScreenState();
}

class _AboutUsScreenState extends State<AboutUsScreen> {
  final _supabase = Supabase.instance.client;
  late Future<AboutUsContent?> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = _fetchContent();
  }

  Future<AboutUsContent?> _fetchContent() async {
    final response = await _supabase
        .from('about_us_content')
        .select('*')
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      return AboutUsContent.fromJson(response);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'About Us',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: FutureBuilder<AboutUsContent?>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)));
          }

          final content = snapshot.data;
          // Fallback if no published content
          if (content == null) {
            return _buildFallbackContent(context);
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (content.heroImageUrl != null && content.heroImageUrl!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CachedNetworkImage(
                        imageUrl: content.heroImageUrl!,
                        fit: BoxFit.cover,
                        height: 200,
                        width: double.infinity,
                        errorWidget: (context, url, error) => const SizedBox.shrink(),
                      ),
                    ),
                  
                  Text(
                    content.titleBn,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (content.subtitleBn != null && content.subtitleBn!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      content.subtitleBn!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 16,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  if (content.bodyBn != null && content.bodyBn!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18221B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        content.bodyBn!,
                        textAlign: TextAlign.justify,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                  
                  if (content.whatWeDoTitleBn != null && content.whatWeDoTitleBn!.isNotEmpty) ...[
                     const SizedBox(height: 32),
                     Text(
                        content.whatWeDoTitleBn!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18221B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          content.whatWeDoBodyBn ?? '',
                          textAlign: TextAlign.justify,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                      ),
                  ],

                  const SizedBox(height: 40),

                  // Go Back Button
                  KeyboardPressEffect(
                    onTap: () {
                      SoundService.playButtonSound();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'ফিরে যান (Back)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildFallbackContent(BuildContext context) {
    return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF142419),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.25),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/about_us.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'About us - আমাদের সম্বন্ধে',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF18221B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  'eআরণ্যক - প্রকৃতি, বন্যপ্রাণী এবং পরিবেশ সম্পর্কে জানার, শেখার ও ভালোবাসার একটি ডিজিটাল উদ্যোগ। আমাদের লক্ষ্য হলো বাংলাভাষী মানুষের কাছে প্রকৃতির বিস্ময়কর জগৎকে সহজ, আকর্ষণীয় এবং আনন্দদায়কভাবে পৌঁছে দেওয়া। ছবি, লেখা, পাখির ডাক, খেলা এবং বিভিন্ন শিক্ষামূলক উপস্থাপনার মাধ্যমে আমরা মানুষ ও প্রকৃতির মধ্যে আরও গভীর সংযোগ গড়ে তুলতে চাই।',
                  textAlign: TextAlign.justify,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              KeyboardPressEffect(
                onTap: () {
                  SoundService.playButtonSound();
                  Navigator.pop(context);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'ফিরে যান (Back)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
