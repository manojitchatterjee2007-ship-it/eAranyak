import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

/// Measured geometry of [medalAssetPath], documented in normalised coordinates so
/// the layout stays maintainable if the artwork is re-exported at a new size.
///
/// All values are fractions of the asset width/height. They were measured from
/// the real 1254x1254 RGBA `assets/images/Medal.png` by scanning for the pale
/// placeholder discs (max channel > 200, saturation < 0.25):
///
///   * Large participant-photo disc
///       - least-squares circle fit: centre (624.2, 584.1), radius 217.4
///       - contiguous pale run: x[392..855], y[372..740]
///   * Small level disc
///       - least-squares circle fit: centre (626.8, 882.7), radius 65.6
///       - contiguous pale run: x[561..693], y[818..948]
///
/// The Bengali title, the slogan and the "স্তর" label are baked into the artwork
/// and are never overdrawn. The level disc interior measured 0 dark pixels, so
/// only the level *number* is composited there.
class MedalGeometry {
  const MedalGeometry._();

  static const String medalAssetPath = 'assets/images/Medal.png';
  static const String welcomeBackgroundAssetPath = 'assets/images/welcome_bg.png';

  /// Centre of the participant photograph disc, as a fraction of asset size.
  static const double photoCenterX = 0.4976;
  static const double photoCenterY = 0.4657;

  /// Radius of the participant photograph disc. Slightly inset from the measured
  /// 217.4px fit so the photo never bleeds over the ornate gold ring.
  static const double photoRadius = 0.1660;

  /// Centre of the level-number disc.
  static const double levelCenterX = 0.4998;
  static const double levelCenterY = 0.7039;

  /// Radius of the level-number disc.
  static const double levelRadius = 0.0480;

  /// Reference size the normalised coordinates were measured at.
  static const int referenceWidth = 1254;
  static const int referenceHeight = 1254;
}

/// The inputs required to render a personalised medal.
///
/// [photoBytes] is optional: a participant without a photograph still receives a
/// legitimate medal showing the level panel.
class MedalRequest {
  /// The genuinely completed level, supplied by the server's eligibility result.
  final int level;

  /// Optional participant photograph (any format `package:image` can decode).
  final Uint8List? photoBytes;

  /// Pan the participant chose while previewing, in source-image fractions.
  /// 0.5/0.5 centres the photograph.
  final double focusX;
  final double focusY;

  /// 1.0 fills the disc; lower values zoom out and letterbox the photo.
  final double zoom;

  const MedalRequest({
    required this.level,
    this.photoBytes,
    this.focusX = 0.5,
    this.focusY = 0.5,
    this.zoom = 1.0,
  });

  MedalRequest copyWith({
    int? level,
    Uint8List? photoBytes,
    bool clearPhoto = false,
    double? focusX,
    double? focusY,
    double? zoom,
  }) {
    return MedalRequest(
      level: level ?? this.level,
      photoBytes: clearPhoto ? null : (photoBytes ?? this.photoBytes),
      focusX: focusX ?? this.focusX,
      focusY: focusY ?? this.focusY,
      zoom: zoom ?? this.zoom,
    );
  }
}

/// Result of a medal render. [pngBytes] is a real, self-contained PNG.
class MedalRenderResult {
  final Uint8List pngBytes;
  final int width;
  final int height;

  /// True when a participant photograph was composited.
  final bool hasPhoto;

  const MedalRenderResult({
    required this.pngBytes,
    required this.width,
    required this.height,
    required this.hasPhoto,
  });
}

/// Composes personalised Kishor Aranyak medals from the supplied artwork.
///
/// All heavy pixel work runs in a background isolate via [compute]; the original
/// `assets/images/Medal.png` and `assets/images/welcome_bg.png` are only ever
/// read, never written.
class MedalComposerService {
  const MedalComposerService._();

  static final Map<String, Uint8List> _assetCache = <String, Uint8List>{};

