import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wildlife_gallery_item.dart';

class WildlifeGalleryAdminService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch all gallery items for admin management
  Future<List<WildlifeGalleryItem>> fetchAllGalleryItems({String? categoryFilter}) async {
    try {
      var query = _supabase.from('wildlife_gallery').select();
      if (categoryFilter != null && categoryFilter.isNotEmpty && categoryFilter != 'all') {
        query = query.eq('category', categoryFilter);
      }
      final res = await query
          .order('editorial_priority', ascending: false)
          .order('created_at', ascending: false);
      return (res as List).map((e) => WildlifeGalleryItem.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Helper to determine content type from extension
  String _getContentType(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// Upload image to wildlife_gallery bucket
  Future<Map<String, String>> uploadGalleryImage(PlatformFile file) async {
    // file_picker 13.x removed `PlatformFile.bytes`; the bytes are read on demand.
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Image file is empty or missing bytes');
    }

    final ext = file.extension?.toLowerCase() ?? 'jpg';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final storagePath = 'photos/$fileName';
    final contentType = _getContentType(ext);

    await _supabase.storage.from('wildlife_gallery').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    final publicUrl = _supabase.storage.from('wildlife_gallery').getPublicUrl(storagePath);
    return {
      'publicUrl': publicUrl,
      'storagePath': storagePath,
    };
  }

  /// Create a new gallery record
  Future<WildlifeGalleryItem> createGalleryItem({
    required String title,
    String? caption,
    String? description,
    String? bengaliDescription,
    String? location,
    String? district,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    String? photographerCredit,
    String? photographerProfileLink,
    String? camera,
    String? lens,
    String? aperture,
    String? shutterSpeed,
    String? iso,
    String? focalLength,
    String? commonName,
    String? scientificName,
    String? speciesDescription,
    String? iucnStatus,
    String category = 'Wildlife',
    int priority = 10,
    bool isFeatured = false,
    bool isPublished = true,
    required String storagePath,
  }) async {
    final user = _supabase.auth.currentUser;
    final now = DateTime.now().toUtc();

    final payload = {
      'title': title.trim(),
      'caption': caption?.trim() ?? title.trim(),
      'description': description?.trim(),
      'bengali_description': bengaliDescription?.trim(),
      'location': location?.trim(),
      'district': district?.trim(),
      'state': state?.trim(),
      'country': country?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'photographer_credit': photographerCredit?.trim(),
      'photographer_profile_link': photographerProfileLink?.trim(),
      'camera': camera?.trim(),
      'lens': lens?.trim(),
      'aperture': aperture?.trim(),
      'shutter_speed': shutterSpeed?.trim(),
      'iso': iso?.trim(),
      'focal_length': focalLength?.trim(),
      'common_name': commonName?.trim(),
      'scientific_name': scientificName?.trim(),
      'species_description': speciesDescription?.trim(),
      'iucn_status': iucnStatus?.trim(),
      'category': category.trim(),
      'editorial_priority': priority,
      'is_featured': isFeatured,
      'is_published': isPublished,
      'published_at': isPublished ? now.toIso8601String() : null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'storage_path': storagePath,
      if (user != null) 'created_by': user.id,
    };

    final res = await _supabase
        .from('wildlife_gallery')
        .insert(payload)
        .select()
        .single();

    return WildlifeGalleryItem.fromJson(res);
  }

  /// Update existing gallery item metadata & storage path safely
  Future<WildlifeGalleryItem> updateGalleryItem({
    required String id,
    required String title,
    String? caption,
    String? description,
    String? bengaliDescription,
    String? location,
    String? district,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    String? photographerCredit,
    String? photographerProfileLink,
    String? camera,
    String? lens,
    String? aperture,
    String? shutterSpeed,
    String? iso,
    String? focalLength,
    String? commonName,
    String? scientificName,
    String? speciesDescription,
    String? iucnStatus,
    String? category,
    int? priority,
    bool? isFeatured,
    bool? isPublished,
    String? newStoragePath,
    String? oldStoragePath,
  }) async {
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'title': title.trim(),
      'caption': caption?.trim() ?? title.trim(),
      'description': description?.trim(),
      'bengali_description': bengaliDescription?.trim(),
      'location': location?.trim(),
      'district': district?.trim(),
      'state': state?.trim(),
      'country': country?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'photographer_credit': photographerCredit?.trim(),
      'photographer_profile_link': photographerProfileLink?.trim(),
      'camera': camera?.trim(),
      'lens': lens?.trim(),
      'aperture': aperture?.trim(),
      'shutter_speed': shutterSpeed?.trim(),
      'iso': iso?.trim(),
      'focal_length': focalLength?.trim(),
      'common_name': commonName?.trim(),
      'scientific_name': scientificName?.trim(),
      'species_description': speciesDescription?.trim(),
      'iucn_status': iucnStatus?.trim(),
      'updated_at': now.toIso8601String(),
    };

    if (category != null) payload['category'] = category.trim();
    if (priority != null) payload['editorial_priority'] = priority;
    if (isFeatured != null) payload['is_featured'] = isFeatured;
    if (isPublished != null) {
      payload['is_published'] = isPublished;
      if (isPublished) payload['published_at'] = now.toIso8601String();
    }
    if (newStoragePath != null && newStoragePath.isNotEmpty) {
      payload['storage_path'] = newStoragePath;
    }

    final res = await _supabase
        .from('wildlife_gallery')
        .update(payload)
        .eq('id', id)
        .select()
        .single();

    // Clean up old storage object only AFTER successful DB update
    if (oldStoragePath != null &&
        oldStoragePath.isNotEmpty &&
        newStoragePath != null &&
        newStoragePath.isNotEmpty &&
        oldStoragePath != newStoragePath) {
      try {
        await _supabase.storage.from('wildlife_gallery').remove([oldStoragePath]);
      } catch (_) {}
    }

    return WildlifeGalleryItem.fromJson(res);
  }

  /// Publish item
  Future<void> publishGalleryItem(String id, {int? priority}) async {
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'is_published': true,
      'published_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    if (priority != null) payload['editorial_priority'] = priority;

    await _supabase.from('wildlife_gallery').update(payload).eq('id', id);
  }

  /// Unpublish item
  Future<void> unpublishGalleryItem(String id) async {
    await _supabase.from('wildlife_gallery').update({
      'is_published': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Update priority
  Future<void> updatePriority(String id, int priority) async {
    await _supabase.from('wildlife_gallery').update({
      'editorial_priority': priority,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Toggle featured status
  Future<void> toggleFeatured(String id, bool isFeatured) async {
    await _supabase.from('wildlife_gallery').update({
      'is_featured': isFeatured,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Delete gallery item permanently and clean storage
  Future<void> deleteGalleryItem(String id, String? storagePath) async {
    await _supabase.from('wildlife_gallery').delete().eq('id', id);
    if (storagePath != null && storagePath.trim().isNotEmpty) {
      try {
        await _supabase.storage.from('wildlife_gallery').remove([storagePath.trim()]);
      } catch (_) {}
    }
  }
}
