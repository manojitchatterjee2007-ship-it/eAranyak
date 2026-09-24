import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cube_transition_plus/cube_transition_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/config.dart';
import '../services/sound_service.dart';
import '../services/forest_ambience_service.dart';
import '../services/app_notification_service.dart';
import '../models/app_notification.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/rotating_book_card.dart';
import '../widgets/magazine_cover_image.dart';
import 'magazine_reader_screen.dart';
import 'news_detail_screen.dart';
import 'expedition_tab.dart';
import 'notification_detail_screen.dart';
import 'nature_games_screen.dart';
import 'writing_submission_screen.dart';
import 'online_book_store_screen.dart';
import 'free_book_preview_screen.dart';
import 'library_screen.dart';

class NewsEditorialService {
  static String safeHeadline(String text) {
    if (text.isEmpty) return text;
    var cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  static void applyBengaliEditorial(Map<String, dynamic> item, {Map<String, dynamic>? translation}) {
    if (translation != null) {
      if ((translation['headline'] ?? '').toString().isNotEmpty) {
        item['title'] = translation['headline'];
      }
      if ((translation['dek'] ?? '').toString().isNotEmpty) {
        item['snippet'] = translation['dek'];
      }
      if ((translation['body'] ?? '').toString().isNotEmpty) {
        item['content'] = translation['body'];
      }
      return;
    }

    if ((item['bengali_headline'] ?? '').toString().isNotEmpty) {
      item['title'] = item['bengali_headline'];
    }
    if ((item['bengali_dek'] ?? '').toString().isNotEmpty) {
      item['snippet'] = item['bengali_dek'];
    }
    if ((item['bengali_body'] ?? '').toString().isNotEmpty) {
      item['content'] = item['bengali_body'];
    }
  }

  static bool hasUsableBengaliContent(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    final body = (item['content'] ?? '').toString();
    if (title.isEmpty || body.isEmpty) return false;
    final bengaliCharRegex = RegExp(r'[\u0980-\u09FF]');
    return bengaliCharRegex.hasMatch(title) || bengaliCharRegex.hasMatch(body);
  }

  static Future<bool> ensureBengaliEdition(Map<String, dynamic> item, {bool force = false}) async {
    final srcUrl = (item['source_url'] ?? '').toString();
    if (srcUrl.isEmpty) return false;

    if (!force && hasUsableBengaliContent(item)) {
      return false;
    }

    try {
      final res = await supabase.functions.invoke(
        'bengali-news-editor',
        body: {'source_url': srcUrl, 'force': force},
      );
      final data = res.data;
      if (data is Map<String, dynamic> && data['ok'] == true && data['article'] is Map) {
        final article = Map<String, dynamic>.from(data['article'] as Map);
        applyBengaliEditorial(item, translation: article);
        return true;
      }
    } catch (_) {}
    return false;
  }
}

class NewsImageFallbackWidget extends StatelessWidget {
  final String tags;
  final String category;

  const NewsImageFallbackWidget({super.key, required this.tags, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B2E1E),
      child: const Center(
        child: Icon(Icons.nature_people_rounded, color: Color(0xFF00E676), size: 42),
      ),
    );
  }
}

class NewsImageWidget extends StatelessWidget {
  final Map<String, dynamic> item;
  final BoxFit fit;

  const NewsImageWidget({super.key, required this.item, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    final imgUrl = item['image_url']?.toString();
    final tags = item['img_tags']?.toString() ?? '';
    final cat = item['category']?.toString() ?? '';

    if (imgUrl != null && imgUrl.isNotEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF0A120D),
        child: CachedNetworkImage(
          imageUrl: imgUrl,
          fit: fit,
          placeholder: (c, u) => Container(color: const Color(0xFF142419)),
          errorWidget: (c, u, e) => NewsImageFallbackWidget(tags: tags, category: cat),
        ),
      );
    }
    return NewsImageFallbackWidget(tags: tags, category: cat);
  }
}

class WildlifeLiveObservation {
  final String id;
  final String commonName;
  final String scientificName;
  final String location;
  final String observedAt;
  final String source;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? imageType;
  final String? imageSource;
  final String? imageAttribution;
  final String? imageLicense;
  final String? observer;
  final String? count;
  final String? quality;
  final String? attribution;
  final String? observationUrl;
  final String? description;
  final bool sourceLocationVerified;

  const WildlifeLiveObservation({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.location,
    required this.observedAt,
    required this.source,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.imageType,
    this.imageSource,
    this.imageAttribution,
    this.imageLicense,
    this.observer,
    this.count,
    this.quality,
    this.attribution,
    this.observationUrl,
    this.description,
    this.sourceLocationVerified = false,
  });

  static String _upgradeWildlifeImageUrl(String url, {bool large = false}) {
    final target = large ? '/large.' : '/medium.';
    return url
        .replaceFirst('/square.', target)
        .replaceFirst('/small.', target)
        .replaceFirst('/thumb.', target)
        .replaceFirst('/tiny.', target);
  }

  static String _string(dynamic value) =>
      value?.toString().trim() ?? '';

  static String? _nullable(dynamic value) {
    final v = _string(value);
    return v.isEmpty ? null : v;
  }

  static double? _toCoordinate(dynamic value) {
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  WildlifeLiveObservation copyWith({
    double? latitude,
    double? longitude,
    String? location,
    bool? sourceLocationVerified,
    String? imageUrl,
    String? imageSource,
    String? imageAttribution,
  }) {
    return WildlifeLiveObservation(
      id: id,
      commonName: commonName,
      scientificName: scientificName,
      location: location ?? this.location,
      observedAt: observedAt,
      source: source,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrl: imageUrl ?? this.imageUrl,
      imageType: imageType,
      imageSource: imageSource ?? this.imageSource,
      imageAttribution: imageAttribution ?? this.imageAttribution,
      imageLicense: imageLicense,
      observer: observer,
      count: count,
      quality: quality,
      attribution: attribution,
      observationUrl: observationUrl,
      description: description,
      sourceLocationVerified: sourceLocationVerified ?? this.sourceLocationVerified,
    );
  }

  factory WildlifeLiveObservation.fromMap(Map<String, dynamic> raw) {
    final taxon = raw['taxon'] is Map
        ? Map<String, dynamic>.from(raw['taxon'] as Map)
        : <String, dynamic>{};
    final user = raw['user'] is Map
        ? Map<String, dynamic>.from(raw['user'] as Map)
        : <String, dynamic>{};

    final commonName = _string(raw['common_name']).isNotEmpty
        ? _string(raw['common_name'])
        : (_string(raw['comName']).isNotEmpty
            ? _string(raw['comName'])
            : (_string(taxon['preferred_common_name']).isNotEmpty
                ? _string(taxon['preferred_common_name'])
                : _string(taxon['name'])));

    final scientificName = _string(raw['scientific_name']).isNotEmpty
        ? _string(raw['scientific_name'])
        : (_string(raw['sciName']).isNotEmpty
            ? _string(raw['sciName'])
            : _string(taxon['name']));

    return WildlifeLiveObservation(
      id: _string(raw['id']).isNotEmpty
          ? _string(raw['id'])
          : '${_string(raw['source'])}-${_string(raw['speciesCode'])}-${_string(raw['obsDt'])}',
      commonName: commonName.isEmpty ? 'বন্যপ্রাণ পর্যবেক্ষণ' : commonName,
      scientificName: scientificName,
      location: _string(raw['location']).isNotEmpty
          ? _string(raw['location'])
          : (_string(raw['locName']).isNotEmpty
              ? _string(raw['locName'])
              : (_string(raw['place_guess']).isNotEmpty
                  ? _string(raw['place_guess'])
                  : 'অবস্থান প্রকাশ করা হয়নি')),
      observedAt: _string(raw['observed_at']).isNotEmpty
          ? _string(raw['observed_at'])
          : (_string(raw['obsDt']).isNotEmpty
              ? _string(raw['obsDt'])
              : _string(raw['observed_on'])),
      source: _string(raw['source']).isEmpty ? 'বন্যপ্রাণ তথ্যস্রোত' : _string(raw['source']),
      latitude: _toCoordinate(raw['latitude'] ?? raw['lat']),
      longitude: _toCoordinate(raw['longitude'] ?? raw['lng'] ?? raw['lon']),
      imageUrl: _nullable(raw['image_url']) ??
          _nullable(raw['imageUrl']) ??
          _nullable(raw['photo_url']) ??
          _nullable(raw['photoUrl']) ??
          _nullable(raw['thumbnail_url']) ??
          _nullable(raw['default_photo'] is Map
              ? (raw['default_photo'] as Map)['medium_url']
              : null) ??
          _nullable(raw['photos'] is List && (raw['photos'] as List).isNotEmpty
              ? ((raw['photos'].first is Map)
                  ? (raw['photos'].first as Map)['url']
                  : null)
              : null),
      imageType: _nullable(raw['image_type']),
      imageSource: _nullable(raw['image_source']),
      imageAttribution: _nullable(raw['image_attribution']),
      imageLicense: _nullable(raw['image_license']),
      observer: _nullable(raw['observer']) ??
          _nullable(raw['observer_name']) ??
          _nullable(raw['user_login']) ??
          _nullable(user['login']) ??
          _nullable(user['name']),
      count: _nullable(raw['count']) ??
          _nullable(raw['howMany']) ??
          _nullable(raw['individual_count']),
      quality: _nullable(raw['quality']) ?? _nullable(raw['quality_grade']) ??
          _nullable(raw['obsReviewed']),
      attribution: _nullable(raw['attribution']) ??
          _nullable(raw['credit']) ??
          _nullable(raw['photographer']) ??
          _nullable(raw['user_login']) ??
          _nullable(user['login']),
      observationUrl: _nullable(raw['observation_url']) ??
          _nullable(raw['observationUrl']) ??
          _nullable(raw['source_url']) ??
          _nullable(raw['url']),
      description: _nullable(raw['description']) ??
          _nullable(raw['short_description']),
    );
  }
}

class WildlifeLiveFeedService {
  static const String functionName = 'wildlife-live-feed';

