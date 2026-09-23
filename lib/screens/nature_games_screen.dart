import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../widgets/keyboard_press_effect.dart';

// ============================================================================
// eআরণ্যক — Nature Games
// -----------------------------------------------------------------------------
// IMPORTANT:
//   Game question content is NOT hardcoded in this file.
//   The permanent game bank lives in Supabase table: game_questions.
//   weekly_game_data is retained only as a compatibility fallback for older
//   deployments; it is never used as the primary question bank.
// ============================================================================

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
      species: firstString(const ['species', 'common_name', 'commonName', 'name']) ?? fallbackSpecies,
      scientificName: firstString(const ['scientific_name', 'scientificName', 'latin_name']),
      imageUrl: firstString(const ['image_url', 'imageUrl', 'photo_url', 'photoUrl']),
      audioUrl: firstString(const ['audio_url', 'audioUrl', 'recording_url', 'recordingUrl']),
      source: firstString(const ['source', 'provider', 'source_name']) ?? fallbackSource,
      attribution: firstString(const ['attribution', 'credit', 'author', 'recordist']),
    );
  }
}

class WildlifeMediaService {
  static const String _iNaturalistBase = 'https://api.inaturalist.org/v1/taxa';
  static final Map<String, WildlifeMedia?> _photoCache = {};
  static final Map<String, WildlifeMedia?> _audioCache = {};

  static Future<WildlifeMedia?> fetchSpeciesPhoto(String species) async {
    if (_photoCache.containsKey(species)) return _photoCache[species];
    try {
      // Exact-name search is preferred. We additionally ask for an animal
      // taxon so a similarly named plant/organism is not selected.
      final uri = Uri.parse(
        '$_iNaturalistBase?q=${Uri.encodeComponent(species)}&rank=species&per_page=5',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null) {
          for (final raw in results) {
            if (raw is! Map) continue;
            final taxon = Map<String, dynamic>.from(raw);
            final name = (taxon['name'] ?? '').toString();
            final preferred = (taxon['preferred_common_name'] ?? '').toString();
            if (!_sameName(species, name) && !_sameName(species, preferred)) continue;
            final photo = taxon['default_photo'];
            if (photo is Map) {
              var url = (photo['medium_url'] ?? photo['url'])?.toString();
              if (url != null && url.isNotEmpty) {
                url = url.replaceAll('square', 'medium');
                final media = WildlifeMedia(
                  species: species,
                  scientificName: name.isEmpty ? null : name,
                  imageUrl: url,
                  source: 'iNaturalist',
                  attribution: photo['attribution']?.toString(),
                );
                _photoCache[species] = media;
                return media;
              }
            }
          }
        }
      }
    } catch (_) {}
    _photoCache[species] = null;
    return null;
  }

  static bool _sameName(String a, String b) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return norm(a) == norm(b);
  }

  static Future<WildlifeMedia?> fetchBirdCall(String species) async {
    if (_audioCache.containsKey(species)) return _audioCache[species];
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'generator': 'search',
        'gsrnamespace': '6',
        'gsrlimit': '20',
        'gsrsearch': '"$species" filetype:audio',
        'prop': 'imageinfo',
        'iiprop': 'url|mime',
      });
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 7));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final pages = decoded['query']?['pages'];
        if (pages is Map) {
          for (final page in pages.values) {
            final info = page['imageinfo']?.first;
            if (info == null) continue;
            final url = info['url']?.toString() ?? '';
            final mime = info['mime']?.toString() ?? '';
            if (url.isNotEmpty && mime.startsWith('audio/')) {
              final media = WildlifeMedia(
                species: species,
                audioUrl: url,
                source: 'Wikimedia Commons',
              );
              _audioCache[species] = media;
              return media;
            }
          }
        }
      }
    } catch (_) {}
    _audioCache[species] = null;
    return null;
  }
}

class WildlifeGameSpecies {
  final String english;
  final String bengali;
  final String question;
  final String? imageUrl;
  final String? audioUrl;
  final String? hint;
  final String? attribution;

  const WildlifeGameSpecies({
    required this.english,
    required this.bengali,
    required this.question,
    this.imageUrl,
    this.audioUrl,
    this.hint,
    this.attribution,
  });

  String get label => bengali.trim().isEmpty ? english : '$bengali ($english)';
}

class WordPuzzleItem {
  final String english;
  final String bengali;
  final List<String> syllables;
  final String? hint;
  final String? imageUrl;

  const WordPuzzleItem({
    required this.english,
    required this.bengali,
    required this.syllables,
    this.hint,
    this.imageUrl,
  });
}

class GameQuestion {
  final String id;
  final String category;
  final String english;
  final String bengali;
  final String question;
  final List<String> options;
  final String? answer;
  final List<String> hints;
  final String? imageUrl;
  final String? audioUrl;
  final String? imageSource;
  final String? audioSource;
  final String? attribution;
  final String? bengaliWord;
  final List<String> syllables;

  const GameQuestion({
    required this.id,
    required this.category,
    required this.english,
    required this.bengali,
    required this.question,
    required this.options,
    this.answer,
    this.hints = const [],
    this.imageUrl,
    this.audioUrl,
    this.imageSource,
    this.audioSource,
    this.attribution,
    this.bengaliWord,
    this.syllables = const [],
  });

  String get label => bengali.trim().isEmpty ? english : '$bengali ($english)';

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static List<String> _strings(dynamic value) {
    if (value is List) {
      return value.map(_string).where((x) => x.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.map(_string).where((x) => x.isNotEmpty).toList();
      } catch (_) {}
      return value
          .split(RegExp(r'\s*[|;,]\s*'))
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
    }
    return const [];
  }

