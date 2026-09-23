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
            'User-Agent': 'eAranyakApp/1.0',
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

          return _audioFormatRank(a['mime']?.toString(), a['url'].toString())
              .compareTo(_audioFormatRank(b['mime']?.toString(), b['url'].toString()));
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
    } catch (_) {}
    return null;
  }

  static Future<WildlifeMedia?> fetchBirdCall(String species) async {
    final serverRes = await _serverMedia(action: 'call', species: species);
    if (serverRes != null && (serverRes.audioUrl?.isNotEmpty ?? false)) {
      return serverRes;
    }
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

  String get label => '$bengali ($english)';
}

class WordPuzzleItem {
  final String english;
  final List<String> syllables;
  const WordPuzzleItem(this.english, this.syllables);

  static final RegExp _akshara = RegExp(
    r'[\u0995-\u09B9\u09DC-\u09DF\u09F0\u09F1]\u09BC?(?:\u09CD[\u0995-\u09B9\u09DC-\u09DF\u09F0\u09F1]\u09BC?)*[\u09BE-\u09C4\u09C7\u09C8\u09CB\u09CC]?[\u0981-\u0983]?'
    r'|[\u0985-\u0994][\u0981-\u0983]?',
  );

  factory WordPuzzleItem.fromBengali(String english, String bengali) {
    final compact = bengali.replaceAll(' ', '').trim();
    final tiles = _akshara.allMatches(compact).map((m) => m.group(0)!).toList();
    return WordPuzzleItem(english, tiles.isNotEmpty ? tiles : [compact]);
  }
}

class WildlifeGameData {
  // ACTIVE DATA (Populated by Supabase)
  static List<WildlifeGameSpecies> photoSpecies = _allPhotoSpecies.toList();
  static List<WildlifeGameSpecies> audioSpecies = _allAudioSpecies.toList();
  static List<Map<String, dynamic>> hintQuiz = _allHintQuiz.toList();
  static List<String> puzzleSpecies = _allPuzzleSpecies.toList();
  static final List<WordPuzzleItem> wordPuzzles = _buildWordPuzzles();

  // SUPABASE WEEKLY PAYLOAD LOADER
  static Future<void> loadWeeklyGames() async {
    try {
      // NOTE: Ensure your table name in Supabase matches exactly ('weekly_game_data')
      final res = await supabase
          .from('weekly_game_data') 
          .select()
          .order('created_at', ascending: false)
          .limit(20);

      final rows = res as List<dynamic>;

      bool photoLoaded = false;
      bool audioLoaded = false;
      bool hintLoaded = false;
      bool scrambleLoaded = false;

      for (var row in rows) {
        final category = row['category'] as String?;
        final payloadStr = row['payload'] as String?;
        if (category == null || payloadStr == null) continue;

        try {
          final payload = jsonDecode(payloadStr);

          if (category == 'photo' && !photoLoaded) {
            final speciesList = List<String>.from(payload['species']);
            photoSpecies = _allPhotoSpecies
                .where((s) => speciesList.contains(s.english))
                .toList();
            // Fallback if mapping failed
            if (photoSpecies.isEmpty) photoSpecies = _allPhotoSpecies.toList();
            photoLoaded = true;
          } 
          else if (category == 'audio' && !audioLoaded) {
            final speciesList = List<String>.from(payload['species']);
            audioSpecies = _allAudioSpecies
                .where((s) => speciesList.contains(s.english))
                .toList();
            if (audioSpecies.isEmpty) audioSpecies = _allAudioSpecies.toList();
            audioLoaded = true;
          } 
          else if (category == 'hint' && !hintLoaded) {
            final indices = List<int>.from(payload['indices']);
            hintQuiz = indices
                .where((i) => i >= 0 && i < _allHintQuiz.length)
                .map((i) => _allHintQuiz[i])
                .toList();
            if (hintQuiz.isEmpty) hintQuiz = _allHintQuiz.toList();
            hintLoaded = true;
          } 
          else if (category == 'scramble' && !scrambleLoaded) {
            puzzleSpecies = List<String>.from(payload['species']);
            if (puzzleSpecies.isEmpty) puzzleSpecies = _allPuzzleSpecies.toList();
            scrambleLoaded = true;
          }
        } catch (e) {
          print('Error parsing payload for $category: $e');
        }
      }
    } catch (e) {
      print('Error fetching weekly games from Supabase: $e');
    }
  }