  static Future<List<WildlifeLiveObservation>> fetchIndiaFeed({
    int limit = 12,
  }) async {
    final response = await supabase.functions.invoke(
      functionName,
      body: <String, dynamic>{
        'countryCode': 'IN',
        'limit': limit,
        'includeSources': <String>['ebird', 'inaturalist'],
      },
    );

    final raw = response.data;
    final payload = <dynamic>[];

    if (raw is List) {
      payload.addAll(raw);
    } else if (raw is Map) {
      final combined = raw['observations'] ??
          raw['data'] ??
          raw['items'] ??
          raw['tiles'];
      if (combined is List) payload.addAll(combined);

      final ebird = raw['ebird'];
      final inaturalist = raw['inaturalist'] ?? raw['iNaturalist'];

      if (ebird is List) {
        for (final item in ebird) {
          if (item is Map) {
            payload.add(<String, dynamic>{
              ...Map<String, dynamic>.from(item),
              'source': 'eBird',
            });
          }
        }
      }

      if (inaturalist is List) {
        for (final item in inaturalist) {
          if (item is Map) {
            payload.add(<String, dynamic>{
              ...Map<String, dynamic>.from(item),
              'source': 'iNaturalist',
            });
          }
        }
      }
    }

    final all = <WildlifeLiveObservation>[];
    final seen = <String>{};

    for (final item in payload) {
      if (item is! Map) continue;
      final observation = WildlifeLiveObservation.fromMap(
        Map<String, dynamic>.from(item),
      );
      if (observation.commonName.trim().isEmpty) continue;
      if (seen.add(observation.id)) {
        all.add(observation);
      }
    }

    final ebird = all
        .where((o) => o.source.toLowerCase() == 'ebird')
        .toList();
    final inaturalist = all
        .where((o) => o.source.toLowerCase() == 'inaturalist')
        .toList();
    final other = all
        .where((o) =>
            o.source.toLowerCase() != 'ebird' &&
            o.source.toLowerCase() != 'inaturalist')
        .toList();

    final targetEach = limit ~/ 2;
    final selectedEbird = ebird.take(targetEach).toList();
    final selectedInat = inaturalist.take(targetEach).toList();

    final balanced = <WildlifeLiveObservation>[];
    final pairCount = selectedEbird.length > selectedInat.length
        ? selectedEbird.length
        : selectedInat.length;

    for (var index = 0; index < pairCount; index++) {
      if (index < selectedEbird.length) {
        balanced.add(selectedEbird[index]);
      }
      if (index < selectedInat.length) {
        balanced.add(selectedInat[index]);
      }
    }

    if (balanced.length < limit) {
      final usedIds = balanced.map((o) => o.id).toSet();
      final fallback = <WildlifeLiveObservation>[
        ...ebird.skip(selectedEbird.length),
        ...inaturalist.skip(selectedInat.length),
        ...other,
      ];
      for (final observation in fallback) {
        if (balanced.length >= limit) break;
        if (usedIds.add(observation.id)) {
          balanced.add(observation);
        }
      }
    }

    return balanced.take(limit).toList();
  }

