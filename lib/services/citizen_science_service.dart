import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wildlife_sighting.dart';
import 'sighting_validation.dart';

/// Raised when a citizen submission cannot be completed; the message is always
/// safe to show to the contributor.
class SightingSubmissionException implements Exception {
  final String message;
  const SightingSubmissionException(this.message);

  @override
  String toString() => message;
}

/// Citizen-facing service for submitting and reading wildlife sightings.
///
/// Security model (see supabase/migrations/20260927120000_phase5_*):
///  * rows are owned by the authenticated contributor and readable only by the
///    owner or an editor;
///  * media lives in the private `citizen_sightings` bucket and is rendered
///    through ProtectedImage (120s signed URLs) — never a public URL;
///  * publication state, masking and notifications are computed server-side.
class CitizenScienceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String mediaBucket = 'citizen_sightings';
  static const String publicView = 'public_wildlife_sightings';
  static const String publicMediaView = 'public_sighting_media';

  // Client-side throttle: the database enforces the hard limits, this simply
  // avoids pointless round-trips for accidental double taps.
  static final List<DateTime> _submitTimestamps = <DateTime>[];
  static const int _maxSubmitsPerMinute = 6;

  bool _withinClientRateLimit() {
    final now = DateTime.now();
    _submitTimestamps.removeWhere(
        (ts) => now.difference(ts) > const Duration(minutes: 1));
    if (_submitTimestamps.length >= _maxSubmitsPerMinute) return false;
    _submitTimestamps.add(now);
    return true;
  }

  String? get currentUserId => _supabase.auth.currentUser?.id;

  static String _dateOnly(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();

  String _friendlyServerError(String raw) {
    final message = raw.trim();
    if (message.contains('Daily submission limit')) return message;
    if (message.contains('Please try again')) return message;
    if (message.contains('Species name is required')) {
      return 'প্রজাতির নাম আবশ্যক';
    }
    if (message.contains('row-level security')) {
      return 'এই কাজটি করার অনুমতি নেই';
    }
    return message.isEmpty ? 'অজানা সমস্যা হয়েছে' : message;
  }
}
