import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:earanyak/core/config.dart';

void main() {
  test('Check wildlife_gallery data all', () async {
    final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);
    final response = await supabase
        .from('wildlife_gallery')
        .select('*')
        .limit(3);
    print("Found ${response.length} total items");
    if (response.isNotEmpty) {
      for (var item in response) {
         print("Item id: ${item['id']} title: ${item['title']}, common_name: ${item['common_name']}, scientific_name: ${item['scientific_name']}");
      }
    }
  });
}