  static Future<WildlifeLiveObservation?> verifySourceLocation(
      WildlifeLiveObservation observation) async {
    final sourceUrl = observation.observationUrl?.trim();
    if (sourceUrl == null || sourceUrl.isEmpty) return null;

    if (_validIndiaCoordinate(observation.latitude, observation.longitude)) {
      return observation.copyWith(
        latitude: observation.latitude,
        longitude: observation.longitude,
        sourceLocationVerified: true,
      );
    }

    try {
      final uri = Uri.tryParse(sourceUrl);
      if (uri == null || !uri.hasScheme) return null;

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      client.userAgent = 'E-Aranyak Wildlife Dashboard/1.0';
      try {
        if (uri.host.contains('inaturalist.org')) {
          final match = RegExp(r'/observations/(\d+)').firstMatch(uri.path);
          if (match != null) {
            final apiUri = Uri.parse(
                'https://api.inaturalist.org/v1/observations/${match.group(1)}');
            final request = await client.getUrl(apiUri);
            final response = await request.close();
            final body = await utf8.decoder.bind(response).join();
            if (response.statusCode >= 200 && response.statusCode < 300) {
              final decoded = jsonDecode(body);
              final raw = decoded is Map && decoded['results'] is List &&
                      (decoded['results'] as List).isNotEmpty
                  ? Map<String, dynamic>.from((decoded['results'] as List).first as Map)
                  : decoded is Map
                      ? Map<String, dynamic>.from(decoded)
                      : <String, dynamic>{};
              final directLat = WildlifeLiveObservation._toCoordinate(raw['latitude']);
              final directLon = WildlifeLiveObservation._toCoordinate(raw['longitude']);
              double? lat = directLat;
              double? lon = directLon;

              final locationString = raw['location']?.toString();
              if ((lat == null || lon == null) && locationString != null) {
                final parts = locationString.split(',');
                if (parts.length >= 2) {
                  lat = WildlifeLiveObservation._toCoordinate(parts[0].trim());
                  lon = WildlifeLiveObservation._toCoordinate(parts[1].trim());
                }
              }

              if ((lat == null || lon == null) && raw['geojson'] is Map) {
                final geo = Map<String, dynamic>.from(raw['geojson'] as Map);
                final coordinates = geo['coordinates'];
                if (coordinates is List && coordinates.length >= 2) {
                  lon = WildlifeLiveObservation._toCoordinate(coordinates[0]);
                  lat = WildlifeLiveObservation._toCoordinate(coordinates[1]);
                }
              }

              final place = WildlifeLiveObservation._nullable(raw['place_guess']);
              if (_validIndiaCoordinate(lat, lon)) {
                return observation.copyWith(
                  latitude: lat,
                  longitude: lon,
                  location: place ?? observation.location,
                  sourceLocationVerified: true,
                );
              }
              return null;
            }
          }
        }

        final request = await client.getUrl(uri);
        final response = await request.close();
        final html = await utf8.decoder.bind(response).join();
        if (response.statusCode < 200 || response.statusCode >= 400) return null;

        final coords = _extractCoordinates(html);
        if (coords == null || !_validIndiaCoordinate(coords.$1, coords.$2)) {
          return null;
        }

        final pageLocation = _extractLocationName(html);
        return observation.copyWith(
          latitude: coords.$1,
          longitude: coords.$2,
          location: pageLocation ?? observation.location,
          sourceLocationVerified: true,
        );
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  static bool _validIndiaCoordinate(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    return lat >= 6.0 && lat <= 37.5 && lon >= 68.0 && lon <= 97.8;
  }

  static (double, double)? _extractCoordinates(String html) {
    final latLonPatterns = <RegExp>[
      RegExp(r'\"latitude\"\s*:\s*(-?\d+(?:\.\d+)?)\s*,\s*\"longitude\"\s*:\s*(-?\d+(?:\.\d+)?)', caseSensitive: false),
      RegExp(r'\"lat\"\s*:\s*(-?\d+(?:\.\d+)?)\s*,\s*\"(?:lng|lon|longitude)\"\s*:\s*(-?\d+(?:\.\d+)?)', caseSensitive: false),
    ];
    for (final pattern in latLonPatterns) {
      final match = pattern.firstMatch(html);
      if (match == null) continue;
      final lat = double.tryParse(match.group(1)!);
      final lon = double.tryParse(match.group(2)!);
      if (lat != null && lon != null &&
          lat.abs() <= 90 && lon.abs() <= 180) {
        return (lat, lon);
      }
    }

    final queryLat = RegExp(
      r'[?&]lat(?:itude)?=(-?\d+(?:\.\d+)?)[&;][^#\s]*?(?:lng|lon|longitude)=(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(html);
    if (queryLat != null) {
      final lat = double.tryParse(queryLat.group(1)!);
      final lon = double.tryParse(queryLat.group(2)!);
      if (lat != null && lon != null &&
          lat.abs() <= 90 && lon.abs() <= 180) {
        return (lat, lon);
      }
    }

    final queryLon = RegExp(
      r'[?&](?:lng|lon|longitude)=(-?\d+(?:\.\d+)?)[&;][^#\s]*?lat(?:itude)?=(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(html);
    if (queryLon != null) {
      final lon = double.tryParse(queryLon.group(1)!);
      final lat = double.tryParse(queryLon.group(2)!);
      if (lat != null && lon != null &&
          lat.abs() <= 90 && lon.abs() <= 180) {
        return (lat, lon);
      }
    }

    return null;
  }

  static String? _extractLocationName(String html) {
    final patterns = <RegExp>[
      RegExp(r"""<meta[^>]+property=["']og:locality["'][^>]+content=["']([^"']+)""", caseSensitive: false),
      RegExp(r'"place_guess"\s*:\s*"([^"]+)"', caseSensitive: false),
      RegExp(r'"locName"\s*:\s*"([^"]+)"', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim();
      }
    }
    return null;
  }
}

class WindowsLiveTile extends StatefulWidget {
  final WildlifeLiveObservation observation;
  final Duration flipInterval;
  final Duration initialDelay;
  final VoidCallback? onTap;
  final bool flipSideways;
  final bool reverseDirection;

  const WindowsLiveTile({
    super.key,
    required this.observation,
    this.flipInterval = const Duration(seconds: 6),
    this.initialDelay = Duration.zero,
    this.onTap,
    this.flipSideways = true,
    this.reverseDirection = false,
  });

  @override
  State<WindowsLiveTile> createState() => _WindowsLiveTileState();
}

class _WindowsLiveTileState extends State<WindowsLiveTile> {
  late final PageController _pageController;
  Timer? _flipTimer;
  Timer? _initialTimer;
  bool _showBack = false;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _scheduleFlip();
  }

  void _scheduleFlip() {
    _flipTimer?.cancel();
    _initialTimer?.cancel();

    _initialTimer = Timer(widget.initialDelay, () {
      if (!mounted) return;
      _flipTimer = Timer.periodic(widget.flipInterval, (_) {
        _flipOnce();
      });
    });
  }

  Future<void> _flipOnce() async {
    if (!mounted || !_pageController.hasClients || _isAnimating) return;

    final targetPage = _showBack ? 0 : 1;
    _isAnimating = true;

    try {
      await _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 1050),
        curve: Curves.easeInOutCubic,
      );
    } finally {
      if (mounted) {
        setState(() => _showBack = targetPage == 1);
      }
      _isAnimating = false;
    }
  }

  @override
  void didUpdateWidget(covariant WindowsLiveTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observation.id != widget.observation.id ||
        oldWidget.flipInterval != widget.flipInterval ||
        oldWidget.initialDelay != widget.initialDelay ||
        oldWidget.flipSideways != widget.flipSideways ||
        oldWidget.reverseDirection != widget.reverseDirection) {
      _scheduleFlip();
    }
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    _initialTimer?.cancel();
    super.dispose();
  }

  String _tileImageUrl(String url) {
    return url
        .replaceFirst('/square.', '/medium.')
        .replaceFirst('/small.', '/medium.')
        .replaceFirst('/thumb.', '/medium.')
        .replaceFirst('/tiny.', '/medium.');
  }

  Widget _imageFace() {
    final rawUrl = widget.observation.imageUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      return const ColoredBox(color: Color(0xFF102416));
    }

    final mediumUrl = _tileImageUrl(rawUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: CachedNetworkImage(
        imageUrl: mediumUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        memCacheWidth: 600,
        placeholder: (_, __) => const ColoredBox(
          color: Color(0xFF102416),
          child: Center(
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF69F0AE),
              ),
            ),
          ),
        ),
        errorWidget: (_, __, ___) {
          if (mediumUrl == rawUrl) {
            return const ColoredBox(color: Color(0xFF102416));
          }
          return CachedNetworkImage(
            imageUrl: rawUrl,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            memCacheWidth: 600,
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF102416)),
          );
        },
      ),
    );
  }

  Widget _imageFaceDecorated() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF102416),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF43A047), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _imageFace(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: .72),
                ],
              ),
            ),
          ),
          Positioned(
            top: 5,
            left: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xCCB71C1C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'সরাসরি',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 70),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xCC07130B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF69F0AE), width: .6),
              ),
              child: Text(
                widget.observation.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF69F0AE),
                  fontSize: 6.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 5,
            child: Text(
              widget.observation.commonName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 10, color: Colors.white54),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 7.5, color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _textFace() {
    final o = widget.observation;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF102416),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF43A047), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.sensors_rounded,
                    size: 12,
                    color: Color(0xFF69F0AE),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      o.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 7.5,
                        color: Color(0xFF69F0AE),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                o.commonName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              if (o.scientificName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  o.scientificName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 7,
                    color: Color(0xFFB9D8BE),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              _detailLine(Icons.place_outlined, o.location),
              const SizedBox(height: 2),
              _detailLine(Icons.schedule_rounded, o.observedAt),
              if (o.count != null) ...[
                const SizedBox(height: 2),
                _detailLine(Icons.groups_rounded, 'সংখ্যা: ${o.count}'),
              ],
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final axis = widget.flipSideways ? Axis.horizontal : Axis.vertical;

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CubePageView(
          controller: _pageController,
          scrollDirection: axis,
          transformStyle: CubeTransformStyle.outside,
          children: [
            KeyedSubtree(
              key: const ValueKey('wildlife-text-face'),
              child: _textFace(),
            ),
            KeyedSubtree(
              key: const ValueKey('wildlife-image-face'),
              child: _imageFaceDecorated(),
            ),
          ],
        ),
      ),
    );
  }
}

class IndiaObservationMap extends StatefulWidget {
  final double latitude;
  final double longitude;

