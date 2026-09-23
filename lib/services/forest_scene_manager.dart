import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages selection of the four realistic forest background scenes
/// (forest_scene1.png through forest_scene4.png) for Library and My Bookshelf.
/// Ensures cross-screen uniqueness (Library scene != Bookshelf scene) and
/// shuffles through scenes using a bag approach on each screen opening.
class ForestSceneManager {
  static const int sceneCount = 4;
  static const String _libraryCurrent = 'forest_scene_library_current_v2';
  static const String _bookshelfCurrent = 'forest_scene_bookshelf_current_v2';
  static const String _libraryBag = 'forest_scene_library_bag_v2';
  static const String _bookshelfBag = 'forest_scene_bookshelf_bag_v2';

  static final Random _random = Random();

  static String assetPath(int index) {
    final safe = (index.clamp(0, sceneCount - 1)) + 1;
    return 'assets/images/forest_scene_$safe.png';
  }

  static Future<int> pickFor(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    final isLibrary = screen == 'library';

    final currentKey = isLibrary ? _libraryCurrent : _bookshelfCurrent;
    final otherKey = isLibrary ? _bookshelfCurrent : _libraryCurrent;
    final bagKey = isLibrary ? _libraryBag : _bookshelfBag;

    final otherCurrent = prefs.getInt(otherKey);

    List<String> bagStr = prefs.getStringList(bagKey) ?? [];
    List<int> bag = bagStr.map((e) => int.parse(e)).toList();

    if (bag.isEmpty) {
      bag = List<int>.generate(sceneCount, (i) => i)..shuffle(_random);
      final current = prefs.getInt(currentKey);
      if (current != null && bag.length > 1 && bag.first == current) {
        final temp = bag[0];
        bag[0] = bag[1];
        bag[1] = temp;
      }
    }

    int selected = bag.removeAt(0);

    // Ensure cross-screen uniqueness: Library scene != Bookshelf scene
    if (otherCurrent != null && selected == otherCurrent) {
      if (bag.isNotEmpty) {
        final altIndex = bag.indexWhere((i) => i != otherCurrent);
        if (altIndex != -1) {
          final alt = bag.removeAt(altIndex);
          bag.add(selected);
          selected = alt;
        } else {
          bag.add(selected);
          selected = (otherCurrent + 1) % sceneCount;
        }
      } else {
        selected = (otherCurrent + 1) % sceneCount;
      }
    }

    await prefs.setStringList(bagKey, bag.map((e) => e.toString()).toList());
    await prefs.setInt(currentKey, selected);
    return selected;
  }

  static Future<int?> currentFor(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(
      screen == 'library' ? _libraryCurrent : _bookshelfCurrent,
    );
  }
}