  // ---------------------------------------------------------------------
  // MASTER DICTIONARY (Fallback / Local Cache)
  // ---------------------------------------------------------------------
  static const List<WildlifeGameSpecies> _allPhotoSpecies = [
    WildlifeGameSpecies(english: 'Bengal Tiger', bengali: 'রয়েল বেঙ্গল টাইগার', question: 'Identify this majestic national animal / এই রাজকীয় প্রাণীটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Asian Elephant', bengali: 'এশীয় হাতি', question: 'Identify this gentle giant of the forest / বনের এই শান্ত দৈত্যটিকে চিনুন'),
    WildlifeGameSpecies(english: 'One-horned Rhinoceros', bengali: 'একশৃঙ্গ গণ্ডার', question: 'Identify this prehistoric-looking mammal / প্রাগৈতিহাসিক চেহারার এই প্রাণীটি চিনুন'),
    WildlifeGameSpecies(english: 'Himalayan Monal', bengali: 'হিমালয়ান মোনাল', question: 'Identify this high-altitude bird / উচ্চ পার্বত্য এই পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Great Indian Bustard', bengali: 'গ্রেট ইন্ডিয়ান বাস্টার্ড', question: 'Identify this iconic grassland bird / এই ঘাসভূমির পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Indian Skimmer', bengali: 'ইন্ডিয়ান স্কিমার', question: 'Identify this river bird / এই নদী-নির্ভর পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Snow Leopard', bengali: 'তুষার চিতা', question: 'Identify this mountain cat / পাহাড়ের এই বিড়ালটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Batagur baska', bengali: 'বাটাগুর বাসকা', question: 'Identify this endangered turtle / এই বিপন্ন কচ্ছপটি চিনুন'),
    WildlifeGameSpecies(english: 'Gharial', bengali: 'ঘড়িয়াল', question: 'Identify this long-snouted crocodilian / লম্বা নাকের এই সরীসৃপটি চিনুন'),
    WildlifeGameSpecies(english: 'Great Hornbill', bengali: 'ধনেশ', question: 'Identify this large rainforest bird / বৃষ্টিচ্ছায় অরণ্যের এই বড় পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Red Panda', bengali: 'লাল পাণ্ডা', question: 'Identify this Himalayan mammal / এই হিমালয়ান স্তন্যপায়ীটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Indian Pangolin', bengali: 'বনরুই', question: 'Identify this armour-clad mammal / বর্মধারী এই প্রাণীটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Barasingha', bengali: 'বারাসিঙ্গা', question: 'Identify this wetland deer / এই জলাভূমি-নির্ভর হরিণটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Indian Peafowl', bengali: 'ময়ূর', question: 'Identify India\'s national bird / ভারতের জাতীয় পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Sloth Bear', bengali: 'ভালুক', question: 'Identify this shaggy-coated bear / এই লোমশ ভালুকটি চিনুন'),
    WildlifeGameSpecies(english: 'Indian Wolf', bengali: 'নেকড়ে', question: 'Identify this grassland predator / এই ঘাসভূমির শিকারীকে চিনুন'),
    WildlifeGameSpecies(english: 'Striped Hyena', bengali: 'দাগি হায়েনা', question: 'Identify this scavenging carnivore / এই মাংসাশী প্রাণীটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Sambar Deer', bengali: 'সাম্বার হরিণ', question: 'Identify this large Indian deer / এই বড় হরিণটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Nilgai', bengali: 'নীলগাই', question: 'Identify India\'s largest antelope / ভারতের সবচেয়ে বড় হরিণজাতীয় প্রাণীটি চিনুন'),
    WildlifeGameSpecies(english: 'King Cobra', bengali: 'রাজগোখরো', question: 'Identify this venomous nest-building snake / এই বিষধর সাপটিকে চিনুন'),
  ];