  const IndiaObservationMap({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<IndiaObservationMap> createState() => _IndiaObservationMapState();
}

class _IndiaObservationMapState extends State<IndiaObservationMap> with SingleTickerProviderStateMixin {
  static const String _asset = 'assets/images/india_topo_map.png';
  Rect? _visibleMapRect;
  Size? _assetSize;
  bool _loadingCalibration = true;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    
    _loadMapCalibration();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadMapCalibration() async {
    try {
      final bytes = await rootBundle.load(_asset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) {
        image.dispose();
        codec.dispose();
        if (mounted) setState(() => _loadingCalibration = false);
        return;
      }

      final data = byteData.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      var minX = width;
      var minY = height;
      var maxX = -1;
      var maxY = -1;

      for (var y = 0; y < height; y++) {
        final row = y * width * 4;
        for (var x = 0; x < width; x++) {
          final alpha = data[row + x * 4 + 3];
          if (alpha >= 24) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      final rect = maxX >= minX && maxY >= minY
          ? Rect.fromLTRB(
              minX.toDouble(),
              minY.toDouble(),
              maxX.toDouble(),
              maxY.toDouble(),
            )
          : null;

      image.dispose();
      codec.dispose();

      if (!mounted) return;
      setState(() {
        _assetSize = Size(width.toDouble(), height.toDouble());
        _visibleMapRect = rect;
        _loadingCalibration = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCalibration = false);
    }
  }

  bool get _validCoordinate {
    final lat = widget.latitude;
    final lon = widget.longitude;
    return lat.isFinite &&
        lon.isFinite &&
        lat >= 6.0 &&
        lat <= 37.5 &&
        lon >= 68.0 &&
        lon <= 97.8;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF07130B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final assetAspect = _assetSize == null || _assetSize!.height == 0
                    ? 900.0 / 534.0
                    : _assetSize!.width / _assetSize!.height;

                final displayedWidth = math.min(
                  maxWidth,
                  constraints.maxHeight * assetAspect,
                );
                final displayedHeight = displayedWidth / assetAspect;
                final left = (constraints.maxWidth - displayedWidth) / 2;
                final top = (constraints.maxHeight - displayedHeight) / 2;

                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: top,
                      width: displayedWidth,
                      height: displayedHeight,
                      child: Image.asset(
                        _asset,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    if (_validCoordinate &&
                        _visibleMapRect != null &&
                        _assetSize != null)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _IndiaObservationMarkerPainter(
                                latitude: widget.latitude,
                                longitude: widget.longitude,
                                assetSize: _assetSize!,
                                visibleMapRect: _visibleMapRect!,
                                imageLeft: left,
                                imageTop: top,
                                imageWidth: displayedWidth,
                                imageHeight: displayedHeight,
                                pulseValue: _pulseAnimation.value,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 9,
            left: 11,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCC07130B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'ভারত — পর্যবেক্ষণের অবস্থান',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          if (!_validCoordinate || (!_loadingCalibration && _visibleMapRect == null))
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xDD07130B),
                  borderRadius: BorderRadius.all(Radius.circular(7)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'মানচিত্রে দেখানোর মতো অবস্থান পাওয়া যায়নি',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IndiaObservationMarkerPainter extends CustomPainter {
  final double latitude;
  final double longitude;
  final Size assetSize;
  final Rect visibleMapRect;
  final double imageLeft;
  final double imageTop;
  final double imageWidth;
  final double imageHeight;
  final double pulseValue;

  const _IndiaObservationMarkerPainter({
    required this.latitude,
    required this.longitude,
    required this.assetSize,
    required this.visibleMapRect,
    required this.imageLeft,
    required this.imageTop,
    required this.imageWidth,
    required this.imageHeight,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const minLon = 68.05;
    const maxLon = 97.42;
    const minLat = 6.75;
    const maxLat = 37.10;

    final lon = longitude.clamp(minLon, maxLon).toDouble();
    final lat = latitude.clamp(minLat, maxLat).toDouble();

    final nx = (lon - minLon) / (maxLon - minLon);
    final ny = (maxLat - lat) / (maxLat - minLat);

    final assetX = visibleMapRect.left + nx * visibleMapRect.width;
    final assetY = visibleMapRect.top + ny * visibleMapRect.height;

    final scaleX = imageWidth / assetSize.width;
    final scaleY = imageHeight / assetSize.height;
    final point = Offset(
      imageLeft + assetX * scaleX,
      imageTop + assetY * scaleY,
    );

    final glowRadius = 4.0 + (10.0 * pulseValue);
    final glowAlpha = (0.8 - (0.6 * pulseValue)).clamp(0.0, 1.0);
    
    final glow = Paint()..color = const Color(0xFF00E676).withValues(alpha: glowAlpha);
    final fill = Paint()..color = const Color(0xFFFF1744); 
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(point, glowRadius, glow);
    canvas.drawCircle(point, 2.5, fill);  
    canvas.drawCircle(point, 3.5, ring);  
  }

  @override
  bool shouldRepaint(covariant _IndiaObservationMarkerPainter oldDelegate) {
    return oldDelegate.latitude != latitude ||
        oldDelegate.longitude != longitude ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.visibleMapRect != visibleMapRect ||
        oldDelegate.imageLeft != imageLeft ||
        oldDelegate.imageTop != imageTop ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

// -------------------------------------------------------------
// NEW: Stateful Bottom Sheet to handle Audio Player State
// -------------------------------------------------------------
class _WildlifeDetailSheet extends StatefulWidget {
  final WildlifeLiveObservation observation;

  const _WildlifeDetailSheet({required this.observation});

  @override
  State<_WildlifeDetailSheet> createState() => _WildlifeDetailSheetState();
}

class _WildlifeDetailSheetState extends State<_WildlifeDetailSheet> {
  late final AudioPlayer _audioPlayer;
  late final bool _ambienceWasPlaying;
  bool _isAudioLoading = false;
  bool _isPlaying = false;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    _ambienceWasPlaying = ForestAmbienceService.isPlaying;
    unawaited(ForestAmbienceService.stopAmbience());
    _audioPlayer = AudioPlayer();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    if (_ambienceWasPlaying) {
      unawaited(ForestAmbienceService.startAmbience());
    }
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (_isAudioLoading) return;

    if (_isPlaying) {
      try {
        await _audioPlayer.pause();
        if (mounted) setState(() => _isPlaying = false);
      } catch (_) {}
      return;
    }

    if (_audioPlayer.source != null && _audioError == null) {
      try {
        await ForestAmbienceService.stopAmbience();
        final source = _audioPlayer.source!;
        await _audioPlayer.stop();
        await _audioPlayer.play(source, volume: 1.0);
        if (mounted) setState(() => _isPlaying = true);
        return;
      } catch (_) {
        try {
          await _audioPlayer.stop();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() {
      _isAudioLoading = true;
      _audioError = null;
    });

    try {
      await ForestAmbienceService.stopAmbience();
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);

      final scientific = widget.observation.scientificName.trim();
      final commonName = widget.observation.commonName.trim();
      final parts = scientific.split(RegExp(r'\s+')).where((x) => x.trim().isNotEmpty).toList();

      if (parts.length < 2) {
        throw Exception('A valid binomial scientific name is required');
      }

      // Bird calls are resolved server-side. The Flutter app never receives
      // the Xeno-canto API key and never tries to stream a protected media URL
      // directly from Windows/Android.
      final response = await supabase.functions
          .invoke(
            'wildlife-bird-call',
            body: <String, dynamic>{
              'scientific_name': '${parts[0]} ${parts[1]}',
              'common_name': commonName,
            },
          )
          .timeout(const Duration(seconds: 40));

      final data = response.data;
      if (data is Uint8List) {
        if (data.length < 1024) {
          throw Exception('The bird-call service returned no valid audio');
        }
        await _audioPlayer.play(BytesSource(data), volume: 1.0);
      } else if (data is String && data.trim().startsWith('http')) {
        await _audioPlayer.play(UrlSource(data.trim()), volume: 1.0);
      } else if (data is Map && (data['audio_url'] ?? data['url']) != null) {
        final url = (data['audio_url'] ?? data['url']).toString().trim();
        if (!url.startsWith('http')) throw Exception('The bird-call service returned an invalid audio URL');
        await _audioPlayer.play(UrlSource(url), volume: 1.0);
      } else {
        String details = '';
        if (data is Map) {
          details = (data['error'] ?? data['message'] ?? '').toString().trim();
        } else if (data != null) {
          details = data.toString().trim();
        }
        throw Exception(details.isEmpty ? 'The bird-call service returned no valid audio' : details);
      }
      if (mounted) setState(() => _isPlaying = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _audioError = _friendlyBirdCallError(e);
        });
      }
      debugPrint('Bird call playback failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isAudioLoading = false;
        });
      }
    }
  }

  String _friendlyBirdCallError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('no exact-species recording') ||
        text.contains('no playable exact-species recording') ||
        text.contains('no playable exact-species') ||
        text.contains('404')) {
      return 'এই প্রজাতির জন্য এখন কোনও নির্ভরযোগ্য পাখির ডাক পাওয়া যাচ্ছে না।';
    }

    if (text.contains('xeno_canto_api_key') ||
        text.contains('missing_xeno_api_key')) {
      return 'পাখির ডাক সার্ভিসের API configuration সম্পূর্ণ হয়নি।';
    }

    if (text.contains('timeout') ||
        text.contains('502') ||
        text.contains('503') ||
        text.contains('504') ||
        text.contains('provider unavailable')) {
      return 'পাখির ডাকের সার্ভিসটি এই মুহূর্তে unavailable। একটু পরে আবার চেষ্টা করুন।';
    }

    return 'পাখির ডাকটি এখন বাজানো যাচ্ছে না। আবার চেষ্টা করুন।';
  }

  String _bengaliQuality(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'needs_id') return 'পরিচয় নির্ধারণাধীন';
    if (v == 'research') return 'গবেষণামূলক রেকর্ড';
    if (v == 'reviewed') return 'পর্যালোচিত';
    if (v == 'unreviewed') return 'পর্যালোচনাধীন';
    return value;
  }

  Widget _liveDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF81C784)),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.observation;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            if (o.imageUrl != null && o.imageUrl!.isNotEmpty)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  color: const Color(0xFF07130B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: CachedNetworkImage(
                    imageUrl: WildlifeLiveObservation._upgradeWildlifeImageUrl(o.imageUrl!, large: true),
                    fit: BoxFit.contain, 
                    errorWidget: (_, __, ___) => const Center(child: Icon(Icons.image_not_supported_rounded, color: Color(0xFF69F0AE))),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.sensors_rounded, color: Color(0xFF69F0AE), size: 18),
                const SizedBox(width: 6),
                Text(o.source, style: const TextStyle(color: Color(0xFF69F0AE), fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(o.commonName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            if (o.scientificName.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(o.scientificName, style: const TextStyle(color: Colors.white60, fontStyle: FontStyle.italic)),
            ],

            // AUDIO PLAYER BUTTON (Only for eBird tiles)
            if (o.source.toLowerCase() == 'ebird') ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF102416),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E7D32)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _toggleAudio,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                            child: _isAudioLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('পাখির ডাক শুনুন (Bird Call)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                if (_audioError != null)
                                  Text(_audioError!, style: const TextStyle(color: Colors.redAccent, fontSize: 10))
                                else
                                  const Text('powered by Xeno-canto', style: TextStyle(color: Color(0xFF69F0AE), fontSize: 9)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF102416),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E7D32)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public_rounded, size: 16, color: Color(0xFF69F0AE)),
                  const SizedBox(width: 7),
                  const Text(
                    'তথ্যসূত্র: ',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Expanded(
                    child: Text(
                      o.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF69F0AE),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (o.latitude != null && o.longitude != null) ...[
              const Text(
                'পর্যবেক্ষণের অবস্থান',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 7),
              IndiaObservationMap(
                latitude: o.latitude!,
                longitude: o.longitude!,
              ),
              const SizedBox(height: 14),
            ],
            _liveDetailRow(Icons.place_rounded, 'পর্যবেক্ষণের স্থান', o.location),
            _liveDetailRow(Icons.schedule_rounded, 'পর্যবেক্ষণের সময়', o.observedAt),
            if (o.count != null) _liveDetailRow(Icons.groups_rounded, 'সংখ্যা', o.count!),
            if (o.observer != null) _liveDetailRow(Icons.person_outline_rounded, 'পর্যবেক্ষক', o.observer!),
            if (o.quality != null) _liveDetailRow(Icons.verified_outlined, 'পর্যবেক্ষণের অবস্থা', _bengaliQuality(o.quality!)),
            if (o.attribution != null) _liveDetailRow(Icons.copyright_rounded, 'স্বীকৃতি', o.attribution!),
            if (o.description != null) ...[
              const SizedBox(height: 8),
              Text(o.description!, style: const TextStyle(color: Colors.white70, height: 1.5)),
            ],
            if (o.observationUrl != null && o.observationUrl!.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(o.observationUrl!);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('মূল পর্যবেক্ষণটি দেখুন'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF69F0AE),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String userEmail;
  final Function(int) onNavigateToTab;
  final String fullName;

  const HomeScreen({
    super.key,
    required this.userEmail,
    required this.onNavigateToTab,
    required this.fullName,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _issues = [];
  Timer? _autoShuffleTimer;

  String? _lastReadMagId;
  String? _lastReadTitle;
  int _lastReadPage = 0;
  int _lastReadTotalPages = 0;

  bool _travelExpanded = false;
  bool _travelContentVisible = false;

  final AppNotificationService _appNotificationService = AppNotificationService();

  List<Map<String, dynamic>> _visibleNews = [];
  late final PageController _newsPageController;
  int _currentNewsPage = 0;

  List<WildlifeLiveObservation> _liveWildlife = [];
  Timer? _liveWildlifeRefreshTimer;
  bool _loadingLiveWildlife = false;
  String? _liveWildlifeError;
  List<AppNotification> _latestNotifications = [];
  bool _loadingNotifications = false;

  @override
  void initState() {
    super.initState();
    _newsPageController = PageController(viewportFraction: 0.85);
    _refreshVisibleNewsWindow();
    loadData();
    _loadContinueReadingSession();
    _startAutoNewsShufflingTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLiveNews();
      _fetchLiveWildlife();
      _startLiveWildlifeRefreshTimer();
    });
  }

  @override
  void dispose() {
    _autoShuffleTimer?.cancel();
    _liveWildlifeRefreshTimer?.cancel();
    _newsPageController.dispose();
    super.dispose();
  }

  void _refreshVisibleNewsWindow() {
    if (!mounted) return;
    setState(() {
      final shuffled = List<Map<String, dynamic>>.from(_visibleNews)..shuffle();
      _visibleNews = shuffled.take(5).toList();
    });
  }

  Future<void> _fetchLiveWildlife() async {
    if (_loadingLiveWildlife) return;
    if (mounted) {
      setState(() {
        _loadingLiveWildlife = true;
        _liveWildlifeError = null;
      });
    }
    try {
      final candidates = await WildlifeLiveFeedService.fetchIndiaFeed(limit: 80);

      final verified = <WildlifeLiveObservation>[];
      const batchSize = 16;
      
      for (var start = 0; start < candidates.length && verified.length < 12; start += batchSize) {
        final end = math.min(start + batchSize, candidates.length);
        final batch = candidates.sublist(start, end);
        
        final resolved = await Future.wait(
          batch.map(WildlifeLiveFeedService.verifySourceLocation),
        );
        
        for (final observation in resolved) {
          if (observation != null && observation.sourceLocationVerified) {
            var finalObs = observation;
            
            if (finalObs.imageUrl == null || finalObs.imageUrl!.trim().isEmpty) {
              final speciesName = finalObs.scientificName.isNotEmpty 
                  ? finalObs.scientificName 
                  : finalObs.commonName;
                  
              final media = await WildlifeMediaService.fetchSpeciesPhoto(speciesName);
              
              if (media != null && media.imageUrl != null) {
                finalObs = finalObs.copyWith(
                  imageUrl: media.imageUrl,
                  imageSource: 'Representative Image',
                  imageAttribution: media.attribution,
                );
              }
            }

            if (finalObs.imageUrl != null && finalObs.imageUrl!.isNotEmpty) {
              verified.add(finalObs);
              if (verified.length >= 12) break;
            }
          }
        }
      }
      
      if (!mounted) return;
      setState(() {
        _liveWildlife = verified;
        _loadingLiveWildlife = false;
        _liveWildlifeError = verified.isEmpty
            ? 'এই মুহূর্তে কোনও সাম্প্রতিক পর্যবেক্ষণ পাওয়া যায়নি।'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLiveWildlife = false;
        _liveWildlifeError = 'সরাসরি বন্যপ্রাণ তথ্যস্রোত এই মুহূর্তে সাময়িকভাবে অনুপলব্ধ।';
      });
    }
  }

  void _startLiveWildlifeRefreshTimer() {
    _liveWildlifeRefreshTimer?.cancel();
    _liveWildlifeRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _fetchLiveWildlife(),
    );
  }

  Future<void> _fetchLiveNews() async {
    try {
      final res = await supabase
          .from('wildlife_news')
          .select()
          .eq('is_published', true)
          .order('editorial_priority', ascending: false)
          .order('published_at', ascending: false)
          .limit(10);

      if (mounted) {
        final rawItems = List<Map<String, dynamic>>.from(res);
        final validItems = <Map<String, dynamic>>[];
        for (var item in rawItems) {
          NewsEditorialService.applyBengaliEditorial(item);
          final imageUrl = item['image_url']?.toString();
          final hasValidImage = imageUrl != null && imageUrl.trim().isNotEmpty;
          final title = item['bengali_headline']?.toString() ?? item['title']?.toString() ?? '';
          final content = item['bengali_body']?.toString() ?? item['snippet']?.toString() ?? '';
          final hasBengali = title.trim().isNotEmpty && content.trim().isNotEmpty;
          if (hasValidImage && hasBengali) {
            validItems.add(item);
          }
        }
        if (mounted) {
          setState(() {
            _visibleNews = List<Map<String, dynamic>>.from(validItems)..shuffle();
            _visibleNews = _visibleNews.take(5).toList();
          });
        }
      }
    } catch (_) {}
  }

  void _startAutoNewsShufflingTimer() {
    _autoShuffleTimer?.cancel();
    _autoShuffleTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (!mounted) return;
      _refreshVisibleNewsWindow();
    });
  }

  Future<void> loadData() async {
    await Future.wait([
      _loadMagazines(),
      _loadContinueReadingSession(),
      _fetchLiveNews(),
      _loadLatestNotifications(),
    ]);
  }

  Future<void> _loadMagazines() async {
    try {
      final res = await supabase
          .from('magazines')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _issues = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadContinueReadingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('last_read_mag_id');
      final title = prefs.getString('last_read_title');
      final page = prefs.getInt('last_read_page') ?? 0;
      final total = prefs.getInt('last_read_total_pages') ?? 0;

      if (id != null && mounted) {
        setState(() {
          _lastReadMagId = id;
          _lastReadTitle = title;
          _lastReadPage = page;
          _lastReadTotalPages = total;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadLatestNotifications() async {
    if (_loadingNotifications) return;
    setState(() => _loadingNotifications = true);
    try {
      final list = await _appNotificationService.fetchAllNotifications(filter: 'published');
      if (mounted) {
        setState(() {
          _latestNotifications = list;
          _loadingNotifications = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNotifications = false);
    }
  }

  void _toggleTravelExpanded() {
    SoundService.playButtonSound();
    setState(() {
      if (_travelExpanded) {
        _travelExpanded = false;
        _travelContentVisible = false;
      } else {
        _travelExpanded = true;
        _travelContentVisible = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _travelExpanded) {
            setState(() => _travelContentVisible = true);
          }
        });
      }
    });
  }

  Widget _buildTravelSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpeditionTab(
            onActivated: _toggleTravelExpanded,
            expanded: _travelExpanded,
          ),
          ClipRect(
            child: AnimatedSize(
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeInOutCubic,
              child: _travelExpanded
                  ? AnimatedOpacity(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                      opacity: _travelContentVisible ? 1.0 : 0.0,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _buildTravelContent(),
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelContent() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🌿', style: TextStyle(fontSize: 22)),
              SizedBox(width: 8),
              Text(
                'Travel with এখন আরণ্যক',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'প্রকৃতির আরও কাছে যাওয়ার পরিকল্পনা করছেন? 🌿',
            style: TextStyle(
              color: Color(0xFF81C784),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'আপনার পরবর্তী বনভ্রমণ, বন্যপ্রাণী পর্যবেক্ষণ, পাখি দেখা, প্রকৃতি অন্বেষণ বা অফবিট ভ্রমণের পরিকল্পনায় এখন আরণ্যক আপনার সঙ্গী হতে চায়।\n\nআপনি কোথায় যেতে চান, কতদিনের জন্য ভ্রমণের পরিকল্পনা করছেন, কী ধরনের অভিজ্ঞতা খুঁজছেন—আমাদের জানান। আমরা চেষ্টা করব আপনার যাত্রা পরিকল্পনা, গন্তব্য সম্পর্কে তথ্য এবং প্রয়োজনীয় পরামর্শ দিয়ে আপনাকে সাহায্য করতে।',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF18221B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.2)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E2E23),
                  Color(0xFF18221B),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('🏡', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 10),
                    Text(
                      'Coming soon..............',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Exclusively "এখন আরণ্যক" maintained homestays in...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTravelPoint(
                    '🌲', 'the forests and foothills of North Bengal'),
                _buildTravelPoint(
                    '⛰️', 'the Himalayan landscapes of Sikkim and Darjeeling'),
                _buildTravelPoint('🦏',
                    "the wilderness surrounding Eastern India's great forests and wildlife landscapes"),
                const SizedBox(height: 16),
                const Text(
                  'প্রকৃতির একেবারে কাছাকাছি, শান্ত পরিবেশে, স্থানীয় সংস্কৃতি ও প্রকৃতির সঙ্গে যুক্ত এক বিশেষ ভ্রমণ অভিজ্ঞতা—খুব শিগগিরই।',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Stay close to nature. Travel responsibly. Discover the wild with এখন আরণ্যক. 🌿',
                  style: TextStyle(
                    color: Color(0xFF81C784),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '💬 পরিকল্পনা করুন আপনার পরবর্তী যাত্রা',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'আপনার ভ্রমণ সংক্রান্ত যেকোনো প্রশ্ন আমাদের পাঠান।',
            style: TextStyle(
                color: Color(0xFF81C784),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          const Text(
            'আপনি জানতে চাইতে পারেন:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildQueryPoint(
              '🌲', 'কোথায় গেলে প্রকৃতির সবচেয়ে কাছাকাছি থাকা যাবে?'),
          _buildQueryPoint('🐦', 'পাখি দেখার জন্য কোন জায়গা উপযুক্ত?'),
          _buildQueryPoint(
              '🐅', 'Wildlife এবং বনভ্রমণের পরিকল্পনা কীভাবে করবেন?'),
          _buildQueryPoint('⛰️', 'পাহাড়, বন বা অফবিট গন্তব্য সম্পর্কে তথ্য'),
          _buildQueryPoint('🏡', 'ভবিষ্যতে আমাদের homestay সম্পর্কিত তথ্য'),
          const SizedBox(height: 16),
          const Text(
            'আপনার প্রশ্ন পাঠান—আমরা আপনাকে সাহায্য করার চেষ্টা করব।',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          KeyboardPressEffect(
            onTap: () => _openTravelQueryDialog(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      color: Colors.black, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'আপনার প্রশ্ন পাঠান (Send Query)',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelPoint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryPoint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTravelQueryDialog() async {
    final msgCtrl = TextEditingController();
    bool sending = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF18221B),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Column(
            children: [
              Text('💬 Travel Query',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              SizedBox(height: 4),
              Text('(ভ্রমণ সংক্রান্ত প্রশ্ন)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF81C784))),
            ],
          ),
          content: TextField(
            controller: msgCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'আপনার প্রশ্ন লিখুন…',
              hintStyle: TextStyle(color: Colors.white38),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('বাতিল', style: TextStyle(color: Colors.white54)),
            ),
            KeyboardPressEffect(
              onTap: sending
                  ? null
                  : () async {
                      final msg = msgCtrl.text.trim();
                      if (msg.isEmpty) return;
                      setModalState(() => sending = true);
                      try {
                        await supabase.from('travel_queries').insert({
                          'message': msg,
                          'user_email': widget.userEmail,
                          'created_at': DateTime.now().toIso8601String(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    '✅ আপনার প্রশ্ন পাঠানো হয়েছে (Query sent successfully)')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString()}')),
                          );
                        }
                      } finally {
                        setModalState(() => sending = false);
                      }
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('পাঠান (Send)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(String phone) async {
    final uri = Uri.parse('https://wa.me/91$phone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Widget _buildNewsTextPanel(Map<String, dynamic> item, bool compact) {
    final TextStyle titleStyle = TextStyle(
      fontSize: compact ? 15 : 20,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: const Color(0xFF382B25),
    );
    final TextStyle snippetStyle = TextStyle(
      fontSize: compact ? 10 : 11,
      height: 1.25,
      color: const Color(0xFF5E5A53),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF3EFE6),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: PaperTexturePainter(seed: (item['title'] ?? '').hashCode),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 22,
              compact ? 10 : 16,
              compact ? 12 : 28,
              compact ? 10 : 16,
            ),
            child: LayoutBuilder(
              builder: (context, panelConstraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: panelConstraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB52B18),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  item['source']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item['date_str']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF746E66),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['title']?.toString() ?? '',
                          maxLines: compact ? 3 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['snippet']?.toString() ?? '',
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: snippetStyle,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB52B18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'পড়ুন',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeGameTile(BuildContext context, String bn, String en,
      dynamic imageAssetOrIcon, Color color, String type, VoidCallback onTap) {
    return KeyboardPressEffect(
      onTap: onTap,
      child: Container(
        width: 145,
        height: 145,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: CustomPaint(
                  painter: GameDiagramPainter(type: type, color: color),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: imageAssetOrIcon is String
                              ? Image.asset(
                                  imageAssetOrIcon,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      alignment: Alignment.center,
                                      color: color.withValues(alpha: 0.15),
                                      child: Icon(
                                        Icons.image_not_supported_rounded,
                                        size: 32,
                                        color: color,
                                      ),
                                    );
                                  },
                                )
                              : imageAssetOrIcon,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(bn,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.2,
                            shadows: [
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                  offset: Offset(0, 1))
                            ])),
                    const SizedBox(height: 2),
                    Text(en,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 2)
                            ])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportantLinksSection() {
    const links = <Map<String, String>>[
      {
        'name': 'eBird',
        'url': 'https://ebird.org/',
        'logo': 'https://www.google.com/s2/favicons?sz=128&domain=ebird.org',
      },
      {
        'name': 'iNaturalist',
        'url': 'https://www.inaturalist.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=inaturalist.org',
      },
      {
        'name': 'Macaulay Library',
        'url': 'https://macaulaylibrary.org/',
        'logo': 'assets/images/macaulay_library.png',
      },
      {
        'name': 'Observation.org',
        'url': 'https://observation.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=observation.org',
      },
      {
        'name': 'Xeno-canto',
        'url': 'https://xeno-canto.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=xeno-canto.org',
      },
      {
        'name': 'Project Noah',
        'url': 'https://projectnoah.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=projectnoah.org',
      },
      {
        'name': 'BirdTrack',
        'url': 'https://www.birdtrack.net/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=birdtrack.net',
      },
      {
        'name': 'Ornitho',
        'url': 'https://www.ornitho.ch/',
        'logo': 'https://www.google.com/s2/favicons?sz=128&domain=ornitho.ch',
      },
      {
        'name': 'Mushroom Observer',
        'url': 'https://mushroomobserver.org/',
        'logo':
            'https://www.google.com/s2/favicons?sz=128&domain=mushroomobserver.org',
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/important_links.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium),
              const SizedBox(width: 8),
              const Text(
                'Important Links',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Padding(
            padding: EdgeInsets.only(left: 28),
            child: Text(
              '(গুরুত্বপূর্ণ লিঙ্ক)',
              style: TextStyle(
                color: Color(0xFF81C784),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720
                  ? 6
                  : constraints.maxWidth >= 480
                  ? 5
                  : 4;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: links.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final link = links[index];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: KeyboardPressEffect(
                          onTap: () async {
                            final uri = Uri.parse(link['url']!);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/blank.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                                FractionallySizedBox(
                                  widthFactor: 0.6,
                                  heightFactor: 0.6,
                                  child: link['logo']!.startsWith('http')
                                      ? CachedNetworkImage(
                                          imageUrl: link['logo']!,
                                          fit: BoxFit.contain,
                                          placeholder: (context, url) =>
                                              const Center(
                                            child: SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              const Icon(
                                            Icons.public_rounded,
                                            color: Colors.white30,
                                            size: 20,
                                          ),
                                        )
                                      : Image.asset(
                                          link['logo']!,
                                          fit: BoxFit.contain,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        link['name']!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLatestNotificationsSection() {
    if (_loadingNotifications) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
      );
    }

    if (_latestNotifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 24, 18, 12),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, color: Color(0xFF00E676), size: 24),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('সর্বশেষ বিজ্ঞপ্তি', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('Latest Notifications & Announcements', style: TextStyle(fontSize: 10, color: Color(0xFF81C784))),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _latestNotifications.length,
            itemBuilder: (context, index) {
              final notif = _latestNotifications[index];
              return Container(
                width: 260,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Card(
                  color: const Color(0xFF18221B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      SoundService.playButtonSound();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationDetailScreen(notification: notif),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notif.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notif.snippet ?? notif.content ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${notif.createdAt.day}/${notif.createdAt.month}/${notif.createdAt.year}',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                              const Text('পড়ুন ↗', style: TextStyle(fontSize: 10, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLiveWildlifeRibbon() {
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 18, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/dashboard.png',
                width: 34,
                height: 34,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'বন্যপ্রাণ বার্তা — ভারতীয় বন্যপ্রাণ ড্যাশবোর্ড',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 37, top: 3),
            child: Text(
              'ভারতের সাম্প্রতিক মাঠ-পর্যবেক্ষণ — প্রতি ৫ মিনিটে নতুন তথ্য',
              style: TextStyle(fontSize: 10, color: Color(0xFF81C784)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 132,
            child: _loadingLiveWildlife && _liveWildlife.isEmpty
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF69F0AE)),
                    ),
                  )
                : _liveWildlife.isEmpty
                    ? Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF102416),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2E7D32)),
                        ),
                        child: Text(
                          _liveWildlifeError ?? 'এই মুহূর্তে কোনও সাম্প্রতিক পর্যবেক্ষণ পাওয়া যায়নি।',
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final withImages = _liveWildlife.where((o) {
                            final image = o.imageUrl?.trim();
                            return o.sourceLocationVerified &&
                                image != null && image.isNotEmpty;
                          }).toList();

                          final balanced = List<WildlifeLiveObservation>.from(withImages)
                            ..shuffle();
                          final visibleObservations = balanced.take(12).toList();

                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics:
                                const BouncingScrollPhysics(),
                            itemCount: visibleObservations.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 9),
                            itemBuilder: (context, index) {
                              final observation =
                                  visibleObservations[index];

                              return SizedBox(
                                width: 124,
                                height: 124,
                                child: WindowsLiveTile(
                                  key: ValueKey(observation.id),
                                  observation: observation,
                                  flipInterval: Duration(
                                    seconds: 5 + (index % 4),
                                  ),
                                  initialDelay: Duration(
                                    milliseconds:
                                        350 + ((index * 673) % 1900),
                                  ),
                                  flipSideways: index.isEven,
                                  reverseDirection: index % 3 == 0,
                                  onTap: () => _showLiveWildlifeDetails(observation),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLiveWildlifeDetails(WildlifeLiveObservation observation) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C1A10),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => _WildlifeDetailSheet(observation: observation),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
        color: const Color(0xFF00E676),
        onRefresh: () async {
          await loadData();
          await _fetchLiveWildlife();
          _refreshVisibleNewsWindow();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // 1) LIVE WILDLIFE OBSERVATIONS
            _buildLiveWildlifeRibbon(),

            // 2) CONTINUE READING SECTION
            if (_lastReadMagId != null && _lastReadTotalPages > 0) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image(
                            image:
                                AssetImage('assets/images/continue_reading.png'),
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain),
                        SizedBox(width: 8),
                        Text('Continue Reading',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 30),
                      child: Text('(পড়া জারি রাখুন)',
                          style:
                          TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF142419),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 65,
                      decoration: BoxDecoration(
                          color: const Color(0xFF1E2E23),
                          borderRadius: BorderRadius.circular(6)),
                      child: MagazineCoverImage(
                        magazineId: _lastReadMagId!,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(formatMagazineTitle(_lastReadTitle),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                              'Page ${_lastReadPage + 1} / $_lastReadTotalPages (${((_lastReadPage + 1) / _lastReadTotalPages * 100).round()}% Completed)',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF81C784))),
                          Text(
                            '(পৃষ্ঠা ${_lastReadPage + 1} / $_lastReadTotalPages)',
                            style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                                value: (_lastReadPage + 1) / _lastReadTotalPages,
                                minHeight: 5,
                                backgroundColor: Colors.white12,
                                color: const Color(0xFF00E676)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    KeyboardPressEffect(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProtectedReaderScreen(
                                magazineId: _lastReadMagId!,
                                title: formatMagazineTitle(_lastReadTitle),
                                userEmail: widget.userEmail,
                                initialPage: _lastReadPage),
                          ),
                        ).then((_) => _loadContinueReadingSession());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/images/resume.png',
                                width: 24,
                                height: 24,
                                filterQuality: FilterQuality.medium),
                            const SizedBox(width: 6),
                            const Text('Resume (চালিয়ে যান)',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.black)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 2) CURRENT HAPPENINGS & WILDLIFE NEWS CAROUSEL
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image(
                          image: AssetImage('assets/images/latest_news.png'),
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Current Happenings & Wildlife News',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 30),
                    child: Text(
                        '(চলতি ঘটনা ও বন্যপ্রাণ বার্তা - প্রতি ২ মিনিটে ৫টি নির্বাচিত খবর)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 292,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _newsPageController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _visibleNews.length,
                        onPageChanged: (index) {
                          if (mounted) {
                            setState(() {
                              _currentNewsPage = index;
                            });
                          }
                        },
                        itemBuilder: (context, index) {
                          final item = _visibleNews[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              margin: EdgeInsets.zero,
                              color: const Color(0xFFF2EEE3),
                              elevation: 7,
                              shadowColor: Colors.black54,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          NewsDetailScreen(newsItem: item),
                                    ),
                                  );
                                },
                                child: LayoutBuilder(
                                  builder: (context, cardConstraints) {
                                    final bool compact =
                                        cardConstraints.maxWidth < 600;
                                    final double artFlex = compact ? 1 : 62;
                                    final double textFlex = compact ? 1 : 38;
                                    return Flex(
                                      direction: compact
                                          ? Axis.vertical
                                          : Axis.horizontal,
                                      children: [
                                        Expanded(
                                          flex: compact ? 1 : artFlex.toInt(),
                                          child: Container(
                                            color: const Color(0xFF0A120D),
                                            child: ClipRect(
                                              child: NewsImageWidget(
                                                item: item, 
                                                fit: BoxFit.contain 
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: compact ? 1 : textFlex.toInt(),
                                          child:
                                          _buildNewsTextPanel(item, compact),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_visibleNews.length > 1)
                        Positioned(
                          left: 16,
                          top: 0,
                          bottom: 30,
                          child: Center(
                            child: Material(
                              color: const Color(0xFFF7F3E8)
                                  .withValues(alpha: 0.92),
                              elevation: 3,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  final prev = (_currentNewsPage - 1 +
                                          _visibleNews.length) %
                                      _visibleNews.length;
                                  _newsPageController.animateToPage(
                                    prev,
                                    duration:
                                        const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    color: Color(0xFF1B241D),
                                    size: 21,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_visibleNews.length > 1)
                        Positioned(
                          right: 16,
                          top: 0,
                          bottom: 30,
                          child: Center(
                            child: Material(
                              color:
                              const Color(0xFFF7F3E8).withValues(alpha: 0.92),
                              elevation: 3,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  final next = (_currentNewsPage + 1) %
                                      _visibleNews.length;
                                  _newsPageController.animateToPage(
                                    next,
                                    duration: const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Color(0xFF1B241D),
                                    size: 21,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_visibleNews.length > 1)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _visibleNews.length,
                                  (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: index == _currentNewsPage ? 18 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: index == _currentNewsPage
                                      ? const Color(0xFF1A201A)
                                      : const Color(0xFF8A8B86),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // 3) LATEST RELEASE SECTION
            if (_issues.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image(
                            image:
                                AssetImage('assets/images/latest_release.png'),
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain),
                        SizedBox(width: 8),
                        Text('Latest Release',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 30),
                      child: Text('(সদ্য প্রকাশিত সংখ্যা)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF81C784))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                    color: const Color(0xFF18221B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 110,
                        height: 155,
                        decoration: BoxDecoration(
                            color: const Color(0xFF1E2E23),
                            borderRadius: BorderRadius.circular(8)),
                        child: MagazineCoverImage(
                        magazineId: _issues.first['id'].toString(),
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(formatMagazineTitle(_issues.first['title']),
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const SizedBox(height: 6),
                            Text(
                                '${_issues.first['issue_date']} • Total ${_issues.first['total_pages']} Pages',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 20),
                            KeyboardPressEffect(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LibraryScreen(
                                      userEmail: widget.userEmail,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset('assets/images/read_full_issue.png',
                                        width: 30,
                                        height: 30,
                                        filterQuality: FilterQuality.medium),
                                    const SizedBox(width: 10),
                                    const Flexible(
                                      child: Text(
                                        'Download from Library (লাইব্রেরি থেকে ডাউনলোড করুন)',
                                        maxLines: 2,
                                        softWrap: true,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.black),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 4) NATURE STUDY THROUGH GAMES SECTION
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image(
                          image: AssetImage(
                              'assets/images/nature_study_through_games.png'),
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain),
                      SizedBox(width: 8),
                      Text('খেলার ছলে প্রকৃতি পাঠ',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 30),
                    child: Text('(Nature Study through Games)',
                        style: TextStyle(fontSize: 10, color: Color(0xFF81C784))),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _buildHomeGameTile(
                    context,
                    'ছবি দেখে চিনুন',
                    'Identify from Picture',
                    'assets/images/identify_image.png',
                    const Color(0xFF2E7D32),
                    'photo',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const WildlifeQuizGame(type: 'photo', difficulty: 'medium'))),
                  ),
                  const SizedBox(width: 12),
                  _buildHomeGameTile(
                    context,
                    'ডাক শুনে চেনা',
                    'Identify from Call',
                    'assets/images/identify_call.png',
                    const Color(0xFF00897B),
                    'audio',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const WildlifeQuizGame(type: 'audio', difficulty: 'medium'))),
                  ),
                  const SizedBox(width: 12),
                  _buildHomeGameTile(
                    context,
                    'ইঙ্গিত বুঝে চেনা',
                    'Identify Hints',
                    'assets/images/identify_clue.png',
                    const Color(0xFF1B5E20),
                    'hint',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const WildlifeQuizGame(type: 'hint', difficulty: 'medium'))),
                  ),
                  const SizedBox(width: 12),
                  _buildHomeGameTile(
                    context,
                    'টুকরো ছবি জোড়া',
                    'Scrambled Image',
                    'assets/images/zigshaw_puzzle.png',
                    const Color(0xFFE65100),
                    'puzzle',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ScrambledImageGame(difficulty: 'medium'))),
                  ),
                  const SizedBox(width: 12),
                  _buildHomeGameTile(
                    context,
                    'শব্দ-জব্দ',
                    'Bird Crossword',
                    'assets/images/crossword.png',
                    const Color(0xFF1565C0),
                    'crossword',
                        () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WordPuzzleGame(difficulty: 'medium'))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 5) COMMUNITY ARTICLE SUBMISSION CALL TO ACTION BANNER
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF142419),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: Color(0xFF00E676), size: 24),
                      SizedBox(width: 10),
                      Text('✍️ এখন আরণ্যকের জন্য কলম ধরুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('🌿 প্রকৃতি নিয়ে আপনার ভাবনা আমাদের সঙ্গে ভাগ করে নিন', style: TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  const Text('প্রকৃতি, বন, বন্যপ্রাণী, পাখি বা পরিবেশ নিয়ে আপনার অভিজ্ঞতা, পর্যবেক্ষণ এবং ভাবনা পৌঁছে দিন এখন আরণ্যক-এর কাছে।\n\nআপনার লেখা প্রবন্ধ (এক হাজার শব্দের মধ্যে) এবং সেই বিষয়ের সঙ্গে সম্পর্কিত আপনার নিজের তোলা ছবি আমাদের পাঠাতে পারেন।\n\nনির্বাচিত লেখা ও ছবি প্রকাশিত হতে পারে এখন আরণ্যক App-এ।\n\n🌿 লিখুন। প্রকৃতিকে অনুভব করুন। আপনার অভিজ্ঞতা অন্যদের সঙ্গে ভাগ করে নিন।', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () {
                        SoundService.playButtonSound();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WritingSubmissionScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      label: const Text('✍️ এখানে আপনার লেখা জমা দিন ➔', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 6) ARANYAK PUBLISHED BOOKS & ONLINE BOOK STORE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 700;
                  return isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildPublishedBooksCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildOnlineStoreBannerCard()),
                          ],
                        )
                      : Column(
                          children: [
                            _buildPublishedBooksCard(),
                            const SizedBox(height: 16),
                            _buildOnlineStoreBannerCard(),
                          ],
                        );
                },
              ),
            ),
            const SizedBox(height: 24),

            // 7) FOREST EXPEDITION PORTAL
            _buildTravelSection(),
            const SizedBox(height: 24),

            // 8) IMPORTANT LINKS SECTION
            _buildImportantLinksSection(),
            const SizedBox(height: 32),

            // 9) LATEST NOTIFICATIONS (if any)
            _buildLatestNotificationsSection(),
            const SizedBox(height: 32),
          ],
        ),
      );
  }

  Widget _buildPublishedBooksCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'এখন আরণ্যক প্রকাশিত বই',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const Text(
          '(Aranyak Published Books)',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF81C784),
          ),
        ),
        const SizedBox(height: 12),
        const AranyakHardboundBookCard(),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _openWhatsApp('9432569171'),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WhatsAppLogo(size: 34),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '9432569171',
                      style: TextStyle(
                        color: Color(0xFF25D366),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '(বইটি কেনার জন্য যোগাযোগ করুন)',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineStoreBannerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF18221B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🛒 অনলাইন বই অর্ডার', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 2),
          const Text('(Ekhon Aranyak Online Book Store)', style: TextStyle(color: Color(0xFF81C784), fontSize: 10)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF121B12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storefront_rounded, color: Color(0xFF00E676), size: 18),
                    SizedBox(width: 8),
                    Text('অন্যান্য প্রকাশনা থেকে প্রকাশিত বইঘর', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                SizedBox(height: 6),
                Text('এখন আরণ্যকের সহযোগিতায় ও অন্যান্য প্রথিতযশা প্রকাশনা থেকে প্রকাশিত বন্যপ্রাণ ও প্রকৃতি বিষয়ক বইসমূহ অনলাইন ক্যাটালগ থেকে পছন্দ করুন এবং সরাসরি অর্ডার করুন।', style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: () {
                SoundService.playButtonSound();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OnlineBookStoreScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.shopping_bag_rounded, color: Colors.black, size: 18),
              label: const Text('🛒 বই ঘর খুলুন', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}