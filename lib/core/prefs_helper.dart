import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  /// Ensures SharedPreferences does not crash due to Pigeon InstanceManager concurrent access bugs.
  static Future<SharedPreferences> getPrefs() async {
    for (int i = 0; i < 3; i++) {
      try {
        return await SharedPreferences.getInstance();
      } catch (e) {
        if (i == 2) rethrow;
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    throw Exception('Failed to initialize SharedPreferences');
  }
}