  factory GameQuestion.fromRow(Map<String, dynamic> raw) {
    // Some versions of the bank store the actual object under payload/data.
    final nested = raw['payload'] is Map
        ? Map<String, dynamic>.from(raw['payload'] as Map)
        : raw['data'] is Map
            ? Map<String, dynamic>.from(raw['data'] as Map)
            : <String, dynamic>{};

    final m = <String, dynamic>{...nested, ...raw};
    final category = _string(m['category']).toLowerCase();
    final english = _string(
      m['english'] ?? m['species'] ?? m['common_name'] ?? m['commonName'] ?? m['name'] ?? m['title'],
    );
    final bengali = _string(
      m['bengali'] ?? m['bengali_name'] ?? m['bengaliName'] ?? m['bn_name'] ?? m['name_bn'],
    );
    final question = _string(m['question'] ?? m['prompt'] ?? m['question_text']);
    final options = _strings(m['options'] ?? m['choices']);
    final answer = _string(m['answer'] ?? m['correct_answer'] ?? m['correctAnswer']);
    final hints = _strings(m['hints'] ?? m['hint']);
    final imageUrl = _string(m['image_url'] ?? m['imageUrl'] ?? m['photo_url']);
    final audioUrl = _string(m['audio_url'] ?? m['audioUrl'] ?? m['recording_url']);
    final imageSource = _string(m['image_source'] ?? m['imageSource']);
    final audioSource = _string(m['audio_source'] ?? m['audioSource']);
    final attribution = _string(m['attribution'] ?? m['credit'] ?? m['author'] ?? m['source']);
    final bengaliWord = _string(m['bengali_word'] ?? m['bengaliWord'] ?? m['word_bn'] ?? bengali);
    var syllables = _strings(m['syllables'] ?? m['tiles'] ?? m['letters']);

    // If the bank contains a Bengali word but no precomputed tiles, split it
    // into Bengali grapheme clusters rather than individual Unicode codepoints.
    if (syllables.isEmpty && bengaliWord.isNotEmpty) {
      syllables = BengaliGrapheme.split(bengaliWord);
    }

    return GameQuestion(
      id: _string(m['id']).isEmpty ? '${category}_${english}_$bengali' : _string(m['id']),
      category: category,
      english: english,
      bengali: bengali,
      question: question,
      options: options,
      answer: answer.isEmpty ? null : answer,
      hints: hints,
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      audioUrl: audioUrl.isEmpty ? null : audioUrl,
      imageSource: imageSource.isEmpty ? null : imageSource,
      audioSource: audioSource.isEmpty ? null : audioSource,
      attribution: attribution.isEmpty ? null : attribution,
      bengaliWord: bengaliWord.isEmpty ? null : bengaliWord,
      syllables: syllables,
    );
  }
}

class BengaliGrapheme {
  // Bengali consonant + dependent vowel/sign + virama/hasant and related marks.
  static final RegExp _cluster = RegExp(
    r'[\u0980-\u09FF](?:[\u0981-\u0983\u09BC\u09BE-\u09CD\u09D7\u09E2-\u09E3\u200C\u200D]*)(?:[\u0980-\u09FF](?:[\u0981-\u0983\u09BC\u09BE-\u09CD\u09D7\u09E2-\u09E3\u200C\u200D]*)*)?',
  );

  static List<String> split(String input) {
    final compact = input.replaceAll(RegExp(r'\s+'), '').trim();
    if (compact.isEmpty) return const [];
    final matches = _cluster.allMatches(compact).map((m) => m.group(0)!).toList();
    if (matches.isEmpty) return [compact];
    return matches;
  }
}

class WildlifeGameData {
  static const int startingQuestionsPerCategory = 20;
  static const Set<String> supportedCategories = {'photo', 'audio', 'hint', 'scramble', 'word'};

  static final Map<String, List<GameQuestion>> _bank = {
    for (final category in supportedCategories) category: <GameQuestion>[],
  };
  static bool loaded = false;
  static String? lastError;

  static List<GameQuestion> get(String category) => List.unmodifiable(_bank[category] ?? const []);