  /// Reads and memoises a bundled asset so repeated renders do not re-parse a
  /// 2.4 MB PNG.
  static Future<Uint8List> _loadAsset(String path) async {
    final cached = _assetCache[path];
    if (cached != null) return cached;
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    _assetCache[path] = bytes;
    return bytes;
  }

  /// Renders the standalone medal with a fully transparent exterior.
  ///
  /// The medal keeps its original proportions and alpha channel: only the two
  /// placeholder discs are filled.
  static Future<MedalRenderResult> renderMedal(MedalRequest request) async {
    final medalBytes = await _loadAsset(MedalGeometry.medalAssetPath);
    return compute(
      _renderMedalIsolate,
      _MedalRenderArgs(medalBytes: medalBytes, request: request),
    );
  }

  /// Renders the medal over the welcome background and returns a shareable PNG.
  ///
  /// The background asset is treated as immutable: it is decoded, scaled and used
  /// as the bottom layer of a new in-memory image.
  ///
  /// Output is 853x1066 (4:5 portrait), which fits inside the source background's
  /// 853x1844 without cropping the ribbon, border or slogan.
  static Future<MedalRenderResult> renderMedalOnWelcomeBackground(
    MedalRequest request,
  ) async {
    final results = await Future.wait([
      _loadAsset(MedalGeometry.medalAssetPath),
      _loadAsset(MedalGeometry.welcomeBackgroundAssetPath),
    ]);
    return compute(
      _renderOnBackgroundIsolate,
      _MedalRenderArgs(
        medalBytes: results[0],
        request: request,
        backgroundBytes: results[1],
      ),
    );
  }
}

class _MedalRenderArgs {
  final Uint8List medalBytes;
  final Uint8List? backgroundBytes;
  final MedalRequest request;

  const _MedalRenderArgs({
    required this.medalBytes,
    required this.request,
    this.backgroundBytes,
  });
}

/// Reads [source] into a square of [destSize], biased by [focusX]/[focusY] so the
/// chosen part of the photograph stays visible.
///
/// The crop is always square so a face is never stretched.
img.Image _coverCrop(
  img.Image source,
  int destSize, {
  required double focusX,
  required double focusY,
  required double zoom,
}) {
  final srcW = source.width;
  final srcH = source.height;
  final minSide = srcW < srcH ? srcW : srcH;

  // zoom 1.0 == fill the disc, lower == zoom out.
  final clampedZoom = zoom.clamp(0.35, 1.0);
  var side = (minSide * clampedZoom).round();
  if (side < 1) side = 1;
  if (side > minSide) side = minSide;

  final maxX = srcW - side;
  final maxY = srcH - side;
  final cropX = maxX <= 0 ? 0 : (maxX * focusX.clamp(0.0, 1.0)).round();
  final cropY = maxY <= 0 ? 0 : (maxY * focusY.clamp(0.0, 1.0)).round();

  final cropped = img.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: side,
    height: side,
  );
  return img.copyResize(
    cropped,
    width: destSize,
    height: destSize,
    interpolation: img.Interpolation.average,
  );
}

