import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- CONFIGURATION ---
const String webBaseUrl = 'https://earanyak.pages.dev';
const String shareBaseUrl = 'https://earanyak.pages.dev';
const String supabaseUrl = 'https://btbcojfuipogpsarjcdw.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0YmNvamZ1aXBvZ3BzYXJqY2R3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyNTU2OTYsImV4cCI6MjEwMjgzMTY5Nn0.q2wtTcZX15QWXMrRg9nWKleZC1F633Ng_d6ajsXuOng';
const String adminEmail = 'ekhonaranyak.edit@gmail.com';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

SupabaseClient get supabase => Supabase.instance.client;

/// Helper to ensure magazine names consistently format as "এখন আরণ্যক"
String formatMagazineTitle(String? title) {
  if (title == null ||
      title.trim().isEmpty ||
      title == 'eআরণ্যক' ||
      title == 'e আরণ্যc' ||
      title == 'e আরণ্যক') {
    return 'এখন আরণ্যক';
  }
  return title
      .replaceAll('e আরণ্যক', 'এখন আরণ্যক')
      .replaceAll('eআরণ্যক', 'এখন আরণ্যক');
}

