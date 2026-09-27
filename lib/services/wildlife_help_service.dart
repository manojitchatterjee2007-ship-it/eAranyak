import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wildlife_help.dart';

class WildlifeHelpService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<bool> submitHelpRequest({
    required String category,
    required String description,
    String? locationApprox,
    String? district,
    String? state,
    String urgency = 'normal',
    String? contactPreference,
    File? mediaFile,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      String? mediaUrl;
      if (mediaFile != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${mediaFile.path.split('/').last}';
        final storagePath = 'wildlife_help/$userId/$fileName';
        await _supabase.storage.from('private_assets').upload(storagePath, mediaFile);
        // We'll store the path instead of public URL since it's private
        mediaUrl = storagePath;
      }

      await _supabase.from('wildlife_help_requests').insert({
        'user_id': userId,
        'category': category,
        'description': description,
        'location_approx': locationApprox,
        'district': district,
        'state': state,
        'urgency': urgency,
        'contact_preference': contactPreference,
        'media_url': mediaUrl,
        'status': 'submitted',
      });
      return true;
    } catch (e) {
      print('Error submitting help request: $e');
      return false;
    }
  }

  Future<List<VerifiedRescueContact>> fetchVerifiedContacts({String? district, String? state}) async {
    try {
      var query = _supabase.from('verified_rescue_contacts').select().eq('status', 'verified');
      
      if (district != null && district.isNotEmpty) {
        query = query.ilike('district', '%$district%');
      }
      if (state != null && state.isNotEmpty) {
        query = query.ilike('state', '%$state%');
      }

      final response = await query.order('name');
      return (response as List).map((e) => VerifiedRescueContact.fromMap(e)).toList();
    } catch (e) {
      print('Error fetching verified contacts: $e');
      return [];
    }
  }

  Future<List<WildlifeSafetyGuideline>> fetchSafetyGuidelines() async {
    try {
      final response = await _supabase
          .from('wildlife_safety_guidelines')
          .select()
          .eq('is_published', true)
          .order('display_order');
      
      return (response as List).map((e) => WildlifeSafetyGuideline.fromMap(e)).toList();
    } catch (e) {
      print('Error fetching safety guidelines: $e');
      return [];
    }
  }
}
