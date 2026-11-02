import '../core/prefs_helper.dart';
import 'dart:math';

/// Manages selection of the four realistic forest background scenes
/// (forest_scene1.png through forest_scene4.png) for Library and My Bookshelf.
/// Ensures cross-screen uniqueness (Library scene != Bookshelf scene) always.
class ForestSceneManager {
  static const int sceneCount = 4;
  static const String _libraryCurrent = 'forest_scene_library_current_v3';
  static const String _bookshelfCurrent = 'forest_scene_bookshelf_current_v3';

  static final Random _random = Random();
  static bool _isPicking = false;

  static String assetPath(int index) {
    final safe = (index.clamp(0, sceneCount - 1)) + 1;
    return 'assets/images/forest_scene_$safe.png';
  }

  static Future<int> pickFor(String screen) async {
    // Basic spinlock to prevent race conditions during IndexedStack initialization
    while (_isPicking) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _isPicking = true;
    
    try {
      final prefs = await PrefsHelper.getPrefs();
      final isLibrary = screen == 'library';

      final currentKey = isLibrary ? _libraryCurrent : _bookshelfCurrent;
      final otherKey = isLibrary ? _bookshelfCurrent : _libraryCurrent;

      final int? savedOther = prefs.getInt(otherKey);
      
      // Get what the other screen currently has, or default to a random choice
      final int otherCurrent = savedOther ?? _random.nextInt(sceneCount);

      // Pick a scene index from 0 to sceneCount - 1 that is strictly different from otherCurrent
      int selected;
      if (sceneCount > 1) {
        do {
          selected = _random.nextInt(sceneCount);
        } while (selected == otherCurrent);
      } else {
        selected = 0;
      }

      await prefs.setInt(currentKey, selected);
      
      // If the other hasn't picked yet (first launch), save its assumed value too
      // to ensure it doesn't accidentally pick the same if it was nil
      if (savedOther == null) {
        await prefs.setInt(otherKey, otherCurrent);
      }
      
      return selected;
    } finally {
      _isPicking = false;
    }
  }

  static Future<int?> currentFor(String screen) async {
    final prefs = await PrefsHelper.getPrefs();
    return prefs.getInt(
      screen == 'library' ? _libraryCurrent : _bookshelfCurrent,
    );
  }
}
