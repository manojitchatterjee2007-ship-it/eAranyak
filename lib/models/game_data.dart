import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';

class WildlifeMedia {
  final String species;
  final String? scientificName;
  final String? imageUrl;
  final String? audioUrl;
  final String source;
  final String? attribution;

  const WildlifeMedia({
    required this.species,
    this.scientificName,
    this.imageUrl,
    this.audioUrl,
    required this.source,
    this.attribution,
  });

  factory WildlifeMedia.fromMap(
      Map<String, dynamic> map, {
        required String fallbackSpecies,
        String fallbackSource = 'Wildlife media',
      }) {
    String? firstString(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      return null;
    }

    return WildlifeMedia(
      species: firstString(
        const ['species', 'common_name', 'commonName', 'name'],
      ) ??
          fallbackSpecies,
      scientificName: firstString(
        const ['scientific_name', 'scientificName', 'latin_name'],
      ),
      imageUrl: firstString(
        const ['image_url', 'imageUrl', 'photo_url', 'photoUrl', 'url'],
      ),
      audioUrl: firstString(
        const ['audio_url', 'audioUrl', 'recording_url', 'recordingUrl'],
      ),
      source: firstString(
        const ['source', 'provider', 'source_name'],
      ) ??
          fallbackSource,
      attribution: firstString(
        const ['attribution', 'credit', 'author', 'recordist'],
      ),
    );
  }
}

class WildlifeMediaService {
  static const String _iNaturalistBase = 'https://api.inaturalist.org/v1/taxa';