/// Draws [photo] into [target] clipped to the circle described by [cx], [cy], [r].
///
/// Only pixels inside the disc are touched, so the Bengali title, slogan, level
/// label, animal illustrations and gold border are provably never overdrawn.
void _stampCircularPhoto(
  img.Image target,
  img.Image photo,
  double cx,
  double cy,
  double r,
) {
  final radiusSq = r * r;
  final originX = cx - r;
  final originY = cy - r;
  final feather = 1.5;

  for (var y = 0; y < target.height; y++) {
    for (var x = 0; x < target.width; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final distSq = dx * dx + dy * dy;
      if (distSq > radiusSq) continue;

      // Nearest-neighbour mapping into the prepared square, bounds-guarded so
      // rounding at the disc edge can never read out of range.
      final px = (x - originX).round().clamp(0, photo.width - 1);
      final py = (y - originY).round().clamp(0, photo.height - 1);
      final src = photo.getPixel(px, py);

      // Soft 1.5px feather so the photo edge does not alias against the gold ring.
      final dist = distSq <= 0 ? 0.0 : _sqrt(distSq);
      final edge = r - dist;
      // Normalised 0..1 coverage: 1 everywhere except the outer 1.5px ring.
      double coverage = 1.0;
      if (edge < feather) {
        coverage = edge / feather;
        if (coverage < 0) coverage = 0;
      }
      final srcAlpha = (src.a.toDouble() / 255.0) * coverage;
      if (srcAlpha <= 0) continue;

      final dst = target.getPixel(x, y);
      final dstAlpha = dst.a.toDouble() / 255.0;
      // Normalised Porter-Duff "over".
      final outAlpha = srcAlpha + dstAlpha * (1 - srcAlpha);
      if (outAlpha <= 0) {
        target.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
        continue;
      }

      int blend(double s, double d) =>
          ((s * srcAlpha + d * dstAlpha * (1 - srcAlpha)) / outAlpha)
              .round()
              .clamp(0, 255);

      target.setPixel(
        x,
        y,
        img.ColorRgba8(
          blend(src.r.toDouble(), dst.r.toDouble()),
          blend(src.g.toDouble(), dst.g.toDouble()),
          blend(src.b.toDouble(), dst.b.toDouble()),
          // ColorRgba8 takes a 0..255 alpha, so scale back up.
          (outAlpha * 255).round().clamp(0, 255),
        ),
      );
    }
  }
}

/// Renders the level number into the small level disc.
///
/// Bengali text is deliberately never rasterised here: the "স্তর" label is part
/// of the artwork, and the level itself is script-neutral Arabic digits which the
/// bundled `arial48` bitmap font covers.
///
/// The number is drawn onto a transparent scratch layer at native font size and
/// then scaled with [img.copyResize], because `drawString` exposes no scale
/// parameters. Compositing the scaled layer keeps the glyphs crisp and centred.
void _drawLevelNumber(img.Image target, int level) {
  final w = target.width;
  final h = target.height;
  final label = level.clamp(1, 999).toString();

  double advance = 0;
  for (final code in label.codeUnits) {
    advance += img.arial48.characters[code]?.xAdvance ?? 24;
  }
  final nativeW = advance.ceil();
  const nativeH = 48;
  if (nativeW <= 0) return;

  final layer =
      img.Image(width: nativeW + 4, height: nativeH + 4, numChannels: 4);
  img.fill(layer, color: img.ColorRgba8(0, 0, 0, 0));
  img.drawString(
    layer,
    label,
    font: img.arial48,
    x: 2,
    y: 2,
    color: img.ColorRgb8(26, 22, 20),
  );

  // Scale so the digits comfortably fit inside the measured disc.
  final discR = MedalGeometry.levelRadius * w;
  final targetW = (discR * 1.35).round().clamp(8, 400);
  final scale = targetW / layer.width;
  final scaled = img.copyResize(
    layer,
    width: targetW,
    height: (layer.height * scale).round(),
    interpolation: img.Interpolation.average,
  );

  final cx = (MedalGeometry.levelCenterX * w).round();
  final cy = (MedalGeometry.levelCenterY * h).round();
  img.compositeImage(
    target,
    scaled,
    dstX: cx - (scaled.width ~/ 2),
    dstY: cy - (scaled.height ~/ 2),
  );
}

/// Square root via Newton iteration. Kept local so the isolate entry points stay
/// plain functions.
double _sqrt(double v) {
  if (v <= 0) return 0;
  var guess = v <= 1 ? 1.0 : v / 2;
  for (var i = 0; i < 24; i++) {
    guess = (guess + v / guess) / 2;
  }
  return guess;
}

