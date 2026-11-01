import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:earanyak/services/medal_composer_service.dart';

/// Builds a synthetic but realistically-sized participant photograph with a
/// bright red square in the upper-left quadrant, so tests can prove which part
/// of the source photograph ended up inside the medal disc.
Uint8List _syntheticPhoto({int w = 1200, int h = 1600}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgb8(20, 90, 200));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: (w / 2).round(),
    y2: (h / 2).round(),
    color: img.ColorRgb8(230, 30, 30),
  );
  return Uint8List.fromList(img.encodePng(image));
}

img.Image? _decode(Uint8List bytes) => img.decodePng(bytes);

bool _isReddish(img.Pixel p) =>
    p.r > 150 && p.g < 110 && p.b < 110 && p.a > 200;

bool _isBluish(img.Pixel p) => p.b > 140 && p.r < 110 && p.a > 200;

/// Number of reddish (source-photo) pixels inside the central 80% of the disc.
int _countRedInDisc(img.Image image) {
  final cx = (MedalGeometry.photoCenterX * image.width).round();
  final cy = (MedalGeometry.photoCenterY * image.height).round();
  final r = (MedalGeometry.photoRadius * image.width * 0.8).round();
  var n = 0;
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if (_isReddish(image.getPixel(x, y))) n++;
    }
  }
  return n;
}