  static Future<WildlifeMedia?> _serverMedia({
    required String action,
    required String species,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'wildlife-media',
        body: {'action': action, 'species': species},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['ok'] == true) {
        final Map<String, dynamic> mediaMap =
            data['media'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(data['media'])
                : <String, dynamic>{};
        final media = WildlifeMedia.fromMap(
          mediaMap,
          fallbackSpecies: species,
          fallbackSource: 'Supabase wildlife media',
        );
        if ((action == 'photo' && (media.imageUrl?.isNotEmpty ?? false)) ||
            (action == 'call' && (media.audioUrl?.isNotEmpty ?? false))) {
          return media;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<WildlifeMedia?> fetchSpeciesPhoto(String species) async {
    final serverRes = await _serverMedia(action: 'photo', species: species);
    if (serverRes != null) return serverRes;

    try {
      final uri = Uri.parse(
          '$_iNaturalistBase?q=${Uri.encodeComponent(species)}&per_page=1');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final taxon = results.first as Map<String, dynamic>;
          final defaultPhoto = taxon['default_photo'] as Map<String, dynamic>?;
          if (defaultPhoto != null) {
            String? imgUrl = defaultPhoto['medium_url'] ?? defaultPhoto['url'];
            if (imgUrl != null && imgUrl.contains('square')) {
              imgUrl = imgUrl.replaceAll('square', 'medium');
            }
            final attribution = defaultPhoto['attribution']?.toString();
            return WildlifeMedia(
              species: species,
              scientificName: taxon['name']?.toString(),
              imageUrl: imgUrl,
              source: 'iNaturalist',
              attribution: attribution,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolve a bird call from Wikimedia Commons.
  ///
  /// We deliberately do not use Xeno-canto, Macaulay Library or Cornell
  /// for the quiz. Commons' MediaWiki API returns the actual uploaded
  /// audio URL plus machine-readable MIME/metadata. The File: webpage
  /// itself is never passed to the audio player.
  static final Map<String, WildlifeMedia> _wikimediaAudioCache = {};

  static String? _metadataValue(Map<String, dynamic>? metadata, String key) {
    final raw = metadata?[key];
    if (raw is Map) {
      final value = raw['value'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    if (raw != null && raw.toString().trim().isNotEmpty) {
      return raw.toString().trim();
    }
    return null;
  }

  static int _audioFormatRank(String? mime, String url) {
    final m = (mime ?? '').toLowerCase();
    final u = url.toLowerCase();
    if (m == 'audio/mpeg' || u.endsWith('.mp3')) return 0;
    if (m == 'audio/wav' || m == 'audio/x-wav' || u.endsWith('.wav')) return 1;
    if (m == 'audio/ogg' || m == 'audio/opus' ||
        u.endsWith('.ogg') || u.endsWith('.oga') || u.endsWith('.opus')) {
      return 2;
    }
    if (m.startsWith('audio/')) return 3;
    return 99;
  }

  static Future<WildlifeMedia?> _wikimediaAudio(String species) async {
    final cached = _wikimediaAudioCache[species];
    if (cached != null) return cached;

    try {
      final queries = <String>[
        '"$species" filetype:audio',
        '$species bird filetype:audio',
      ];

      for (final searchTerm in queries) {
        final uri = Uri.https(
          'commons.wikimedia.org',
          '/w/api.php',
          <String, String>{
            'action': 'query',
            'format': 'json',
            'generator': 'search',
            'gsrnamespace': '6',
            'gsrlimit': '30',
            'gsrsearch': searchTerm,
            'prop': 'imageinfo',
            'iiprop': 'url|mime|extmetadata',
          },
        );

        final response = await http.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'eAranyakApp/1.0 (educational wildlife app; Flutter)',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;

        final body = response.body;
        final decoded = jsonDecode(body);
        if (decoded is! Map) continue;

        final query = decoded['query'];
        if (query is! Map) continue;

        final pages = query['pages'];
        if (pages is! Map) continue;

        final candidates = <Map<String, dynamic>>[];

        for (final rawPage in pages.values) {
          if (rawPage is! Map) continue;
          final page = Map<String, dynamic>.from(rawPage);
          final title = page['title']?.toString() ?? '';
          final imageInfo = page['imageinfo'];

          if (imageInfo is! List || imageInfo.isEmpty) continue;
          final first = imageInfo.first;
          if (first is! Map) continue;

          final info = Map<String, dynamic>.from(first);
          final url = info['url']?.toString().trim();
          final mime = info['mime']?.toString().trim();

          if (url == null || url.isEmpty || mime == null) continue;
          if (!mime.toLowerCase().startsWith('audio/')) continue;

          final titleLower = title.toLowerCase();
          final speciesLower = species.toLowerCase();

          int relevance = 0;
          if (titleLower.contains(speciesLower)) relevance += 100;
          if (titleLower.contains('call')) relevance += 20;
          if (titleLower.contains('song')) relevance += 10;

          final metadata = info['extmetadata'] is Map
              ? Map<String, dynamic>.from(info['extmetadata'])
              : null;

          candidates.add({
            'url': url,
            'mime': mime,
            'title': title,
            'metadata': metadata,
            'relevance': relevance,
          });
        }

        if (candidates.isEmpty) continue;

        candidates.sort((a, b) {
          final relevanceCompare =
          (b['relevance'] as int).compareTo(a['relevance'] as int);
          if (relevanceCompare != 0) return relevanceCompare;

          return _audioFormatRank(
            a['mime']?.toString(),
            a['url'].toString(),
          ).compareTo(
            _audioFormatRank(
              b['mime']?.toString(),
              b['url'].toString(),
            ),
          );
        });

        final best = candidates.first;
        final metadata = best['metadata'] as Map<String, dynamic>?;

        final artist = _metadataValue(metadata, 'Artist') ??
            _metadataValue(metadata, 'Credit') ??
            _metadataValue(metadata, 'Creator');

        final license = _metadataValue(metadata, 'LicenseShortName') ??
            _metadataValue(metadata, 'UsageTerms');

        final attributionParts = <String>[
          if (artist != null && artist.isNotEmpty) 'Recorded by $artist',
          if (license != null && license.isNotEmpty) license,
          'Wikimedia Commons',
        ];

        final media = WildlifeMedia(
          species: species,
          audioUrl: best['url'].toString(),
          source: 'Wikimedia Commons',
          attribution: attributionParts.join(' • '),
        );

        _wikimediaAudioCache[species] = media;
        return media;
      }
    } catch (_) {
      // The quiz handles this as an unavailable call rather than crashing.
    }

    return null;
  }

  static Future<WildlifeMedia?> fetchBirdCall(String species) async {
    // Prefer the server-side aggregator when it returns a usable call…
    final serverRes = await _serverMedia(action: 'call', species: species);
    if (serverRes != null && (serverRes.audioUrl?.isNotEmpty ?? false)) {
      return serverRes;
    }
    // …otherwise fall back to the public Wikimedia Commons search.
    return _wikimediaAudio(species);
  }
}

class WildlifeGameSpecies {
  final String english;
  final String bengali;
  final String question;

  const WildlifeGameSpecies({
    required this.english,
    required this.bengali,
    required this.question,
  });

  String get label => '$english ($bengali)';
}

class WildlifeGameData {
  static const List<WildlifeGameSpecies> photoSpecies = [
    WildlifeGameSpecies(
      english: 'Bengal Tiger',
      bengali: 'রয়েল বেঙ্গল টাইগার',
      question: 'Identify this majestic national animal / এই রাজকীয় প্রাণীটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Asian Elephant',
      bengali: 'এশীয় হাতি',
      question: 'Identify this gentle giant of the forest / বনের এই শান্ত দৈত্যটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'One-horned Rhinoceros',
      bengali: 'একশৃঙ্গ গণ্ডার',
      question: 'Identify this prehistoric-looking mammal / প্রাগৈতিহাসিক চেহারার এই প্রাণীটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Himalayan Monal',
      bengali: 'হিমালয়ান মোনাল',
      question: 'Identify this high-altitude bird / উচ্চ পার্বত্য এই পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Great Indian Bustard',
      bengali: 'গ্রেট ইন্ডিয়ান বাস্টার্ড',
      question: 'Identify this iconic grassland bird / এই ঘাসভূমির পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Indian Skimmer',
      bengali: 'ইন্ডিয়ান স্কিমার',
      question: 'Identify this river bird / এই নদী-নির্ভর পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Snow Leopard',
      bengali: 'তুষার চিতা',
      question: 'Identify this mountain cat / পাহাড়ের এই বিড়ালটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Batagur baska',
      bengali: 'বাটাগুর বাসকা',
      question: 'Identify this endangered turtle / এই বিপন্ন কচ্ছপটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Gharial',
      bengali: 'ঘড়িয়াল',
      question: 'Identify this long-snouted crocodilian / লম্বা নাকের এই সরীসৃপটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Great Hornbill',
      bengali: 'ধনেশ',
      question: 'Identify this large rainforest bird / বৃষ্টিচ্ছায় অরণ্যের এই বড় পাখিটি চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Red Panda',
      bengali: 'লাল পাণ্ডা',
      question: 'Identify this Himalayan mammal / এই হিমালয়ান স্তন্যপায়ীটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Indian Pangolin',
      bengali: 'বনরুই',
      question: 'Identify this armour-clad mammal / বর্মধারী এই প্রাণীটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Barasingha',
      bengali: 'বারাসিঙ্গা',
      question: 'Identify this wetland deer / এই জলাভূমি-নির্ভর হরিণটিকে চিনুন',
    ),
  ];

  static const List<WildlifeGameSpecies> audioSpecies = [
    WildlifeGameSpecies(
      english: 'Oriental Magpie-Robin',
      bengali: 'দোয়েল',
      question: 'Listen carefully and identify this bird / মন দিয়ে শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Common Myna',
      bengali: 'শালিক',
      question: 'Whose call is this? / এই ডাকটি কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'Asian Koel',
      bengali: 'কোকিল',
      question: 'Identify the bird from its call / ডাক শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Greater Coucal',
      bengali: 'কুবো',
      question: 'Listen to the call and identify the bird / ডাক শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Black Drongo',
      bengali: 'ফিঙে',
      question: 'Identify this bird by its sharp call / ডাক শুনে পাখিটিকে চিনুন',
    ),
    WildlifeGameSpecies(
      english: 'Spotted Dove',
      bengali: 'তিলঘঘু',
      question: 'Which bird makes this cooing sound? / এই কুজন কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'Jungle Babbler',
      bengali: 'ছাতারে',
      question: 'Identify this noisy group call / এই শোরগোলপূর্ণ ডাকটি কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'White-throated Kingfisher',
      bengali: 'সাদা-গলা মাছরাঙা',
      question: 'Which bird made this call? / এই ডাকটি কোন পাখির?',
    ),
    WildlifeGameSpecies(
      english: 'Coppersmith Barbet',
      bengali: 'বসন্তবৌরি',
      question: 'Identify this rhythmic call / এই ছন্দময় ডাকটি চিনুন',
    ),
  ];

  static const List<Map<String, dynamic>> hintQuiz = [
    {
      'hints': [
        'I have the longest snout among all crocodilians.',
        'I am critically endangered and found in the Chambal river.',
        'Adult males have a pot-like structure on my nose.',
      ],
      'options': [
        'Gharial (ঘড়িয়াল)',
        'Mugger Crocodile (মাগর কুমির)',
        'Saltwater Crocodile (নোনা জলের কুমির)',
        'False Gharial (ফলস ঘড়িয়াল)',
      ],
      'answer': 'Gharial (ঘড়িয়াল)',
    },
    {
      'hints': [
        'I am a marine herbivore often called "Sea Cow".',
        'I am found in the Gulf of Mannar and Andaman islands.',
        'I am the state animal of Andaman and Nicobar.',
      ],
      'options': [
        'Dugong (ডুগং)',
        'Manatee (ম্যানাটি)',
        'Dolphin (ডলফিন)',
        'Porpoise (পরপাস)',
      ],
      'answer': 'Dugong (ডুগং)',
    },
    {
      'hints': [
        'I am the state bird of West Bengal.',
        'I have a brilliant blue color on my back and wings.',
        'I wait patiently on branches before diving for fish.',
      ],
      'options': [
        'White-throated Kingfisher (সাদা-গলা মাছরাঙা)',
        'Pied Kingfisher (কালো-সাদা মাছরাঙা)',
        'Common Kingfisher (ছোট মাছরাঙা)',
        'Blue Jay (নীলকণ্ঠ)',
      ],
      'answer': 'White-throated Kingfisher (সাদা-গলা মাছরাঙা)',
    },
    {
      'hints': [
        'I am an ancient, living fossil found on the Odisha coast.',
        'I come to the beach in thousands for "Arribada".',
        'I am the smallest and most abundant sea turtle.',
      ],
      'options': [
        'Olive Ridley (অলিভ রিডলি)',
        'Green Sea Turtle (সবুজ কচ্ছপ)',
        'Loggerhead (লগারহেড)',
        'Leatherback (লেদারব্যাক)',
      ],
      'answer': 'Olive Ridley (অলিভ রিডলি)',
    },
    {
      'hints': [
        'I am the only ape species found in India.',
        'I am known for my loud, distinctive hooting calls.',
        'I live in the rainforest forests of Northeast India.',
      ],
      'options': [
        'Hoolock Gibbon (উলুক)',
        'Bonobo (বোনাবো)',
        'Gorilla (গরিলা)',
        'Orangutan (ওরাংওটাং)',
      ],
      'answer': 'Hoolock Gibbon (উলুক)',
    },
    {
      'hints': [
        'I am an endemic macaque found in the Western Ghats.',
        'I have a silver-white mane surrounding my face.',
        'I am primarily a fruit-eater but also eat insects.',
      ],
      'options': [
        'Lion-tailed Macaque (সিংহপুচ্ছ বাঁদর)',
        'Bonnet Macaque (টুপি বাঁদর)',
        'Rhesus Macaque (লাল বাঁদর)',
        'Langur (লঙ্গুর)',
      ],
      'answer': 'Lion-tailed Macaque (সিংহপুচ্ছ বাঁদর)',
    },
    {
      'hints': [
        'I am the "dancing deer" of Manipur.',
        'I live on floating islands of vegetation called "Phumdis".',
        'I am found only in Keibul Lamjao National Park.',
      ],
      'options': [
        'Sangai (সাঙ্গাই)',
        'Hog Deer (পাড় হরিণ)',
        'Barking Deer (মায়া হরিণ)',
        'Chital (চিত্রা হরিণ)',
      ],
      'answer': 'Sangai (সাঙ্গাই)',
    },
    {
      'hints': [
        'I am the only wild goat found in South India.',
        'I have curved horns and a stocky build.',
        'I live in the high-altitude grassy hills of Nilgiris.',
      ],
      'options': [
        'Nilgiri Tahr (নীলগিরি তহর)',
        'Ibex (আইবেক্স)',
        'Markhor (মারখোর)',
        'Mountain Goat (পাহাড়ি ছাগল)',
      ],
      'answer': 'Nilgiri Tahr (নীলগিরি তহর)',
    },
    {
      'hints': [
        'I am famous as the "Ghost of the Mountains".',
        'I am perfectly camouflaged in the rocky Himalayas.',
        'I cannot roar, but I can hiss and growl.',
      ],
      'options': [
        'Snow Leopard (তুষার চিতা)',
        'Clouded Leopard (মেঘলা চিতা)',
        'Puma (পুমা)',
        'Jaguar (জাগুয়ার)',
      ],
      'answer': 'Snow Leopard (তুষার চিতা)',
    },
    {
      'hints': [
        'I am the state animal of Sikkim.',
        'I spend most of my time in trees eating bamboo.',
        'I have a long, bushy, ringed tail.',
      ],
      'options': [
        'Red Panda (লাল পাণ্ডা)',
        'Giant Panda (পাণ্ডা)',
        'Koala (কোয়ালা)',
        'Lemur (লেমুর)',
      ],
      'answer': 'Red Panda (লাল পাণ্ডা)',
    },
    {
      'hints': [
        'I have a horn-like casque on top of my bill.',
        'I play a vital role in dispersing rainforest seeds.',
        'I am the state bird of Kerala and Arunachal Pradesh.',
      ],
      'options': [
        'Great Hornbill (ধনেশ)',
        'Malabar Pied Hornbill (কালো-সাদা ধনেশ)',
        'Grey Hornbill (ধূসর ধনেশ)',
        'Toucan (টুকান)',
      ],
      'answer': 'Great Hornbill (ধনেশ)',
    },
    {
      'hints': [
        'I am the largest of all wild cattle in the world.',
        'I have massive horns and white "socks" on my legs.',
        'I am found in large herds in Central Indian forests.',
      ],
      'options': [
        'Gaur (গৌর/ইন্ডিয়ান বাইসন)',
        'Wild Buffalo (বন মহিষ)',
        'Yak (চমরী গাই)',
        'Nilgai (নীলগাই)',
      ],
      'answer': 'Gaur (গৌর/ইন্ডিয়ান বাইসন)',
    },
    {
      'hints': [
        'I am a venomous snake known as the "King of Cobras".',
        'I am the only snake in the world that builds nests.',
        'I feed primarily on other snakes.',
      ],
      'options': [
        'King Cobra (রাজগোখরো)',
        'Spectacled Cobra (গোখরো)',
        'Monocled Cobra (কেউটে)',
        'Python (অজগর)',
      ],
      'answer': 'King Cobra (রাজগোখরো)',
    },
  ];

  static const List<String> puzzleSpecies = [
    'Indian Skimmer',
    'Great Indian Bustard',
    'Bengal Tiger',
    'Red Panda',
    'Snow Leopard',
  ];
}
