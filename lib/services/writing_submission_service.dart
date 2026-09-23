import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../models/writing_submission.dart';

class WritingSubmissionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch a single submission by ID
  static Future<WritingSubmission?> fetchSubmissionById(String id) async {
    try {
      final res = await Supabase.instance.client
          .from('writing_submissions')
          .select('*, community_article_images(*)')
          .eq('id', id)
          .maybeSingle();
      if (res != null) {
        return WritingSubmission.fromJson(res);
      }
    } catch (_) {}
    return null;
  }

  /// Helper to calculate word count across Bengali and English text.
  static int countWords(String text) {
    if (text.trim().isEmpty) return 0;
    final words = text
        .trim()
        .split(RegExp(r'[\s\n\r\t,.\-!?;:॥।]+'))
        .where((w) => w.isNotEmpty);
    return words.length;
  }

  /// Get current user profile name for prefilling field.
  Future<String?> getCurrentUserName() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final res = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && res['full_name'] != null) {
        final name = res['full_name'].toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}

    // Fallback to user metadata or email
    final metaName = user.userMetadata?['full_name'] ?? user.userMetadata?['name'];
    if (metaName != null && metaName.toString().trim().isNotEmpty) {
      return metaName.toString().trim();
    }
    return user.email?.split('@').first;
  }

  /// Upload photos selected by user to Supabase Storage bucket 'writing_submissions'
  Future<List<String>> uploadPhotos(List<PlatformFile> files) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User is not logged in');

    final List<String> uploadedUrls = [];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      // file_picker 13.x removed `PlatformFile.bytes`; read the bytes on demand
      // and skip files the platform cannot read (same as the old null case).
      Uint8List? bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        bytes = null;
      }
      if (bytes == null || bytes.isEmpty) continue;

      final ext = file.extension?.toLowerCase() ?? 'jpg';
      // Validate image extensions
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
        continue; // Skip invalid extensions like svg, gif, executables
      }

      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      final path = '${user.id}/$fileName';

      await _supabase.storage.from('writing_submissions').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/${ext == 'png' ? 'png' : (ext == 'webp' ? 'webp' : 'jpeg')}',
              upsert: true,
            ),
          );

      final publicUrl = _supabase.storage.from('writing_submissions').getPublicUrl(path);
      uploadedUrls.add(publicUrl);
    }

    return uploadedUrls;
  }

  /// Submit user article to Supabase
  Future<WritingSubmission> submitWriting({
    required String title,
    required String authorName,
    required String articleContent,
    required List<PlatformFile> photos,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User is not logged in / অনুগ্রহ করে লগইন করুন');

    final wordCount = countWords(articleContent);
    if (wordCount > 1000) {
      throw Exception('লেখা ১,০০০ শব্দের বেশি হতে পারবে না (বর্তমান শব্দ সংখ্যা: $wordCount)');
    }
    if (title.trim().isEmpty) {
      throw Exception('অনুগ্রহ করে লেখার শিরোনাম লিখুন');
    }
    if (articleContent.trim().isEmpty) {
      throw Exception('অনুগ্রহ করে আপনার লেখাটি লিখুন');
    }

    // 1. Upload photos if any
    List<String> photoUrls = [];
    if (photos.isNotEmpty) {
      try {
        photoUrls = await uploadPhotos(photos);
      } catch (_) {
        // Photos are optional, proceed gracefully if storage policy fails
      }
    }

    final excerpt = articleContent.length > 180
        ? '${articleContent.substring(0, 180)}...'
        : articleContent;

    // 2. Save submission record
    final Map<String, dynamic> payload = {
      'user_id': user.id,
      'author_name': authorName.trim(),
      'title': title.trim(),
      'article_content': articleContent.trim(),
      'word_count': wordCount,
      'status': 'pending',
      'photo_urls': photoUrls,
      'excerpt': excerpt,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'is_published': false,
      'editorial_priority': 0,
    };

    final res = await _supabase
        .from('writing_submissions')
        .insert(payload)
        .select()
        .single();

    final articleId = res['id']?.toString();
    if (articleId != null && photoUrls.isNotEmpty) {
      for (int i = 0; i < photoUrls.length; i++) {
        try {
          await _supabase.from('community_article_images').insert({
            'article_id': articleId,
            'image_url': photoUrls[i],
            'display_order': i,
          });
        } catch (_) {}
      }
    }

    return WritingSubmission.fromJson(res);
  }

  /// Fetch user's own submissions
  Future<List<WritingSubmission>> fetchMySubmissions() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await _supabase
          .from('writing_submissions')
          .select('*, community_article_images(*)')
          .eq('user_id', user.id)
          .order('submitted_at', ascending: false);

      return (res as List).map((e) => WritingSubmission.fromJson(e)).toList();
    } catch (_) {
      final res = await _supabase
          .from('writing_submissions')
          .select()
          .eq('user_id', user.id)
          .order('submitted_at', ascending: false);

      return (res as List).map((e) => WritingSubmission.fromJson(e)).toList();
    }
  }

  /// Fetch PUBLISHED community articles for PUBLIC DISPLAY
  /// Rule: is_published = true AND status = 'published'
  /// Ordered by: editorial_priority DESC, published_at DESC
  Future<List<WritingSubmission>> fetchPublishedArticles() async {
    try {
      try {
        final res = await _supabase
            .from('writing_submissions')
            .select('*, community_article_images(*)')
            .eq('is_published', true)
            .eq('status', 'published')
            .order('editorial_priority', ascending: false)
            .order('published_at', ascending: false);

        return (res as List).map((e) => WritingSubmission.fromJson(e)).toList();
      } catch (_) {
        final res = await _supabase
            .from('writing_submissions')
            .select()
            .eq('is_published', true)
            .eq('status', 'published')
            .order('editorial_priority', ascending: false)
            .order('published_at', ascending: false);

        return (res as List).map((e) => WritingSubmission.fromJson(e)).toList();
      }
    } catch (e) {
      return [];
    }
  }

  /// Fetch all submissions for Admin/Editor with optional status filtering
  Future<List<WritingSubmission>> fetchAllSubmissions({String? statusFilter}) async {
    try {
      var query = _supabase.from('writing_submissions').select('*, community_article_images(*)');

      if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
        if (statusFilter == 'pending') {
          query = query.inFilter('status', ['pending', 'pending_review']);
        } else {
          query = query.eq('status', statusFilter);
        }
      }

      final res = await query.order('submitted_at', ascending: false);
      return (res as List).map((e) => WritingSubmission.fromJson(e)).toList();
    } catch (_) {
      var query = _supabase.from('writing_submissions').select();

      if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
        if (statusFilter == 'pending') {
          query = query.inFilter('status', ['pending', 'pending_review']);
        } else {
          query = query.eq('status', statusFilter);
        }
      }

      final res = await query.order('submitted_at', ascending: false);
      return (res as List).map((e) => WritingSubmission.fromJson(e)).toList();
    }
  }

  /// Approve a submission (without publishing yet)
  Future<void> approveSubmission(String submissionId) async {
    await _supabase
        .from('writing_submissions')
        .update({
          'status': 'approved',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', submissionId);
  }

  /// Reject a submission with optional reason
  Future<void> rejectSubmission(String submissionId, {String? reason}) async {
    await _supabase
        .from('writing_submissions')
        .update({
          'status': 'rejected',
          'is_published': false,
          'rejection_reason': reason,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', submissionId);
  }

  /// Publish a community article
  /// Sets status = 'published', is_published = true, published_at = now()
  /// DOES NOT touch wildlife_news table!
  Future<void> publishSubmission(WritingSubmission submission, {int priority = 10}) async {
    final now = DateTime.now().toUtc();
    await _supabase
        .from('writing_submissions')
        .update({
          'status': 'published',
          'is_published': true,
          'editorial_priority': priority,
          'published_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .eq('id', submission.id);
  }

  /// Unpublish a community article
  Future<void> unpublishSubmission(String submissionId) async {
    await _supabase
        .from('writing_submissions')
        .update({
          'status': 'unpublished',
          'is_published': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', submissionId);
  }

  /// Update editorial priority (0–100)
  Future<void> updatePriority(String submissionId, int priority) async {
    await _supabase
        .from('writing_submissions')
        .update({
          'editorial_priority': priority,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', submissionId);
  }

  /// Delete a submission
  Future<void> deleteSubmission(String submissionId) async {
    await _supabase
        .from('writing_submissions')
        .delete()
        .eq('id', submissionId);
  }

  /// Backward compatibility helper
  Future<void> updateStatus(String submissionId, String newStatus) async {
    if (newStatus == 'published') {
      final now = DateTime.now().toUtc();
      await _supabase.from('writing_submissions').update({
        'status': 'published',
        'is_published': true,
        'published_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('id', submissionId);
    } else if (newStatus == 'rejected') {
      await rejectSubmission(submissionId);
    } else if (newStatus == 'approved') {
      await approveSubmission(submissionId);
    } else {
      await _supabase.from('writing_submissions').update({
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', submissionId);
    }
  }
}