  static const List<WildlifeGameSpecies> _allAudioSpecies = [
    WildlifeGameSpecies(english: 'Oriental Magpie-Robin', bengali: 'দোয়েল', question: 'Listen carefully and identify this bird / মন দিয়ে শুনে পাখিটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Common Myna', bengali: 'শালিক', question: 'Whose call is this? / এই ডাকটি কোন পাখির?'),
    WildlifeGameSpecies(english: 'Asian Koel', bengali: 'কোকিল', question: 'Identify the bird from its call / ডাক শুনে পাখিটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Greater Coucal', bengali: 'কুবো', question: 'Listen to the call and identify the bird / ডাক শুনে পাখিটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Black Drongo', bengali: 'ফিঙে', question: 'Identify this bird by its sharp call / ডাক শুনে পাখিটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Spotted Dove', bengali: 'তিলা ঘুঘু', question: 'Which bird makes this cooing sound? / এই কুজন কোন পাখির?'),
    WildlifeGameSpecies(english: 'Jungle Babbler', bengali: 'ছাতারে', question: 'Identify this noisy group call / এই শোরগোলপূর্ণ ডাকটি কোন পাখির?'),
    WildlifeGameSpecies(english: 'White-throated Kingfisher', bengali: 'সাদাবুক মাছরাঙা', question: 'Which bird made this call? / এই ডাকটি কোন পাখির?'),
    WildlifeGameSpecies(english: 'Coppersmith Barbet', bengali: 'বসন্তবৌরি', question: 'Identify this rhythmic call / এই ছন্দময় ডাকটি চিনুন'),
    WildlifeGameSpecies(english: 'Indian Cuckoo', bengali: 'বৌ কথা কও', question: 'Which bird "asks its wife to speak"? / কোন পাখির ডাকে এই কথা শোনা যায়?'),
    WildlifeGameSpecies(english: 'Common Hawk-Cuckoo', bengali: 'পাপিয়া', question: 'Identify this bird known for its rising call / ক্রমবর্ধমান সুরের এই পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'House Crow', bengali: 'পাতি কাক', question: 'Identify this familiar city bird by its call / এই পরিচিত পাখিটিকে ডাক শুনে চিনুন'),
    WildlifeGameSpecies(english: 'Rose-ringed Parakeet', bengali: 'টিয়া', question: 'Which bird makes this screeching call? / এই তীক্ষ্ণ ডাকটি কোন পাখির?'),
    WildlifeGameSpecies(english: 'Common Tailorbird', bengali: 'টুনটুনি', question: 'Identify this tiny loud-voiced bird / এই ছোট্ট উচ্চকণ্ঠ পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Barn Owl', bengali: 'লক্ষী পেঁচা', question: 'Identify this night bird by its screech / এই রাতের পাখিটিকে চিনুন'),
    WildlifeGameSpecies(english: 'Indian Roller', bengali: 'নীলকণ্ঠ', question: 'Identify this bird by its harsh call / কর্কশ ডাক শুনে পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Common Hoopoe', bengali: 'মোহনচূড়া', question: 'Which bird makes this soft "oop-oop" call? / এই নরম ডাকটি কোন পাখির?'),
    WildlifeGameSpecies(english: 'Black-hooded Oriole', bengali: 'বেনেবৌ', question: 'Identify this fluty-voiced bird / এই মধুর সুরেলা পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'House Sparrow', bengali: 'চড়াই', question: 'Identify this common chirping bird / এই পরিচিত কিচিরমিচির পাখিটি চিনুন'),
    WildlifeGameSpecies(english: 'Baya Weaver', bengali: 'বাবুই', question: 'Identify this nest-weaving bird by its call / বাসা-বোনা এই পাখিটিকে চিনুন'),
  ];

  static const List<Map<String, dynamic>> _allHintQuiz = [
    {
      'hints': [
        'আমি সব কুমিরের মধ্যে সবচেয়ে লম্বা নাক-বিশিষ্ট। / I have the longest snout among all crocodilians.',
        'আমি অতি বিপন্ন এবং চম্বল নদীতে পাওয়া যাই। / I am critically endangered and found in the Chambal river.',
        'পূর্ণবয়স্ক পুরুষদের নাকে একটি কলসির মতো গঠন থাকে। / Adult males have a pot-like structure on my nose.',
      ],
      'options': ['ঘড়িয়াল (Gharial)', 'মাগর কুমির (Mugger Crocodile)', 'নোনা জলের কুমির (Saltwater Crocodile)', 'ফলস ঘড়িয়াল (False Gharial)'],
      'answer': 'ঘড়িয়াল (Gharial)',
    },
    {
      'hints': [
        'আমাকে প্রায়ই "সমুদ্র গরু" বলা হয়, আমি একটি সামুদ্রিক তৃণভোজী। / I am a marine herbivore often called "Sea Cow".',
        'আমি মান্নার উপসাগর ও আন্দামান দ্বীপপুঞ্জে পাওয়া যাই। / I am found in the Gulf of Mannar and Andaman islands.',
        'আমি আন্দামান ও নিকোবরের রাজ্য প্রাণী। / I am the state animal of Andaman and Nicobar.',
      ],
      'options': ['ডুগং (Dugong)', 'ম্যানাটি (Manatee)', 'ডলফিন (Dolphin)', 'পরপাস (Porpoise)'],
      'answer': 'ডুগং (Dugong)',
    },
    {
      'hints': [
        'আমি পশ্চিমবঙ্গের রাজ্য পাখি। / I am the state bird of West Bengal.',
        'আমার পিঠ ও ডানায় উজ্জ্বল নীল রঙ আছে। / I have a brilliant blue color on my back and wings.',
        'মাছ শিকারের আগে আমি ধৈর্য ধরে ডালে বসে থাকি। / I wait patiently on branches before diving for fish.',
      ],
      'options': ['সাদাবুক মাছরাঙা (White-throated Kingfisher)', 'কালো-সাদা মাছরাঙা (Pied Kingfisher)', 'ছোট মাছরাঙা (Common Kingfisher)', 'নীলকণ্ঠ (Blue Jay)'],
      'answer': 'সাদাবুক মাছরাঙা (White-throated Kingfisher)',
    },
    {
      'hints': [
        'আমি ওড়িশার উপকূলে পাওয়া একটি প্রাচীন, জীবন্ত জীবাশ্ম। / I am an ancient, living fossil found on the Odisha coast.',
        'আমি হাজার হাজার সংখ্যায় "আরিবাদা"-র জন্য সৈকতে আসি। / I come to the beach in thousands for "Arribada".',
        'আমি সবচেয়ে ছোট ও সবচেয়ে সংখ্যাগরিষ্ঠ সামুদ্রিক কচ্ছপ। / I am the smallest and most abundant sea turtle.',
      ],
      'options': ['অলিভ রিডলি (Olive Ridley)', 'সবুজ কচ্ছপ (Green Sea Turtle)', 'লগারহেড (Loggerhead)', 'লেদারব্যাক (Leatherback)'],
      'answer': 'অলিভ রিডলি (Olive Ridley)',
    },
    {
      'hints': [
        'আমিই ভারতে পাওয়া একমাত্র বনমানুষ প্রজাতি। / I am the only ape species found in India.',
        'আমার জোরে, স্বতন্ত্র হুতাশ ডাকের জন্য পরিচিত। / I am known for my loud, distinctive hooting calls.',
        'আমি উত্তর-পূর্ব ভারতের রেইনফরেস্টে বাস করি। / I live in the rainforest of Northeast India.',
      ],
      'options': ['উলুক (Hoolock Gibbon)', 'বোনাবো (Bonobo)', 'গরিলা (Gorilla)', 'ওরাংওটাং (Orangutan)'],
      'answer': 'উলুক (Hoolock Gibbon)',
    },
    {
      'hints': [
        'আমি পশ্চিমঘাটে পাওয়া একটি স্থানীয় বানরজাতীয় প্রাণী। / I am an endemic macaque found in the Western Ghats.',
        'আমার মুখের চারপাশে রূপালি-সাদা কেশর আছে। / I have a silver-white mane surrounding my face.',
        'আমি মূলত ফলভোজী, তবে পোকামাকড়ও খাই। / I am primarily a fruit-eater but also eat insects.',
      ],
      'options': ['সিংহপুচ্ছ বাঁদর (Lion-tailed Macaque)', 'টুপি বাঁদর (Bonnet Macaque)', 'লাল বাঁদর (Rhesus Macaque)', 'লঙ্গুর (Langur)'],
      'answer': 'সিংহপুচ্ছ বাঁদর (Lion-tailed Macaque)',
    },
    {
      'hints': [
        'আমি মণিপুরের "নাচুনে হরিণ"। / I am the "dancing deer" of Manipur.',
        'আমি "ফুমডিস" নামক ভাসমান উদ্ভিদ-দ্বীপে বাস করি। / I live on floating islands of vegetation called "Phumdis".',
        'আমি শুধুমাত্র কেইবুল লামজাও জাতীয় উদ্যানে পাওয়া যাই। / I am found only in Keibul Lamjao National Park.',
      ],
      'options': ['সাঙ্গাই (Sangai)', 'পাড় হরিণ (Hog Deer)', 'মায়া হরিণ (Barking Deer)', 'চিত্রা হরিণ (Chital)'],
      'answer': 'সাঙ্গাই (Sangai)',
    },
    {
      'hints': [
        'আমিই দক্ষিণ ভারতে পাওয়া একমাত্র বন্য ছাগল। / I am the only wild goat found in South India.',
        'আমার বাঁকা শিং ও শক্তপোক্ত দেহ আছে। / I have curved horns and a stocky build.',
        'আমি নীলগিরির উচ্চ-উচ্চতার ঘাসের পাহাড়ে বাস করি। / I live in the high-altitude grassy hills of Nilgiris.',
      ],
      'options': ['নীলগিরি তহর (Nilgiri Tahr)', 'আইবেক্স (Ibex)', 'মারখোর (Markhor)', 'পাহাড়ি ছাগল (Mountain Goat)'],
      'answer': 'নীলগিরি তহর (Nilgiri Tahr)',
    },
    {
      'hints': [
        'আমি "পাহাড়ের ভূত" নামে বিখ্যাত। / I am famous as the "Ghost of the Mountains".',
        'আমি হিমালয়ের পাথুরে ভূমিতে নিখুঁতভাবে ছদ্মবেশে থাকি। / I am perfectly camouflaged in the rocky Himalayas.',
        'আমি গর্জন করতে পারি না, তবে হিস্ হিস্ ও গর্গর্ শব্দ করতে পারি। / I cannot roar, but I can hiss and growl.',
      ],
      'options': ['তুষার চিতা (Snow Leopard)', 'মেঘলা চিতা (Clouded Leopard)', 'পুমা (Puma)', 'জাগুয়ার (Jaguar)'],
      'answer': 'তুষার চিতা (Snow Leopard)',
    },
    {
      'hints': [
        'আমি সিকিমের রাজ্য প্রাণী। / I am the state animal of Sikkim.',
        'আমি বেশিরভাগ সময় গাছে বাঁশ খেয়ে কাটাই। / I spend most of my time in trees eating bamboo.',
        'আমার লম্বা, ঝোপালো, বলয়যুক্ত লেজ আছে। / I have a long, bushy, ringed tail.',
      ],
      'options': ['লাল পাণ্ডা (Red Panda)', 'পাণ্ডা (Giant Panda)', 'কোয়ালা (Koala)', 'লেমুর (Lemur)'],
      'answer': 'লাল পাণ্ডা (Red Panda)',
    },
    {
      'hints': [
        'আমার ঠোঁটের উপরে শিং-সদৃশ একটি গঠন আছে। / I have a horn-like casque on top of my bill.',
        'আমি বর্ষারণ্যের বীজ ছড়িয়ে দেওয়ার গুরুত্বপূর্ণ কাজ করি। / I play a vital role in dispersing rainforest seeds.',
        'আমি কেরালা ও অরুণাচল প্রদেশের রাজ্য পাখি। / I am the state bird of Kerala and Arunachal Pradesh.',
      ],
      'options': ['ধনেশ (Great Hornbill)', 'কালো-সাদা ধনেশ (Malabar Pied Hornbill)', 'ধূসর ধনেশ (Grey Hornbill)', 'টুকান (Toucan)'],
      'answer': 'ধনেশ (Great Hornbill)',
    },
    {
      'hints': [
        'আমি পৃথিবীর সকল বন্য গবাদি পশুর মধ্যে সবচেয়ে বড়। / I am the largest of all wild cattle in the world.',
        'আমার বিশাল শিং এবং পায়ে সাদা "মোজা" আছে। / I have massive horns and white "socks" on my legs.',
        'আমি মধ্য ভারতের বনে বড় পালে পাওয়া যাই। / I am found in large herds in Central Indian forests.',
      ],
      'options': ['গৌর/ইন্ডিয়ান বাইসন (Gaur)', 'বন মহিষ (Wild Buffalo)', 'চমরী গাই (Yak)', 'নীলগাই (Nilgai)'],
      'answer': 'গৌর/ইন্ডিয়ান বাইসন (Gaur)',
    },
    {
      'hints': [
        'আমি "কোবরাদের রাজা" নামে পরিচিত একটি বিষধর সাপ। / I am a venomous snake known as the "King of Cobras".',
        'আমিই পৃথিবীর একমাত্র সাপ যে বাসা তৈরি করি। / I am the only snake in the world that builds nests.',
        'আমি মূলত অন্যান্য সাপ শিকার করে খাই। / I feed primarily on other snakes.',
      ],
      'options': ['রাজগোখরো (King Cobra)', 'গোখরো (Spectacled Cobra)', 'কেউটে (Monocled Cobra)', 'অজগর (Python)'],
      'answer': 'রাজগোখরো (King Cobra)',
    },
    {
      'hints': [
        'আমি ভারতের জাতীয় পাখি। / I am India\'s national bird.',
        'পুরুষের রঙিন, ঝলমলে লেজ পেখম মেলে নাচার জন্য বিখ্যাত। / The male is famous for its colourful, shimmering fanned tail dance.',
        'বর্ষাকালে আমার ডাক প্রায়ই শোনা যায়। / My call is often heard during the monsoon.',
      ],
      'options': ['ময়ূর (Indian Peafowl)', 'তিতির (Pheasant)', 'মোরগ (Junglefowl)', 'সারস (Crane)'],
      'answer': 'ময়ূর (Indian Peafowl)',
    },
    {
      'hints': [
        'আমি সিংহের একটি উপ-প্রজাতি, শুধু ভারতে বন্য অবস্থায় পাওয়া যাই। / I am a subspecies of lion found wild only in India.',
        'আমি গুজরাটের গির অরণ্যে বাস করি। / I live in the Gir forest of Gujarat.',
        'পুরুষদের কেশর আফ্রিকান সিংহের তুলনায় ছোট। / The males have a shorter mane than African lions.',
      ],
      'options': ['এশিয়াটিক সিংহ (Asiatic Lion)', 'বাঘ (Tiger)', 'চিতা (Leopard)', 'জাগুয়ার (Jaguar)'],
      'answer': 'এশিয়াটিক সিংহ (Asiatic Lion)',
    },
    {
      'hints': [
        'আমি সাধারণত পালবদ্ধভাবে ঘাসভূমিতে শিকার করি। / I typically hunt in packs across grasslands.',
        'আমি ভারতের সবচেয়ে বিপন্ন বড় স্তন্যপায়ী প্রাণীদের একটি। / I am one of India\'s most endangered large mammals.',
        'আমি কুকুরের মতো দেখতে, কিন্তু গৃহপালিত নই। / I look dog-like, but I am not domesticated.',
      ],
      'options': ['নেকড়ে (Indian Wolf)', 'শেয়াল (Jackal)', 'ঢোল (Dhole)', 'কুকুর (Dog)'],
      'answer': 'নেকড়ে (Indian Wolf)',
    },
    {
      'hints': [
        'আমি ভারতের জাতীয় জলজ প্রাণী। / I am India\'s National Aquatic Animal.',
        'আমি গঙ্গা ও ব্রহ্মপুত্র নদীতে বাস করি এবং প্রায় অন্ধ। / I live in the Ganges and Brahmaputra rivers and am nearly blind.',
        'আমি শব্দ-তরঙ্গ ব্যবহার করে শিকার খুঁজি। / I use sound waves to find my prey.',
      ],
      'options': ['গাঙ্গেয় শুশুক (Ganges River Dolphin)', 'ইরাবতী ডলফিন (Irrawaddy Dolphin)', 'ডুগং (Dugong)', 'তিমি (Whale)'],
      'answer': 'গাঙ্গেয় শুশুক (Ganges River Dolphin)',
    },
    {
      'hints': [
        'আমার খোলসের উপর তারার মতো হলুদ নকশা আছে। / My shell has star-like yellow patterns.',
        'আমি একটি স্থলচর কচ্ছপ, জলজ নই। / I am a land tortoise, not aquatic.',
        'আমি ভারত ও শ্রীলঙ্কার শুষ্ক ঝোপঝাড় অঞ্চলে পাওয়া যাই। / I am found in the dry scrublands of India and Sri Lanka.',
      ],
      'options': ['ভারতীয় তারা কচ্ছপ (Indian Star Tortoise)', 'ব্যাটাগুর কচ্ছপ (Batagur)', 'কাছিম (Terrapin)', 'অলিভ রিডলি (Olive Ridley)'],
      'answer': 'ভারতীয় তারা কচ্ছপ (Indian Star Tortoise)',
    },
    {
      'hints': [
        'আমি পৃথিবীর সবচেয়ে বড় কাঠবিড়ালিদের একজন। / I am one of the largest squirrels in the world.',
        'আমার গায়ে লাল, বেগুনি ও কালোর মতো একাধিক উজ্জ্বল রঙ থাকে। / My coat has multiple bright colours like maroon, purple and black.',
        'আমি মহারাষ্ট্রের রাজ্য প্রাণী। / I am the state animal of Maharashtra.',
      ],
      'options': ['মালাবার জায়ান্ট কাঠবিড়ালি (Malabar Giant Squirrel)', 'উড়ন্ত কাঠবিড়ালি (Flying Squirrel)', 'পাম কাঠবিড়ালি (Palm Squirrel)', 'চিপমাঙ্ক (Chipmunk)'],
      'answer': 'মালাবার জায়ান্ট কাঠবিড়ালি (Malabar Giant Squirrel)',
    },
    {
      'hints': [
        'আমি পৃথিবীর সবচেয়ে লম্বা উড়ন্ত পাখি। / I am the tallest flying bird in the world.',
        'আমি উত্তরপ্রদেশের রাজ্য পাখি এবং আজীবন একই সঙ্গীর সাথে থাকি। / I am the state bird of Uttar Pradesh and mate for life.',
        'আমার লম্বা লাল পা ও লাল মাথা আছে। / I have long red legs and a red head.',
      ],
      'options': ['সারস ক্রেন (Sarus Crane)', 'বক (Stork)', 'বগা (Egret)', 'সারস পাখি (Heron)'],
      'answer': 'সারস ক্রেন (Sarus Crane)',
    },
  ];

  static const List<String> _allPuzzleSpecies = [
    'Indian Skimmer', 'Great Indian Bustard', 'Bengal Tiger', 'Red Panda', 'Snow Leopard',
    'Asian Elephant', 'One-horned Rhinoceros', 'Himalayan Monal', 'Batagur baska', 'Gharial',
    'Great Hornbill', 'Indian Pangolin', 'Barasingha', 'Indian Peafowl', 'Sloth Bear',
    'Indian Wolf', 'Striped Hyena', 'Sambar Deer', 'Nilgai', 'King Cobra',
  ];

  static List<WordPuzzleItem> _buildWordPuzzles() {
    const raw = <List<String>>[
      ['Little Cormorant', 'পানকৌড়ি'], ['Cattle Egret', 'গোবক'],
      ['Little Egret', 'ছোট বগা'], ['Medium Egret', 'মাঝলা বগা'],
      ['Great Egret', 'বড় বক'], ['Indian Pond Heron', 'কোঁচ বক'],
      ['Purple Heron', 'বেগুনী বক'], ['Wooly-necked Stork', 'মানিকজোর'],
      ['Asian Openbill', 'শামুকখোল'], ['Greater Adjutant', 'হাড়গিলে'],
      ['Lesser Adjutant', 'মদন টাক'], ['Black-headed Ibis', 'সাদা কাস্তেচরা'],
      ['Glossy Ibis', 'খয়রা কাস্তেচরা'],
      ['Lesser Whistling-duck', 'ছোট সরাল'], ['Ruddy Shelduck', 'চখাচখি'],
      ['Bar-headed Goose', 'বরি হাঁস'], ['Mallard', 'নীল শির'],
      ['Spot-billed Duck', 'মেটে হাঁস'], ['Northern Pintail', 'বড়দিঘর'],
      ['Garganey', 'গিরিয়া'], ['Cotton Pygmy-goose', 'বালি হাঁস'],
      ['Common Pochard', 'রাঙ্গামুড়ি'], ['Red-crested Pochard', 'বড় রাঙ্গামুড়ি'],
      ['Little Grebe', 'পানডুবি'],
      ['Black Drongo', 'ফিঙ্গে'], ['Ashy Drongo', 'নীল ফিঙ্গে'],
      ['Greater Racket-tailed Drongo', 'ভীমরাজ'], ['Brown Shrike', 'কাজল পাখি'],
      ['Long-tailed Shrike', 'মেটে লাটোরা'], ['Brahminy Starling', 'বামুন শালিখ'],
      ['Asian Pied Starling', 'গো শালিখ'], ['Bank Myna', 'গাঙ শালিখ'],
      ['Common Myna', 'শালিখ'], ['Jungle Myna', 'ঝুট শালিখ'],
      ['Chestnut-tailed Starling', 'কাঠ শালিক'],
      ['Rufous Treepie', 'হাড়ি চাচা'], ['House Crow', 'পাতি কাক'],
      ['Large-billed Crow', 'দাঁড় কাক'], ['Eurasian Collared Dove', 'কন্ঠী ঘুঘু'],
      ['Spotted Dove', 'তিলা ঘুঘু'], ['Yellow-footed Green Pigeon', 'হরিয়াল'],
      ['Rock Pigeon', 'গোলা পায়রা'], ['Alexandrine Parakeet', 'চন্দনা'],
      ['Rose-ringed Parakeet', 'টিয়া'], ['Indian Cuckoo', 'বৌ কথা কও'],
      ['Common Hawk Cuckoo', 'পাপিয়া'], ['Asian Koel', 'কোকিল'],
      ['Greater Coucal', 'কুবো'],
      ['Brown Fish Owl', 'ভুতুম পেঁচা'], ['Barn Owl', 'লক্ষী পেঁচা'],
      ['Asian Palm Swift', 'তাল চড়াই'], ['Indian Roller', 'নীলকণ্ঠ'],
      ['Pied Kingfisher', 'ফটকা'], ['Common Kingfisher', 'মাছরাঙা'],
      ['White-throated Kingfisher', 'সাদাবুক মাছরাঙা'], ['Stork-billed Kingfisher', 'গুরিয়াল'],
      ['Green Bee-eater', 'বাঁশপাতি'], ['Blue-throated Barbet', 'ভগীরথ'],
      ['Coppersmith Barbet', 'বসন্তবৌরি'], ['Lineated Barbet', 'দাগি বসন্ত'],
      ['Common Hoopoe', 'মোহনচূড়া'], ['Great Hornbill', 'ধনেশ'],
      ['Black-rumped Flameback', 'সুবর্ণ কাঠঠোকরা'], ['Common Iora', 'ফটিকজল'],
      ['Asian Fairy Bluebird', 'নীলপরী'], ['Blue-winged Leafbird', 'হরবোলা'],
      ['Eurasian Golden Oriole', 'হলদে বসন্ত'], ['Black-hooded Oriole', 'বেনেবৌ'],
      ['Oriental Skylark', 'ভরতপাখি'], ['Singing Bushlark', 'আগগিন'],
      ['Indian Bushlark', 'জংলি আগগিন'], ['Bengal Bushlark', 'পাহাড়ি আগগিন'],
      ['Ashy-crowned Sparrow Lark', 'ধুলাচাটা'], ['Barn Swallow', 'আবাবিল'],
      ['Red-vented Bulbul', 'বুলবুলি'], ['Red-whiskered Bulbul', 'সিপাহি বুলবুলি'],
      ['White-browed Bulbul', 'শ্বেতভ্রু বুলবুল'], ['Jungle Babbler', 'ছাতারে'],
      ['Common Babbler', 'মেঠো ছাতারে'], ['Yellow-eyed Babbler', 'গুলাবচশম'],
      ['Red-throated Flycatcher', 'চুটকি'], ['Mangrove Whistler', 'গরানপাখি'],
      ['Verditer Flycatcher', 'নীল কটকটীয়া'], ['Blue-throated Flycatcher', 'নীলটুনি'],
      ['Asian Paradise-flycatcher', 'দুধরাজ'], ['White-throated Fantail', 'চাক দোয়েল'],
      ['White-browed Fantail', 'পুলকপাখি'], ['Plain Prinia', 'ফুটকি'],
      ['Zitting Cisticola', 'ছোট ফুটকি'], ['Clamorous Reed-Warbler', 'টিকরা'],
      ['Common Tailorbird', 'টুনটুনি'],
      ['Oriental Magpie Robin', 'দোয়েল'], ['Indian Robin', 'কালি শ্যামা'],
      ['Bluethroat', 'গুপিকণ্ঠ'], ['Siberian Stonechat', 'পাতি শিলাফিদ্দা'],
      ['Orange-headed Thrush', 'দামা'], ['Great Tit', 'রামগাঙরা'],
      ['Paddyfield Pipit', 'তুলিকা'], ['Tawny Pipit', 'বেলে তুলিকা'],
      ['Tree Pipit', 'গেছো তুলিকা'], ['Yellow Wagtail', 'হলদে খনজন'],
      ['White Wagtail', 'খনজন'], ['Citrine Wagtail', 'হলদে মাথা খনজন'],
      ['Forest Wagtail', 'জংলি খনজন'],
      ['Oriental White-eye', 'চশমাটুনি'], ['Purple-rumped Sunbird', 'মৌটুসী'],
      ['Purple Sunbird', 'দূর্গা টুনটুনি'], ['Pale-billed Flowerpecker', 'পরাগপাখি'],
      ['Thick-billed Flowerpecker', 'মোটাচঞ্চু পরাগপাখি'], ['Fire-breasted Flowerpecker', 'লালবুক পরাগপাখি'],
      ['Red Avadavat', 'লাল মুনিয়া'], ['Indian Silverbill', 'সর মুনিয়া'],
      ['Scaly-breasted Munia', 'তেলি মুনিয়া'], ['Black-headed Munia', 'শ্যামসুন্দর'],
      ['House Sparrow', 'চড়াই'], ['Baya Weaver', 'বাবুই'],
      ['Black-winged Kite', 'কাপাসি'], ['Brahminy Kite', 'শঙ্খচিল'],
      ['Black Kite', 'চিল'], ['Shikra', 'শিকরা বাজ'],
      ['Oriental Honey Buzzard', 'মধু বাজ'],
      ['Slaty-breasted Rail', 'মেটেবুক ঝিল্লি'], ['Brown Crake', 'খয়রা ঝিল্লি'],
      ['Baillon\'s Crake', 'ছোট খেনী'], ['Ruddy-breasted Crake', 'লালবুক গুরগুরি'],
      ['White-breasted Waterhen', 'ডাহুক'],
      ['Bronze-winged Jacana', 'জলপিপি'], ['Pheasant-tailed Jacana', 'জলময়ূর'],
      ['Wood Sandpiper', 'বন বাটান'], ['Common Sandpiper', 'পাতি বাটান'],
      ['Common Snipe', 'কাদাখোঁচা'],
    ];

    return raw.map((pair) => WordPuzzleItem.fromBengali(pair[0], pair[1])).toList();
  }
}