  static Future<void> loadGameBank() async {
    lastError = null;
    try {
      // The app must play the current weekly selection, not the entire active
      // bank. The permanent bank remains in game_questions; weekly_challenges
      // decides which questions are playable this week.
      final weeklyResponse = await supabase
          .from('weekly_challenges')
          .select('week_start,category,question_ids')
          .order('week_start', ascending: false)
          .limit(5);

      final weeklyRows = (weeklyResponse as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final latestWeek = weeklyRows
          .map((row) => row['week_start']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .fold<String>('', (current, value) => value.compareTo(current) > 0 ? value : current);

      if (latestWeek.isEmpty) {
        throw Exception('No current weekly game challenge is available.');
      }

      final idsByCategory = <String, List<String>>{};
      for (final row in weeklyRows.where((row) => row['week_start']?.toString() == latestWeek)) {
        final category = row['category']?.toString().toLowerCase() ?? '';
        final ids = row['question_ids'];
        if (!supportedCategories.contains(category) || ids is! List) continue;
        idsByCategory[category] = ids
            .map((id) => id.toString())
            .where((id) => id.isNotEmpty)
            .toList();
      }

      final allIds = idsByCategory.values.expand((ids) => ids).toSet().toList();
      if (allIds.isEmpty) {
        throw Exception('The current weekly challenge contains no question IDs.');
      }

      final response = await supabase
          .from('game_questions')
          .select()
          .inFilter('id', allIds)
          .eq('active', true);

      final questionMap = <String, GameQuestion>{};
      for (final raw in (response as List).whereType<Map>()) {
        final q = GameQuestion.fromRow(Map<String, dynamic>.from(raw));
        if (q.id.isNotEmpty && q.english.isNotEmpty) {
          questionMap[q.id] = q;
        }
      }

      for (final category in supportedCategories) {
        final seen = <String>{};
        final seenAnswers = <String>{};
        final orderedIds = idsByCategory[category] ?? const <String>[];
        _bank[category] = orderedIds
            .map((id) => questionMap[id])
            .whereType<GameQuestion>()
            .where((q) {
              // Bengali Bird Puzzle must never repeat the same Bengali answer
              // within a weekly set, even if two species share an alias.
              if (category == 'word') {
                final key = (q.bengaliWord ?? q.bengali)
                    .replaceAll(RegExp(r'\s+'), '')
                    .toLowerCase();
                return key.isNotEmpty && seenAnswers.add(key);
              }
              return seen.add(q.id);
            })
            .toList();
      }

      final missing = allIds.where((id) => !questionMap.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        lastError = 'Some weekly game questions are missing or inactive (${missing.length}).';
      }

      final emptyCategories = supportedCategories
          .where((category) => (_bank[category]?.isNotEmpty ?? false) == false)
          .toList();
      if (emptyCategories.isNotEmpty) {
        throw Exception('No playable questions for: ${emptyCategories.join(', ')}');
      }

      loaded = true;
    } catch (e) {
      // Legacy compatibility only. We do not hardcode game content here.
      try {
        final response = await supabase
            .from('game_questions')
            .select()
            .eq('active', true)
            .order('created_at', ascending: false);
        final parsed = (response as List)
            .whereType<Map>()
            .map((row) => GameQuestion.fromRow(Map<String, dynamic>.from(row)))
            .where((q) => supportedCategories.contains(q.category) && q.english.isNotEmpty)
            .toList();
        for (final category in supportedCategories) {
          _bank[category] = parsed.where((q) => q.category == category).take(startingQuestionsPerCategory).toList();
        }
        loaded = true;
        lastError = 'Weekly game data could not be loaded; temporary active-bank fallback used: $e';
      } catch (legacyError) {
        loaded = false;
        lastError = 'Unable to load game bank: $e; fallback read: $legacyError';
        rethrow;
      }
    }
  }
}

// ============================================================================
// MAIN GAMES SCREEN
// ============================================================================

class NatureGamesScreen extends StatefulWidget {
  const NatureGamesScreen({super.key});

  @override
  State<NatureGamesScreen> createState() => NatureGamesScreenState();
}

class NatureGamesScreenState extends State<NatureGamesScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await WildlifeGameData.loadGameBank();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = WildlifeGameData.lastError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
  }

