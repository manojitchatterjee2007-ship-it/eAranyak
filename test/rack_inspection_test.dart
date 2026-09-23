import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inspect current rack layer assets', () async {
    const paths = [
      'assets/images/metal_rack_background_posts.png',
      'assets/images/metal_rack_foreground_lip.png',
      'assets/images/wooden_rack_background_posts.png',
      'assets/images/wooden_rack_foreground_lip.png',
    ];

    for (final path in paths) {
      final file = File(path);

      expect(
        file.existsSync(),
        isTrue,
        reason: 'Rack asset is missing: $path',
      );

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(
        byteData,
        isNotNull,
        reason: 'Could not decode image: $path',
      );

      print(
        '=== $path '
        '(Width: ${image.width}, Height: ${image.height}) ===',
      );

      if (byteData == null) {
        continue;
      }

      final midX = image.width ~/ 2;

      final startY = (image.height * 0.6).toInt();
      final endY = (image.height * 0.9).toInt();

      for (int y = startY; y < endY; y++) {
        final offset = (y * image.width + midX) * 4;

        final r = byteData.getUint8(offset);
        final g = byteData.getUint8(offset + 1);
        final b = byteData.getUint8(offset + 2);
        final a = byteData.getUint8(offset + 3);

        print(
          'y=$y '
          '(frac: ${(y / image.height).toStringAsFixed(3)}): '
          'r=$r g=$g b=$b a=$a',
        );
      }

      image.dispose();
      codec.dispose();
    }
  });
}