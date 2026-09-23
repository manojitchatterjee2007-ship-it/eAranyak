import 'dart:convert';
import 'dart:io';

/// Resolves Bengali vernacular names for wildlife observations.
///
/// Priority:
/// 1. Bengali name already supplied by the trusted wildlife feed.
/// 2. iNaturalist Bengali locale (bn), matched against the scientific name.
///
/// The service is deliberately cached in memory so the Home screen does not
/// repeatedly query iNaturalist for the same species during its 5-minute feed
/// refresh cycle.
class WildlifeBengaliNameService {
  static final Map<String, String?> _cache = <String, String?>{};

  static String _clean(dynamic value) => value?.toString().trim() ?? '';

  static bool _containsBengali(String value) => RegExp(r'[\u0980-\u09FF]').hasMatch(value);

  static String _speciesKey(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    return parts.length >= 2 ? '${parts[0]} ${parts[1]}'.toLowerCase() : value.trim().toLowerCase();
  }

  static String _normaliseScientific(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static String? _embeddedBengali(Map<String, dynamic> raw) {
    const keys = <String>[
      'bengali_name',
      'bengaliName',
      'bn_name',
      'name_bn',
      'vernacular_name_bn',
      'common_name_bn',
      'bengali_common_name',
      'commonNameBn',
    ];

    for (final key in keys) {
      final value = _clean(raw[key]);
      if (value.isNotEmpty && _containsBengali(value)) return value;
    }
    return null;
  }

  static Future<String?> resolve({
    required String scientificName,
    Map<String, dynamic>? raw,
  }) async {
    final embedded = raw == null ? null : _embeddedBengali(raw);
    if (embedded != null) return embedded;

    final key = _speciesKey(scientificName);
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];

    final parts = key.split(' ');
    if (parts.length < 2) {
      _cache[key] = null;
      return null;
    }

    final exactScientific = '${parts[0]} ${parts[1]}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    client.userAgent = 'eAranyak/1.0 (wildlife Bengali name lookup)';

    try {
      final uri = Uri.https('api.inaturalist.org', '/v1/taxa', <String, String>{
        'q': exactScientific,
        'locale': 'bn',
        'all_names': 'true',
        'rank': 'species',
        'per_page': '5',
      });

      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _cache[key] = null;
        return null;
      }

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      final results = decoded is Map && decoded['results'] is List
          ? decoded['results'] as List
          : const <dynamic>[];

      for (final item in results) {
        if (item is! Map) continue;
        final taxon = Map<String, dynamic>.from(item);
        final taxonScientific = _clean(taxon['name']);
        if (_normaliseScientific(taxonScientific) != _normaliseScientific(exactScientific)) {
          continue;
        }

        final preferred = _clean(taxon['preferred_common_name']);
        if (preferred.isNotEmpty && _containsBengali(preferred)) {
          _cache[key] = preferred;
          return preferred;
        }

        final names = taxon['names'];
        if (names is List) {
          for (final nameItem in names) {
            if (nameItem is! Map) continue;
            final name = _clean(nameItem['name']);
            final lexicon = _clean(nameItem['lexicon']).toLowerCase();
            if (name.isNotEmpty && _containsBengali(name) &&
                (lexicon.isEmpty || lexicon == 'bengali' || lexicon == 'bangla')) {
              _cache[key] = name;
              return name;
            }
          }
        }
      }
    } catch (_) {
      // Name enrichment is optional. Never allow it to break the wildlife feed.
    } finally {
      client.close(force: true);
    }

    _cache[key] = null;
    return null;
  }

  static void clearMemoryCache() => _cache.clear();
}
