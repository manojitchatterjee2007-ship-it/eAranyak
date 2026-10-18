import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:earanyak/core/config.dart';

void main() {
  test('Check daily_wildlife_features', () async {
    final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);
    final response = await supabase
        .from('daily_wildlife_features')
        .select('*')
        .order('created_at', ascending: false)
        .limit(2);
    print("Found ${response.length} features");
    for (var f in response) {
      print("Id: ${f['id']}, Status: ${f['status']}, Generation status: ${f['image_generation_status']}");
    }
  });
}