  void _startQuiz(BuildContext context, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WildlifeQuizGame(type: type)),
    );
  }

  void _startScramble(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ScrambledImageGame()));
  }

  void _startWordPuzzle(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WordPuzzleGame()));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
            )
          else ...[
            if (_error != null && _error!.isNotEmpty) _buildWarning(_error!),
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFF00E676), size: 18),
                SizedBox(width: 8),
                Text('Choose a challenge', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                SizedBox(width: 7),
                Text('(একটি খেলা বেছে নিন)', style: TextStyle(color: Color(0xFF81C784), fontSize: 10)),
              ],
            ),
            const SizedBox(height: 11),
            _buildCards(context),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.school_rounded, color: Color(0xFF81C784), size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('প্রতিটি খেলায় প্রকৃতির সঙ্গে একটু পরিচয়, একটু আনন্দ।', style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.35))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF214D2A), Color(0xFF102016)]),
          border: Border.all(color: const Color(0x5200E676)),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 9))],
        ),
        child: const Row(
          children: [
            Image(image: AssetImage('assets/images/nature_study_through_games.png'), width: 72, height: 72, fit: BoxFit.contain),
            SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('খেলার ছলে প্রকৃতি পাঠ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 3),
                  Text('Nature Study through Games', style: TextStyle(fontSize: 12, color: Color(0xFF81C784))),
                  SizedBox(height: 8),
                  Text('দেখুন • শুনুন • ভাবুন • চিনুন', style: TextStyle(fontSize: 11, color: Colors.white60)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildWarning(String message) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(.35))),
        child: Text(message, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
      );

  Widget _buildCards(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 700 ? 4 : 2;
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossAxisCount == 4 ? 1.05 : .96,
            children: [
              _buildGameCard(context, 'আলোকচিত্র চেনা', 'Identify from Photos', 'assets/images/identify_image.png', const Color(0xFF2E7D32), 'দেখে চিনুন', () => _startQuiz(context, 'photo')),
              _buildGameCard(context, 'ডাক শুনে চেনা', 'Recognize by Call', 'assets/images/identify_call.png', const Color(0xFF00897B), 'শুনে চিনুন', () => _startQuiz(context, 'audio')),
              _buildGameCard(context, 'ইঙ্গিত বুঝে চেনা', 'Identify from Hints', 'assets/images/identify_clue.png', const Color(0xFF6A1B9A), 'ইঙ্গিত ধরুন', () => _startQuiz(context, 'hint')),
              _buildGameCard(context, 'টুকরো ছবি জোড়া', 'Scrambled Image', 'assets/images/zigshaw_puzzle.png', const Color(0xFFE65100), 'ছবি মিলিয়ে নিন', () => _startScramble(context)),
              _buildGameCard(context, 'শব্দ-জব্দ', 'Bengali Bird Puzzle', 'assets/images/crossword.png', const Color(0xFF1565C0), 'শব্দ সাজান', () => _startWordPuzzle(context)),
            ],
          );
        },
      );

  Widget _buildGameCard(
    BuildContext context,
    String titleBn,
    String titleEn,
    String imageAsset,
    Color color,
    String action,
    VoidCallback onTap,
  ) {
    return KeyboardPressEffect(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(.28), color.withOpacity(.07)],
          ),
          border: Border.all(color: color.withOpacity(.52)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.22),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    color: color.withOpacity(.12),
                    child: Image.asset(
                      imageAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          color: Colors.white70,
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      titleBn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withOpacity(.5),
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                titleEn,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(.24),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  action,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ============================================================================
// QUIZ GAME — photo / audio / hint
// ============================================================================

class WildlifeQuizGame extends StatefulWidget {
  final String type;
  const WildlifeQuizGame({super.key, required this.type});

  @override
  State<WildlifeQuizGame> createState() => _WildlifeQuizGameState();
}

class _WildlifeQuizGameState extends State<WildlifeQuizGame> {
  List<GameQuestion> _questions = [];
  int _currentIndex = 0;
  int _score = 0;
  bool _answered = false;
  bool _loading = true;
  String? _selectedOption;
  WildlifeMedia? _media;
  AudioPlayer? _quizAudioPlayer;
  bool _audioPlaying = false;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _quizAudioPlayer = AudioPlayer()..setPlayerMode(PlayerMode.mediaPlayer);
    _quizAudioPlayer!.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _audioPlaying = false);
    });
    _initQuiz();
  }

  Future<void> _initQuiz() async {
    final pool = WildlifeGameData.get(widget.type).toList()..shuffle();
    _questions = pool.take(WildlifeGameData.startingQuestionsPerCategory).toList();
    _currentIndex = 0;
    _score = 0;
    _answered = false;
    _selectedOption = null;
    _showHint = false;
    if (_questions.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await _loadCurrentMedia();
  }

  Future<void> _loadCurrentMedia() async {
    if (_questions.isEmpty) return;
    final q = _questions[_currentIndex];
    if (mounted) setState(() { _loading = true; _media = null; });

    WildlifeMedia? media;
    if (widget.type == 'hint') {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // The Supabase record is authoritative. Never replace a question's
    // media with a live search result for another species.
    if (widget.type == 'photo' && q.imageUrl != null && q.imageUrl!.trim().isNotEmpty) {
      media = WildlifeMedia(
        species: q.english,
        imageUrl: q.imageUrl,
        source: q.imageSource ?? 'Supabase game bank',
        attribution: q.attribution,
      );
    } else if (widget.type == 'audio' && q.audioUrl != null && q.audioUrl!.trim().isNotEmpty) {
      media = WildlifeMedia(
        species: q.english,
        audioUrl: q.audioUrl,
        source: q.audioSource ?? 'Supabase game bank',
        attribution: q.attribution,
      );
    }

    if (!mounted) return;
    if (media == null || (widget.type == 'photo' && media.imageUrl == null) || (widget.type == 'audio' && media.audioUrl == null)) {
      // Do not silently turn a question into a different species. Remove only
      // this unavailable question and keep its identity intact.
      _questions.removeAt(_currentIndex);
      if (_questions.isEmpty || _currentIndex >= _questions.length) {
        _showFinalScore();
      } else {
        await _loadCurrentMedia();
      }
      return;
    }
    setState(() { _media = media; _loading = false; });
  }

  List<String> _optionsFor(GameQuestion q) {
    final options = q.options
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();

    // Bank validation guarantees four options for these quiz types.
    // Do not manufacture choices from unrelated questions.
    return options.take(4).toList();
  }

  void _handleAnswer(String option) {
    if (_answered || _loading || _questions.isEmpty) return;
    _quizAudioPlayer?.stop();
    final q = _questions[_currentIndex];
    final correct = q.answer?.trim().isNotEmpty == true ? q.answer!.trim() : q.label;
    final isCorrect = option == correct || _sameAnswer(option, q);
    setState(() {
      _selectedOption = option;
      _answered = true;
      _showHint = false;
      if (isCorrect) _score++;
    });
  }

  bool _sameAnswer(String option, GameQuestion q) {
    final normalized = option.toLowerCase().trim();
    return normalized == q.label.toLowerCase().trim() || normalized == q.english.toLowerCase().trim() || normalized == q.bengali.toLowerCase().trim();
  }

  Future<void> _nextQuestion() async {
    await _quizAudioPlayer?.stop();
    if (_currentIndex >= _questions.length - 1) {
      _showFinalScore();
      return;
    }
    setState(() { _currentIndex++; _answered = false; _selectedOption = null; _audioPlaying = false; _showHint = false; });
    await _loadCurrentMedia();
  }

  void _showHintForCurrent() {
    if (_questions.isEmpty || _answered) return;
    setState(() => _showHint = true);
  }

  void _skipQuestion() async {
    await _quizAudioPlayer?.stop();
    if (_currentIndex >= _questions.length - 1) {
      _showFinalScore();
      return;
    }
    setState(() { _currentIndex++; _answered = false; _selectedOption = null; _audioPlaying = false; _showHint = false; });
    await _loadCurrentMedia();
  }

  void _showFinalScore() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('Game Complete!', style: TextStyle(color: Colors.white)),
        content: Text('Your score: $_score / ${_questions.length}', style: const TextStyle(color: Colors.white70)),
        actions: [TextButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: const Text('Back to Games', style: TextStyle(color: Color(0xFF00E676))))],
      ),
    );
  }

  @override
  void dispose() {
    _quizAudioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _questions.isEmpty) {
      return const Scaffold(backgroundColor: Color(0xFF0D1410), body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))));
    }
    if (_questions.isEmpty) {
      return Scaffold(backgroundColor: const Color(0xFF0D1410), appBar: AppBar(title: const Text('Game')), body: const Center(child: Text('No active questions are available.', style: TextStyle(color: Colors.white70))));
    }

    final current = _questions[_currentIndex];
    final options = _optionsFor(current);
    final correct = current.answer?.trim().isNotEmpty == true ? current.answer!.trim() : current.label;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        title: Text(widget.type == 'photo' ? 'PHOTO QUIZ' : widget.type == 'audio' ? 'AUDIO QUIZ' : 'HINT QUIZ'),
        backgroundColor: Colors.transparent,
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('$_score / ${_currentIndex + (_answered ? 1 : 0)}', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold))))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: (_currentIndex + 1) / _questions.length, backgroundColor: Colors.white12, color: const Color(0xFF00E676)),
            const SizedBox(height: 18),
            Text(current.question.isEmpty ? 'চিনে নিন' : current.question, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (widget.type == 'photo') _buildPhotoArea() else if (widget.type == 'audio') _buildAudioArea() else _buildHintArea(current),
            const SizedBox(height: 12),
            if (!_answered) _buildHintButton(current),
            if (_showHint && !_answered) _buildInlineHint(current),
            const SizedBox(height: 14),
            ...options.map((opt) {
              var bg = Colors.white10;
              if (_answered) {
                if (opt == correct || _sameAnswer(opt, current)) bg = Colors.green.shade800;
                else if (opt == _selectedOption) bg = Colors.red.shade900;
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KeyboardPressEffect(
                  onTap: () => _handleAnswer(opt),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 54),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: _answered && (opt == correct || _sameAnswer(opt, current)) ? Border.all(color: Colors.white, width: 2) : null),
                    child: Text(opt, style: const TextStyle(fontSize: 15, color: Colors.white)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            if (_answered)
              KeyboardPressEffect(onTap: _nextQuestion, child: Container(height: 52, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(10)), child: Text(_currentIndex == _questions.length - 1 ? 'Finish (শেষ)' : 'Next (পরবর্তী)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))))
            else
              TextButton(onPressed: _skipQuestion, child: const Text('Skip (এড়িয়ে যান)', style: TextStyle(color: Colors.white54, fontSize: 16))),
          ],
        ),
      ),
    );
  }

  Widget _buildHintButton(GameQuestion q) => Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: _showHintForCurrent,
          icon: const Icon(Icons.lightbulb_outline, size: 18),
          label: const Text('Hint / ইঙ্গিত'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent, side: BorderSide(color: Colors.amberAccent.withOpacity(.45))),
        ),
      );

  Widget _buildInlineHint(GameQuestion q) {
    final text = q.hints.isNotEmpty ? q.hints.first : (q.bengali.isNotEmpty ? 'বাংলা নাম: ${q.bengali}' : 'এই প্রশ্নটির উত্তরটি প্রকৃতি ও প্রাণীটির বৈশিষ্ট্য ভেবে খুঁজুন।');
    return Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber.withOpacity(.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(.3))), child: Text('💡 $text', style: const TextStyle(color: Colors.amberAccent, fontSize: 13, height: 1.35)));
  }

  Widget _buildPhotoArea() {
    if (_loading) return const SizedBox(height: 350, child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))));
    return Container(height: 350, width: double.infinity, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: CachedNetworkImage(imageUrl: _media!.imageUrl!, fit: BoxFit.contain, errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)))));
  }

  Widget _buildAudioArea() {
    if (_loading) return const SizedBox(height: 190, child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))));
    return Container(height: 190, decoration: BoxDecoration(color: const Color(0xFF174D2B), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF00E676).withOpacity(.35))), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(iconSize: 64, color: const Color(0xFF00E676), icon: Icon(_audioPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill), onPressed: () async { if (_audioPlaying) { await _quizAudioPlayer?.pause(); if (mounted) setState(() => _audioPlaying = false); } else { await _quizAudioPlayer?.play(UrlSource(_media!.audioUrl!)); if (mounted) setState(() => _audioPlaying = true); } }), const Text('PLAY BIRD CALL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]));
  }

  Widget _buildHintArea(GameQuestion current) {
    final hints = current.hints;
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1B5E20).withOpacity(.16), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF81C784).withOpacity(.35))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (hints.isNotEmpty) ...hints.take(3).map((h) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('• $h', style: const TextStyle(color: Colors.white70, fontSize: 16))),) else const Text('প্রকৃতির একটি পরিচিত বৈশিষ্ট্য মনে করে উত্তরটি খুঁজুন।', style: TextStyle(color: Colors.white70, fontSize: 16))]));
  }
}

