import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Whether a pixel qualifies as "light green" — close to the app's brand
/// accent colour #00E676 (g=230). The threshold is deliberately high so that
/// muted olive/green tones that are part of the icon's natural design are not
/// confused with a bright light-green halo/ring artefact added by the launcher
/// icon generator.
bool _isLightGreen(img.Pixel p) =>
    p.g > 160 && (p.g > p.r + 40) && (p.g > p.b + 60) && p.a > 10;

void main() {
  test('Verify generated launcher icon files have no light green border', () {
    final paths = [
      'android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png',
      'android/app/src/main/res/mipmap-xxxhdpi/launcher_icon.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    ];

    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final image = img.decodeImage(file.readAsBytesSync())!;
      print('=== $path (${image.width}x${image.height}) ===');

      final w = image.width;
      final h = image.height;
      // Border threshold: pixels within 10% of any edge are considered "border".
      // A light green border indicates an icon generation artifact (e.g. a halo
      // ring added by the launcher icon generator). Light green in the centre of
      // the icon is the legitimate brand colour and is acceptable.
      final borderThreshold = (w * 0.10).round();

      int borderLightGreenCount = 0;
      int centerLightGreenCount = 0;

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          if (!_isLightGreen(p)) continue;
          final isBorder =
              x < borderThreshold ||
              x > w - borderThreshold ||
              y < borderThreshold ||
              y > h - borderThreshold;
          if (isBorder) {
            borderLightGreenCount++;
          } else {
            centerLightGreenCount++;
          }
        }
      }

      print(
          '  Light green pixels: border=$borderLightGreenCount center=$centerLightGreenCount');

      // The icon design legitimately uses light green (brand colour). Fail only
      // when light green appears at the border, which signals a generation
      // artefact rather than intentional design.
      expect(borderLightGreenCount, equals(0),
          reason: 'Light green border pixels indicate an icon generation '
              'artefact (halo/ring) around the launcher icon.');
    }
  });
}