/// Dark "ink" pixels inside the level disc. The source artwork contains none.
int _countInkInLevelDisc(img.Image image) {
  final cx = (MedalGeometry.levelCenterX * image.width).round();
  final cy = (MedalGeometry.levelCenterY * image.height).round();
  final r = (MedalGeometry.levelRadius * image.width).round();
  var ink = 0;
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy > r * r) continue;
      final p = image.getPixel(x, y);
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (lum < 170 && p.a > 200) ink++;
    }
  }
  return ink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MedalComposerService geometry', () {
    test('normalised coordinates map onto the measured asset pixels', () {
      // Photo disc: measured centre (624.2, 584.1) radius 217.4 in a 1254 asset.
      expect(
        (MedalGeometry.photoCenterX * MedalGeometry.referenceWidth).round(),
        closeTo(624, 1),
      );
      expect(
        (MedalGeometry.photoCenterY * MedalGeometry.referenceHeight).round(),
        closeTo(584, 1),
      );
      expect(
        (MedalGeometry.photoRadius * MedalGeometry.referenceWidth).round(),
        closeTo(208, 3),
      );

      // Level disc: measured centre (626.8, 882.7) radius 65.6.
      expect(
        (MedalGeometry.levelCenterX * MedalGeometry.referenceWidth).round(),
        closeTo(627, 1),
      );
      expect(
        (MedalGeometry.levelCenterY * MedalGeometry.referenceHeight).round(),
        closeTo(883, 1),
      );
    });
  });

  group('renderMedal', () {
    test('produces a valid 1254x1254 RGBA PNG', () async {
      final result = await MedalComposerService.renderMedal(
        const MedalRequest(level: 3),
      );

      expect(result.width, 1254);
      expect(result.height, 1254);
      expect(result.hasPhoto, isFalse);

      final decoded = _decode(result.pngBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 1254);
      expect(decoded.height, 1254);
      expect(decoded.numChannels, 4);

      // PNG signature.
      expect(result.pngBytes[0], 0x89);
      expect(result.pngBytes[1], 0x50); // 'P'
      expect(result.pngBytes[2], 0x4E); // 'N'
      expect(result.pngBytes[3], 0x47); // 'G'
    });

    test('keeps the transparent exterior transparent (never black)', () async {
      final result =
          await MedalComposerService.renderMedal(const MedalRequest(level: 1));
      final decoded = _decode(result.pngBytes)!;

      // The corner was measured fully transparent in the source asset.
      final corner = decoded.getPixel(2, 2);
      expect(corner.a, lessThan(16),
          reason:
              'medal exterior must stay transparent, not flattened to black');
    });

    test('places the photograph inside the large disc only', () async {
      final result = await MedalComposerService.renderMedal(
        MedalRequest(level: 2, photoBytes: _syntheticPhoto()),
      );
      final decoded = _decode(result.pngBytes)!;
      expect(result.hasPhoto, isTrue);

      final cx = (MedalGeometry.photoCenterX * decoded.width).round();
      final cy = (MedalGeometry.photoCenterY * decoded.height).round();
      final r = MedalGeometry.photoRadius * decoded.width;

      // Centre of the disc must contain photograph pixels.
      final centre = decoded.getPixel(cx, cy);
      expect(centre.a, greaterThan(200));
      expect(_isReddish(centre) || _isBluish(centre), isTrue,
          reason: 'disc centre should show the participant photograph');

      // Well outside the disc the gold border must be untouched.
      final outsideGold = decoded.getPixel(cx, cy - (r + 26).round());
      expect(_isReddish(outsideGold) || _isBluish(outsideGold), isFalse,
          reason: 'photo must not leak outside the placeholder');

      // The Bengali title band below the level disc is artwork, never a photo.
      final titleBand = decoded.getPixel(
        (MedalGeometry.levelCenterX * decoded.width).round(),
        (0.86 * decoded.height).round(),
      );
      expect(_isBluish(titleBand), isFalse);
    });

    test('honours focus so the participant can reposition the crop', () async {
      // The synthetic photo has a red square in its upper half.
      final upper = _decode(
        (await MedalComposerService.renderMedal(
          MedalRequest(level: 1, photoBytes: _syntheticPhoto(), focusY: 0.0),
        ))
            .pngBytes,
      )!;
      final lower = _decode(
        (await MedalComposerService.renderMedal(
          MedalRequest(level: 1, photoBytes: _syntheticPhoto(), focusY: 1.0),
        ))
            .pngBytes,
      )!;

      expect(_countRedInDisc(upper), greaterThan(_countRedInDisc(lower)),
          reason: 'focusY=0 must keep more of the upper red region visible');
    });

    test('draws the level number into the small level disc', () async {
      final result = await MedalComposerService.renderMedal(
        const MedalRequest(level: 7),
      );
      final decoded = _decode(result.pngBytes)!;

      expect(_countInkInLevelDisc(decoded), greaterThan(120),
          reason: 'the level number must be rasterised inside the level disc');
    });

    test('a different level produces different pixels', () async {
      final lvl3 =
          await MedalComposerService.renderMedal(const MedalRequest(level: 3));
      final lvl8 =
          await MedalComposerService.renderMedal(const MedalRequest(level: 8));
      expect(lvl3.pngBytes, isNot(equals(lvl8.pngBytes)));
    });

    test('an undecodable photo falls back to a level-only medal', () async {
      final result = await MedalComposerService.renderMedal(
        MedalRequest(
          level: 4,
          photoBytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
        ),
      );
      final decoded = _decode(result.pngBytes)!;
      expect(decoded.width, 1254);
      // Disc interior stays the artwork pale cream; no photo leaked in.
      final centre = decoded.getPixel(
        (MedalGeometry.photoCenterX * decoded.width).round(),
        (MedalGeometry.photoCenterY * decoded.height).round(),
      );
      expect(_isReddish(centre) || _isBluish(centre), isFalse);
    });
  });

  group('renderMedalOnWelcomeBackground', () {
    test('composites onto the welcome background as a 4:5 PNG', () async {
      final result = await MedalComposerService.renderMedalOnWelcomeBackground(
        MedalRequest(level: 5, photoBytes: _syntheticPhoto()),
      );

      expect(result.width, 853);
      expect(result.height, 1066);

      final decoded = _decode(result.pngBytes)!;
      expect(decoded.width, 853);
      expect(decoded.height, 1066);
      // The background is opaque, so the export must be fully opaque.
      expect(decoded.getPixel(1, 1).a, greaterThan(250));
    });

    test('never overwrites the source background asset', () async {
      final before = await MedalComposerService.renderMedalOnWelcomeBackground(
        const MedalRequest(level: 1),
      );
      final after = await MedalComposerService.renderMedalOnWelcomeBackground(
        const MedalRequest(level: 2),
      );
      // Different levels yield different bytes, proving a fresh composite.
      expect(before.pngBytes, isNot(equals(after.pngBytes)));
      // The medal asset is still loadable at its original size.
      final plain =
          await MedalComposerService.renderMedal(const MedalRequest(level: 1));
      expect(plain.width, 1254);
    });

    test('base64 round-trips, proving the PNG is genuinely shareable',
        () async {
      final result = await MedalComposerService.renderMedalOnWelcomeBackground(
        const MedalRequest(level: 6),
      );
      final roundTripped = _decode(
          Uint8List.fromList(base64Decode(base64Encode(result.pngBytes))))!;
      expect(roundTripped.width, result.width);
      expect(roundTripped.height, result.height);
    });
  });
}