// ============================================================================
// SCRAMBLED IMAGE GAME
// ============================================================================

class ScrambledImageGame extends StatefulWidget {
  const ScrambledImageGame({super.key});

  @override
  State<ScrambledImageGame> createState() => _ScrambledImageGameState();
}

class _ScrambledImageGameState extends State<ScrambledImageGame> {
  GameQuestion? _question;
  WildlifeMedia? _media;
  bool _loading = true;
  bool _submitted = false;
  bool _showHint = false;
  int _moveCount = 0;
  int? _selectedTile;
  List<int> _tiles = [];

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  Future<void> _initGame() async {
    final pool = WildlifeGameData.get('scramble').toList()..shuffle();
    if (pool.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final q = pool.first;
    if (mounted) setState(() { _question = q; _loading = true; _submitted = false; _showHint = false; _moveCount = 0; _selectedTile = null; _tiles = List.generate(9, (i) => i)..shuffle(); });

    final media = q.imageUrl != null && q.imageUrl!.trim().isNotEmpty
        ? WildlifeMedia(
            species: q.english,
            imageUrl: q.imageUrl,
            source: q.imageSource ?? 'Supabase game bank',
            attribution: q.attribution,
          )
        : null;

    if (!mounted) return;
    if (media?.imageUrl == null) {
      // Do not silently change the answer to another species.
      setState(() => _loading = false);
      return;
    }
    setState(() { _media = media; _loading = false; });
  }

  bool get _isSolved => _tiles.length == 9 && List.generate(9, (i) => i).every((i) => _tiles[i] == i);

  void _onTileTap(int index) {
    if (_submitted || _loading) return;
    if (_selectedTile == null) {
      setState(() => _selectedTile = index);
      return;
    }
    final first = _selectedTile!;
    if (first == index) {
      setState(() => _selectedTile = null);
      return;
    }
    setState(() {
      final temp = _tiles[first];
      _tiles[first] = _tiles[index];
      _tiles[index] = temp;
      _selectedTile = null;
      _moveCount++;
    });
  }

  void _submitPuzzle() {
    if (_submitted || _loading || _question == null) return;
    final correct = _isSolved;
    if (correct) setState(() => _submitted = true);
    _showPuzzleResult(correct: correct);
  }

  void _showPuzzleHint() {
    if (_submitted) return;
    setState(() => _showHint = true);
  }

  void _showPuzzleResult({required bool correct}) {
    final q = _question!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: Text(correct ? 'Correct! 🎉' : 'Not quite', style: TextStyle(color: correct ? const Color(0xFF00E676) : Colors.orangeAccent)),
        content: Text(correct ? 'You restored ${q.english} correctly in $_moveCount moves.' : 'Try again. Rearrange the tiles and submit once the picture is complete.', style: const TextStyle(color: Colors.white70)),
        actions: [
          if (correct) TextButton(onPressed: () { Navigator.pop(ctx); _initGame(); }, child: const Text('Next Puzzle', style: TextStyle(color: Color(0xFF00E676)))),
          TextButton(onPressed: () { Navigator.pop(ctx); if (correct) Navigator.pop(context); }, child: Text(correct ? 'Quit' : 'Try Again', style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _question;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(title: const Text('SCRAMBLED IMAGE'), backgroundColor: Colors.transparent),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
          : q == null || _media?.imageUrl == null
              ? const Center(child: Text('No puzzle image is currently available.', style: TextStyle(color: Colors.white70)))
              : SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxBoard = math.min(420.0, math.max(280.0, constraints.maxWidth - 32));
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          children: [
                            Text('Restore the image', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(q.bengali.isNotEmpty ? '${q.bengali} (${q.english})' : q.english, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF81C784), fontSize: 14)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: maxBoard,
                              height: maxBoard,
                              child: Container(
                                decoration: BoxDecoration(border: Border.all(color: const Color(0xFF00E676), width: 2), borderRadius: BorderRadius.circular(12)),
                                clipBehavior: Clip.antiAlias,
                                child: LayoutBuilder(builder: (context, board) {
                                  final piece = board.maxWidth / 3;
                                  return GridView.builder(
                                    physics: const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
                                    itemCount: 9,
                                    itemBuilder: (ctx, idx) {
                                      final originalIndex = _tiles[idx];
                                      final row = originalIndex ~/ 3;
                                      final col = originalIndex % 3;
                                      final selected = _selectedTile == idx;
                                      return GestureDetector(
                                        onTap: () => _onTileTap(idx),
                                        child: Container(
                                          decoration: BoxDecoration(border: Border.all(color: selected ? Colors.amber : Colors.black, width: selected ? 3 : 1)),
                                          child: ClipRect(
                                            child: Stack(children: [Positioned(left: -col * piece, top: -row * piece, width: board.maxWidth, height: board.maxHeight, child: CachedNetworkImage(imageUrl: _media!.imageUrl!, fit: BoxFit.cover))]),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Tap two tiles to swap them • Moves: $_moveCount', style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            if (!_submitted) ...[
                              if (!_showHint)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    onPressed: _showPuzzleHint,
                                    icon: const Icon(Icons.lightbulb_outline, size: 18),
                                    label: const Text('Hint / ইঙ্গিত'),
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent, side: BorderSide(color: Colors.amberAccent.withOpacity(.45))),
                                  ),
                                ),
                              if (_showHint)
                                Container(
                                  width: maxBoard,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.amber.withOpacity(.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(.3))),
                                  child: Text('💡 ${q.hints.isNotEmpty ? q.hints.first : 'ছবির প্রাণীটির বৈশিষ্ট্য খেয়াল করে টাইল সাজান।'}', style: const TextStyle(color: Colors.amberAccent, fontSize: 13, height: 1.35)),
                                ),
                              SizedBox(
                                width: maxBoard,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _submitPuzzle,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('SUBMIT PICTURE / ছবি জমা দিন'),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                ),
                              ),
                            ] else
                              const Text('Submitted', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextButton(onPressed: _initGame, child: const Text('Skip (এড়িয়ে যান)', style: TextStyle(color: Colors.white54))),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================================
// BENGALI BIRD WORD PUZZLE
// ============================================================================

class WordPuzzleGame extends StatefulWidget {
  const WordPuzzleGame({super.key});

  @override
  State<WordPuzzleGame> createState() => _WordPuzzleGameState();
}

class _WordPuzzleGameState extends State<WordPuzzleGame> {
  GameQuestion? _current;
  WildlifeMedia? _media;
  bool _loading = true;
  bool _showHint = false;
  List<String> _slots = [];
  List<bool> _isFixed = [];
  List<String> _availableLetters = [];
  final Set<String> _usedIds = {};

  @override
  void initState() {
    super.initState();
    _loadNextPuzzle();
  }

  static const List<String> _bengaliDistractorLetters = [
    'ক', 'খ', 'গ', 'ঘ', 'চ', 'ছ', 'জ', 'ঝ', 'ট', 'ঠ', 'ড', 'ঢ',
    'ত', 'থ', 'দ', 'ধ', 'ন', 'প', 'ফ', 'ব', 'ভ', 'ম', 'য', 'র', 'ল',
    'শ', 'ষ', 'স', 'হ', 'আ', 'ই', 'উ', 'এ', 'ও', 'অ',
  ];

  List<String> _buildLetterOptions(List<String> needed) {
    final random = math.Random();
    final neededKeys = needed.toSet();
    final distractors = _bengaliDistractorLetters
        .where((letter) => !neededKeys.contains(letter))
        .toList()
      ..shuffle(random);

    // Always provide at least four extra Bengali letters, while keeping the
    // option set manageable on a phone screen. Distractors never replace the
    // actual answer letters.
    final extraCount = math.max(4, math.min(8, needed.length));
    final extras = distractors.take(extraCount).toList();
    return [...needed, ...extras]..shuffle(random);
  }

  Future<void> _loadNextPuzzle() async {
    final pool = WildlifeGameData.get('word').where((q) => !_usedIds.contains(q.id)).toList();
    final source = pool;
    if (source.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    source.shuffle();
    final q = source.first;
    _usedIds.add(q.id);

    if (mounted) setState(() { _current = q; _loading = true; _showHint = false; });

    WildlifeMedia? media;
    if (q.imageUrl != null && q.imageUrl!.trim().isNotEmpty) {
      // Supabase remains authoritative when the exact bird image is already
      // stored with the WORD question.
      media = WildlifeMedia(
        species: q.english,
        imageUrl: q.imageUrl,
        source: q.imageSource ?? 'Supabase game bank',
        attribution: q.attribution,
      );
    } else {
      // Older WORD records may predate image synchronization. Fetch only the
      // exact species name; WildlifeMediaService rejects non-exact taxon names
      // so the image cannot silently belong to another bird.
      media = await WildlifeMediaService.fetchSpeciesPhoto(q.english);
    }

    final syllables = q.syllables.isNotEmpty ? q.syllables : BengaliGrapheme.split(q.bengaliWord ?? q.bengali);
    if (!mounted) return;
    setState(() {
      _media = media;
      _loading = false;
      _slots = List.filled(syllables.length, '');
      _isFixed = List.filled(syllables.length, false);
      final revealCount = syllables.length > 3 ? 1 : 0;
      final revealIndex = syllables.isEmpty ? -1 : math.Random().nextInt(syllables.length);
      if (revealCount > 0 && revealIndex >= 0) {
        _slots[revealIndex] = syllables[revealIndex];
        _isFixed[revealIndex] = true;
      }
      final needed = <String>[];
      for (var i = 0; i < syllables.length; i++) {
        if (!_isFixed[i]) needed.add(syllables[i]);
      }
      _availableLetters = _buildLetterOptions(needed);
    });
  }

  void _onAvailableTap(String letter) {
    final emptyIndex = _slots.indexOf('');
    if (emptyIndex == -1) return;
    setState(() { _slots[emptyIndex] = letter; _availableLetters.remove(letter); });
  }

  void _onSlotTap(int index) {
    if (_slots[index].isNotEmpty && !_isFixed[index]) {
      setState(() { _availableLetters.add(_slots[index]); _slots[index] = ''; });
    }
  }

  void _submitWord() {
    final q = _current;
    if (q == null || _slots.contains('')) return;
    final answer = _slots.join('');
    final correct = (q.bengaliWord ?? q.bengali).replaceAll(RegExp(r'\s+'), '');
    final ok = answer == correct;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: Text(ok ? 'Correct! (সঠিক!)' : 'Try again', style: TextStyle(color: ok ? const Color(0xFF00E676) : Colors.orangeAccent)),
        content: Text(ok ? 'সঠিক উত্তর: ${q.bengali}' : 'শব্দটির অক্ষরগুলি আবার সাজিয়ে চেষ্টা করুন।', style: const TextStyle(color: Colors.white70)),
        actions: [
          if (ok) TextButton(onPressed: () { Navigator.pop(ctx); _loadNextPuzzle(); }, child: const Text('Next Bird', style: TextStyle(color: Color(0xFF00E676)))),
          TextButton(onPressed: () { Navigator.pop(ctx); if (ok) Navigator.pop(context); }, child: Text(ok ? 'Quit' : 'Try Again', style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _current;
    if (_loading) return const Scaffold(backgroundColor: Color(0xFF0D1410), body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))));
    if (q == null) return const Scaffold(backgroundColor: Color(0xFF0D1410), body: Center(child: Text('No Bengali bird puzzles are available.', style: TextStyle(color: Colors.white70))));

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(title: const Text('শব্দ-জব্দ (BIRD PUZZLE)'), backgroundColor: Colors.transparent),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_media?.imageUrl != null)
                Container(
                  height: 230,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black26,
                    border: Border.all(color: const Color(0xFF1565C0).withOpacity(.45)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: _media!.imageUrl!,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                      errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text('পাখিটির বাংলা নামটি সাজান', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(q.english, style: const TextStyle(color: Color(0xFF81C784), fontSize: 14)),
              const SizedBox(height: 12),
              if (!_showHint) OutlinedButton.icon(onPressed: () => setState(() => _showHint = true), icon: const Icon(Icons.lightbulb_outline, size: 18), label: const Text('Hint / ইঙ্গিত'), style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent, side: BorderSide(color: Colors.amberAccent.withOpacity(.4)))),
              if (_showHint) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber.withOpacity(.08), borderRadius: BorderRadius.circular(12)), child: Text(q.hints.isNotEmpty ? '💡 ${q.hints.first}' : '💡 বাংলা নামের প্রথম অক্ষরটি মনে করুন।', style: const TextStyle(color: Colors.amberAccent))),
              const SizedBox(height: 18),
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: List.generate(_slots.length, (index) {
                final fixed = _isFixed[index];
                return GestureDetector(onTap: () => _onSlotTap(index), child: Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: fixed ? const Color(0xFF00E676).withOpacity(.2) : Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: fixed ? const Color(0xFF00E676) : Colors.white30)), child: Text(_slots[index], style: TextStyle(color: fixed ? const Color(0xFF00E676) : Colors.white, fontSize: 18, fontWeight: FontWeight.bold))));
              })),
              const SizedBox(height: 22),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                alignment: WrapAlignment.center,
                children: _availableLetters.map((letter) => KeyboardPressEffect(
                  onTap: () => _onAvailableTap(letter),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: _slots.contains('') ? null : _submitWord, icon: const Icon(Icons.check_circle_outline), label: const Text('SUBMIT / জমা দিন'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black, disabledBackgroundColor: Colors.white12, disabledForegroundColor: Colors.white38, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
              TextButton(onPressed: _loadNextPuzzle, child: const Text('Skip (এড়িয়ে যান)', style: TextStyle(color: Colors.white54))),
            ],
          ),
        ),
      ),
    );
  }
}


class GameDiagramPainter extends CustomPainter {
  final String type;
  final Color color;
  GameDiagramPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    if (type == 'photo') {
      final rrect = RRect.fromLTRBR(w * 0.1, h * 0.25, w * 0.9, h * 0.8, const Radius.circular(10));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, paint);
      canvas.drawCircle(Offset(w * 0.5, h * 0.52), w * 0.22, paint);
      canvas.drawCircle(Offset(w * 0.5, h * 0.52), w * 0.12, paint..strokeWidth = 1.5);
      canvas.drawRect(Rect.fromLTWH(w * 0.7, h * 0.18, w * 0.12, h * 0.07), paint);
    } else if (type == 'hint') {
      final brainPath = Path()
        ..addOval(Rect.fromCircle(center: Offset(w * 0.5, h * 0.38), radius: w * 0.28));
      canvas.drawPath(brainPath, fillPaint);
      canvas.drawPath(brainPath, paint);
      final neckPath = Path()
        ..moveTo(w * 0.25, h * 0.9)
        ..quadraticBezierTo(w * 0.25, h * 0.65, w * 0.5, h * 0.65)
        ..quadraticBezierTo(w * 0.75, h * 0.65, w * 0.75, h * 0.9);
      canvas.drawPath(neckPath, paint);
    } else if (type == 'call') {
      for (int i = 0; i < 4; i++) {
        final radius = w * 0.15 + i * (w * 0.18);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.15, h * 0.5), radius: radius),
          -0.7 * math.pi / 2,
          1.4 * math.pi / 2,
          false,
          paint..strokeWidth = 3.5 - (i * 0.5),
        );
      }
    } else if (type == 'crossword') {
      final rectSize = w * 0.2;
      final startX = w * 0.2;
      final startY = h * 0.2;
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          if ((i == 1) || (j == 1)) {
             final rect = Rect.fromLTWH(startX + j * rectSize, startY + i * rectSize, rectSize, rectSize);
             canvas.drawRect(rect, fillPaint);
             canvas.drawRect(rect, paint);
          }
        }
      }
    } else {
      final piece = Path()
        ..moveTo(w * 0.15, h * 0.25)
        ..lineTo(w * 0.35, h * 0.25)
        ..arcToPoint(Offset(w * 0.55, h * 0.25), radius: Radius.circular(w * 0.1))
        ..lineTo(w * 0.75, h * 0.25)
        ..lineTo(w * 0.75, h * 0.45)
        ..arcToPoint(Offset(w * 0.75, h * 0.65), radius: Radius.circular(w * 0.1), clockwise: false)
        ..lineTo(w * 0.75, h * 0.85)
        ..lineTo(w * 0.15, h * 0.85)
        ..close();
      canvas.drawPath(piece, fillPaint);
      canvas.drawPath(piece, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}