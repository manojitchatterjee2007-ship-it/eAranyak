import 'dart:io';
import 'package:flutter/foundation.dart';
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
      debugPrint('Error submitting help request: $e');
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
      final fetched = (response as List).map((e) => VerifiedRescueContact.fromMap(e)).toList();
      
      if (fetched.isEmpty) {
        return [
          VerifiedRescueContact(
            id: 'default-1',
            name: 'Wildlife Crime Control Bureau (WCCB)',
            organization: 'Central Government',
            contactType: 'control_room',
            district: 'All',
            state: 'All India',
            phone: '1800-11-9334',
            email: 'wccb@nic.in',
            website: 'wccb.gov.in',
            availability: '24x7',
            status: 'verified',
          ),
          VerifiedRescueContact(
            id: 'default-2',
            name: 'Wildlife Rescue Centre (Salt Lake)',
            organization: 'West Bengal Forest Dept',
            contactType: 'rescue_centre',
            district: 'Kolkata',
            state: 'West Bengal',
            phone: '033-2334-6900',
            website: 'westbengalforest.gov.in',
            availability: 'Daytime',
            status: 'verified',
          ),
          VerifiedRescueContact(
            id: 'default-3',
            name: 'Forest Department HQ (Aranya Bhawan)',
            organization: 'West Bengal Forest Dept',
            contactType: 'headquarters',
            district: 'Kolkata',
            state: 'West Bengal',
            phone: '033-2335-8581',
            email: 'pccfhoff.fd-wb@gov.in',
            availability: 'Office Hours',
            status: 'verified',
          ),
          VerifiedRescueContact(
            id: 'default-4',
            name: 'Sundarban Tiger Reserve',
            organization: 'West Bengal Forest Dept',
            contactType: 'reserve_office',
            district: 'South 24 Parganas',
            state: 'West Bengal',
            phone: '03210-255070',
            email: 'strfd.fd-wb@gov.in',
            availability: '24x7',
            status: 'verified',
          ),
        ];
      }
      return fetched;
    } catch (e) {
      debugPrint('Error fetching verified contacts: $e');
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
      
      final fetched = (response as List).map((e) => WildlifeSafetyGuideline.fromMap(e)).toList();
      
      if (fetched.isEmpty) {
        return [
          WildlifeSafetyGuideline(
            id: 'guide-1',
            title: 'সাপ দেখলে কী করবেন?',
            content: 'সাপ দেখলে ভয় পাবেন না বা তাকে মারার চেষ্টা করবেন না। সাপ থেকে অন্তত ১০ ফুট দূরত্ব বজায় রাখুন। সাপ সাধারণত নিজ থেকে আক্রমণ করে না। বনদপ্তর বা নিকটবর্তী বন্যপ্রাণী উদ্ধারকারী দলে খবর দিন।',
            displayOrder: 1,
            isPublished: true,
          ),
          WildlifeSafetyGuideline(
            id: 'guide-2',
            title: 'বন্যপ্রাণী লোকালয়ে প্রবেশ করলে',
            content: 'বন্যপ্রাণীকে উত্যক্ত করবেন না। ভিড় জমাবেন না, এতে প্রাণীটি ভয় পেয়ে আক্রমণ করতে পারে। প্রাণীটির যাওয়ার জন্য একটি নিরাপদ রাস্তা খোলা রাখুন এবং দ্রুত বনদপ্তরে জানান।',
            displayOrder: 2,
            isPublished: true,
          ),
          WildlifeSafetyGuideline(
            id: 'guide-3',
            title: 'আহত পাখি বা পশু দেখলে',
            content: 'আহত প্রাণীকে নিজে চিকিৎসা করার চেষ্টা করবেন না। তাকে একটি সুরক্ষিত জায়গায় রাখুন (যেমন কার্টবোর্ড বক্স)। জল বা খাবার জোর করে খাওয়াবেন না। দ্রুত বিশেষজ্ঞদের সাথে যোগাযোগ করুন।',
            displayOrder: 3,
            isPublished: true,
          ),
        ];
      }
      return fetched;
    } catch (e) {
      debugPrint('Error fetching safety guidelines: $e');
      return [];
    }
  }
}