MedalRenderResult _renderMedalIsolate(_MedalRenderArgs args) {
  final decoded = img.decodeImage(args.medalBytes);
  if (decoded == null) {
    throw StateError('Unable to decode the medal artwork asset.');
  }

  // Guarantee an explicit alpha channel so the transparent exterior stays
  // transparent instead of being flattened to black.
  final base = decoded.numChannels == 4
      ? img.Image.from(decoded)
      : decoded.convert(numChannels: 4);

  final w = base.width;
  final h = base.height;

  final photoBytes = args.request.photoBytes;
  var hasPhoto = false;
  if (photoBytes != null && photoBytes.isNotEmpty) {
    final photo = img.decodeImage(photoBytes);
    if (photo != null) {
      hasPhoto = true;
      final r = MedalGeometry.photoRadius * w;
      final prepared = _coverCrop(
        photo,
        (r * 2).round(),
        focusX: args.request.focusX,
        focusY: args.request.focusY,
        zoom: args.request.zoom,
      );
      _stampCircularPhoto(
        base,
        prepared,
        MedalGeometry.photoCenterX * w,
        MedalGeometry.photoCenterY * h,
        r,
      );
    }
  }

  _drawLevelNumber(base, args.request.level);

  return MedalRenderResult(
    pngBytes: img.encodePng(base),
    width: w,
    height: h,
    hasPhoto: hasPhoto,
  );
}

MedalRenderResult _renderOnBackgroundIsolate(_MedalRenderArgs args) {
  final backgroundBytes = args.backgroundBytes;
  if (backgroundBytes == null) {
    throw StateError('The welcome background asset was not supplied.');
  }
  final background = img.decodeImage(backgroundBytes);
  if (background == null) {
    throw StateError('Unable to decode the welcome background artwork.');
  }

  // 4:5 portrait export that fits inside the 853x1844 source background.
  const outW = 853;
  const outH = 1066;

  final scale = outW / background.width > outH / background.height
      ? outW / background.width
      : outH / background.height;
  final scaledBg = img.copyResize(
    background,
    width: (background.width * scale).round(),
    height: (background.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
  final cropX =
      ((scaledBg.width - outW) / 2).round().clamp(0, scaledBg.width - outW);
  final cropY =
      ((scaledBg.height - outH) / 2).round().clamp(0, scaledBg.height - outH);
  final canvas = img.copyCrop(
    scaledBg,
    x: cropX,
    y: cropY,
    width: outW,
    height: outH,
  );

  // Personalise the medal at its native resolution first, then scale it down so
  // the disc geometry is computed at full fidelity.
  final medalResult = _renderMedalIsolate(args);
  final personalised = img.decodeImage(medalResult.pngBytes);
  if (personalised == null) {
    throw StateError('Unable to decode the personalised medal.');
  }

  // Leave breathing room so the ribbon, gold border and slogan are never clipped.
  const marginFraction = 0.04;
  final maxMedalW = (outW * (1 - marginFraction * 2)).round();
  final maxMedalH = (outH * (1 - marginFraction * 2)).round();
  final medalScale =
      maxMedalW / personalised.width < maxMedalH / personalised.height
          ? maxMedalW / personalised.width
          : maxMedalH / personalised.height;
  final scaledMedal = img.copyResize(
    personalised,
    width: (personalised.width * medalScale).round(),
    height: (personalised.height * medalScale).round(),
    interpolation: img.Interpolation.average,
  );

  final dstX = ((outW - scaledMedal.width) / 2).round();
  final dstY = ((outH - scaledMedal.height) / 2).round();
  final composed = img.compositeImage(canvas, scaledMedal, dstX: dstX, dstY: dstY);

  return MedalRenderResult(
    pngBytes: img.encodePng(composed),
    width: composed.width,
    height: composed.height,
    hasPhoto: medalResult.hasPhoto,
  );
}




