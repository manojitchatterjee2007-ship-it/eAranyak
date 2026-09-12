import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/config.dart';
import '../models/game_data.dart';
import '../widgets/keyboard_press_effect.dart';

class NatureGamesScreen extends StatefulWidget {
  const NatureGamesScreen({super.key});

  @override
  State<NatureGamesScreen> createState() => NatureGamesScreenState();
}

class NatureGamesScreenState extends State<NatureGamesScreen> {
  Map<String, Map<String, dynamic>> _weekly = {};

  @override
  void initState() {
    super.initState();
    _loadWeeklyChallenges();
  }

  void refresh() {
    _loadWeeklyChallenges();
    setState(() {});
  }

  String _currentWeekStart() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadWeeklyChallenges() async {
    try {
      final res = await supabase
          .from('weekly_challenges')
          .select()
          .eq('week_start', _currentWeekStart());
      if (!mounted) return;
      setState(() {
        _weekly = {
          for (final row in res)
            if ((row['category'] ?? '').toString().isNotEmpty)
              (row['category'] as String):
                  Map<String, dynamic>.from(row['payload'] ?? const {}),
        };
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _startQuiz(BuildContext context, String type) {
    List<String>? species;
    List<Map<String, dynamic>>? hints;
    int seed = 0;

    final challenge = _weekly[type];
    if (challenge != null) {
      final rawSpecies = challenge['species'];
      if (rawSpecies is List) {
        species = rawSpecies.map((e) => e.toString()).toList();
      }
      final rawHints = challenge['hints'];
      if (rawHints is List) {
        hints = rawHints
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      seed = int.tryParse(challenge['seed']?.toString() ?? '0') ?? 0;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WildlifeQuizGame(
          type: type,
          weeklySpecies: species,
          weeklyHintItems: hints,
          weeklySeed: seed,
        ),
      ),
    );
  }

  void _startScramble(BuildContext context) {
    List<String>? species;
    final challenge = _weekly['scramble'];
    if (challenge != null) {
      final rawSpecies = challenge['species'];
      if (rawSpecies is List) {
        species = rawSpecies.map((e) => e.toString()).toList();
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScrambledImageGame(weeklySpecies: species),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF214D2A), Color(0xFF102016)],
              ),
              border: Border.all(
                color: const Color(0x5200E676),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 18,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: const Row(
              children: [
                Image(image: AssetImage('assets/images/nature_study_through_games.png'), width: 72, height: 72, fit: BoxFit.contain),
                SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'খেলার ছলে প্রকৃতি পাঠ',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Nature Study through Games',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF81C784),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'দেখুন • শুনুন • ভাবুন • চিনুন',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFF00E676), size: 18),
              SizedBox(width: 8),
              Text(
                'Choose a challenge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 7),
              Text(
                '(একটি খেলা বেছে নিন)',
                style: TextStyle(
                  color: Color(0xFF81C784),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (_weekly.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 14, bottom: 14),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.45)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emoji_events_rounded,
                      color: Color(0xFF00E676), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'এই সপ্তাহের নতুন চ্যালেঞ্জ লাইভ! (This week\'s challenges are live)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 700 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: crossAxisCount == 4 ? 1.05 : 0.96,
                children: [
                  _buildGameCard(
                    context,
                    'আলোকচিত্র চেনা',
                    'Identify from Photos',
                    'assets/images/identify_image.png',
                    const Color(0xFF2E7D32),
                    'দেখে চিনুন',
                        () => _startQuiz(context, 'photo'),
                  ),
                  _buildGameCard(
                    context,
                    'ডাক শুনে চেনা',
                    'Recognize by Call',
                    'assets/images/identify_call.png',
                    const Color(0xFF00897B),
                    'শুনে চিনুন',
                        () => _startQuiz(context, 'audio'),
                  ),
                  _buildGameCard(
                    context,
                    'ইঙ্গিত বুঝে চেনা',
                    'Identify from Hints',
                    'assets/images/identify_clue.png',
                    const Color(0xFF6A1B9A),
                    'ইঙ্গিত ধরুন',
                        () => _startQuiz(context, 'hint'),
                  ),
                  _buildGameCard(
                    context,
                    'টুকরো ছবি জোড়া',
                    'Scrambled Image',
                    'assets/images/zigshaw_puzzle.png',
                    const Color(0xFFE65100),
                    'ছবি মিলিয়ে নিন',
                        () => _startScramble(context),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.school_rounded, color: Color(0xFF81C784), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'প্রতিটি খেলায় প্রকৃতির সঙ্গে একটু পরিচয়, একটু আনন্দ।',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
            colors: [
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.07),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.52)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
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
              // Flexible image area: absorbs any residual height
              // differences so the card can NEVER overflow at the bottom.
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    color: color.withValues(alpha: 0.12),
                    child: Image.asset(
                      imageAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.image_not_supported_rounded,
                            color: Colors.white70,
                            size: 38,
                          ),
                        );
                      },
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
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                titleEn,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.24),
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

class WildlifeQuizGame extends StatefulWidget {
  final String type;
  final List<String>? weeklySpecies;
  final List<Map<String, dynamic>>? weeklyHintItems;
  final int weeklySeed;

  const WildlifeQuizGame({
    super.key,
    required this.type,
    this.weeklySpecies,
    this.weeklyHintItems,
    this.weeklySeed = 0,
  });

  @override
  State<WildlifeQuizGame> createState() => _WildlifeQuizGameState();
}

class _WildlifeQuizGameState extends State<WildlifeQuizGame> {
  late List<Map<String, dynamic>> _questions;
  int _currentIndex = 0;
  int _score = 0;
  bool _answered = false;
  bool _loading = true;
  String? _selectedOption;
  String? _mediaError;
  WildlifeMedia? _media;
  AudioPlayer? _quizAudioPlayer;
  bool _audioPlaying = false;
  bool _audioLoading = false;

  @override
  void initState() {
    super.initState();

    _quizAudioPlayer = AudioPlayer();
    _quizAudioPlayer!.setPlayerMode(PlayerMode.mediaPlayer);
    _quizAudioPlayer!.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _audioPlaying = false;
        _audioLoading = false;
      });
    });

    _initQuiz();
  }

  Future<void> _initQuiz() async {
    if (widget.type == 'hint') {
      List<Map<String, dynamic>> raw;
      if (widget.weeklyHintItems != null &&
          widget.weeklyHintItems!.isNotEmpty) {
        raw = widget.weeklyHintItems!
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } else {
        raw = WildlifeGameData.hintQuiz
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      raw.shuffle(math.Random(widget.weeklySeed));

      if (!mounted) return;
      setState(() {
        _questions = raw;
        _loading = false;
      });
      return;
    }

    if (widget.type == 'photo' || widget.type == 'audio') {
      final basePool = widget.type == 'audio'
          ? WildlifeGameData.audioSpecies
          : WildlifeGameData.photoSpecies;

      var pool = basePool;
      if (widget.weeklySpecies != null && widget.weeklySpecies!.isNotEmpty) {
        final weekly = basePool
            .where((s) => widget.weeklySpecies!.contains(s.english))
            .toList();
        if (weekly.isNotEmpty) pool = weekly;
      }

      final species = pool.toList()..shuffle(math.Random(widget.weeklySeed));

      _questions = species
          .take(8)
          .map(
            (s) {
          final distractors = basePool
              .where((x) => x.english != s.english)
              .toList()
            ..shuffle(math.Random(widget.weeklySeed + s.english.hashCode));

          return <String, dynamic>{
            'species': s,
            'options': <String>[
              s.label,
              ...distractors.take(3).map((x) => x.label),
            ]..shuffle(),
          };
        },
      )
          .toList();
    }

    await _loadCurrentMedia();
  }

  Future<void> _loadCurrentMedia() async {
    if (_questions.isEmpty) return;

    if (widget.type == 'hint') {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final species =
        (_questions[_currentIndex]['species'] as WildlifeGameSpecies).english;

    if (mounted) {
      await _quizAudioPlayer?.stop();
      if (mounted) {
        setState(() {
          _loading = true;
          _audioPlaying = false;
          _audioLoading = false;
          _media = null;
          _mediaError = null;
          _answered = false;
          _selectedOption = null;
        });
      }
    }

    WildlifeMedia? media;
    if (widget.type == 'photo') {
      media = await WildlifeMediaService.fetchSpeciesPhoto(species);
    } else if (widget.type == 'audio') {
      media = await WildlifeMediaService.fetchBirdCall(species);
    }

    if (!mounted) return;

    if (media == null ||
        (widget.type == 'photo' && media.imageUrl == null) ||
        (widget.type == 'audio' && media.audioUrl == null)) {
      setState(() {
        _loading = false;
        _mediaError = widget.type == 'audio'
            ? 'No suitable bird call was found.\n'
            'উপযুক্ত পাখির ডাক পাওয়া যায়নি।'
            : 'Media for $species is temporarily unavailable.\n'
            'এই প্রজাতির মিডিয়া এই মুহূর্তে পাওয়া যাচ্ছে না।';
      });
      return;
    }

    setState(() {
      _media = media;
      _loading = false;
    });
  }

  void _handleAnswer(String option) {
    if (_answered || _loading || _questions.isEmpty) return;
    _quizAudioPlayer?.stop();
    _audioPlaying = false;
    _audioLoading = false;

    final species = _questions[_currentIndex]['species'];
    final correct = species is WildlifeGameSpecies
        ? species.label
        : _questions[_currentIndex]['answer']?.toString();

    setState(() {
      _selectedOption = option;
      _answered = true;
      if (option == correct) {
        _score++;
      }
    });
  }

  Future<void> _nextQuestion() async {
    if (_currentIndex >= _questions.length - 1) {
      await _showFinalScore();
      return;
    }

    await _quizAudioPlayer?.stop();
    setState(() {
      _currentIndex++;
      _answered = false;
      _selectedOption = null;
      _audioPlaying = false;
      _audioLoading = false;
      _media = null;
      _mediaError = null;
    });

    await _loadCurrentMedia();
  }

  Future<void> _showFinalScore() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('Game Complete! (খেলা শেষ!)'),
        content: Text(
          'Your score: $_score / ${_questions.length}\n'
              'আপনার স্কোর: $_score / ${_questions.length}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text(
              'Back to Games',
              style: TextStyle(color: Color(0xFF00E676)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _quizAudioPlayer?.stop();
    _quizAudioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _questions.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1410),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E676)),
        ),
      );
    }

    final current = _questions[_currentIndex];
    final isHint = widget.type == 'hint';
    final WildlifeGameSpecies? species =
    current['species'] is WildlifeGameSpecies
        ? current['species'] as WildlifeGameSpecies
        : null;

    final String question = isHint
        ? 'Who am I? / আমি কে?'
        : (species?.question ?? 'Identify this species / প্রজাতিটি চিনুন');

    final List<String> options = List<String>.from(current['options'] as List);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        title: Text(
          widget.type == 'photo'
              ? 'IDENTIFY FROM PHOTOS'
              : widget.type == 'audio'
              ? 'RECOGNIZE FROM CALL'
              : 'IDENTIFY FROM HINTS',
        ),
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$_score / ${_currentIndex + (_answered ? 1 : 0)}',
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions.length,
              backgroundColor: Colors.white12,
              color: const Color(0xFF00E676),
            ),
            const SizedBox(height: 22),
            Text(
              question,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            if (widget.type == 'photo')
              _buildPhotoArea()
            else if (widget.type == 'audio')
              _buildAudioArea()
            else
              _buildHintArea(current),
            const SizedBox(height: 22),
            ...options.map(
                  (opt) {
                final correct =
                    species?.label ?? current['answer']?.toString() ?? '';
                final isCorrect = opt == correct;
                final isSelected = opt == _selectedOption;

                Color background = Colors.white10;
                if (_answered) {
                  if (isCorrect) {
                    background = Colors.green.shade800;
                  } else if (isSelected) {
                    background = Colors.red.shade900;
                  }
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KeyboardPressEffect(
                    onTap: () {
                      _handleAnswer(opt);
                    },
                    child: Container(
                      height: 54,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(8),
                        border: _answered && isCorrect
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: Text(
                        opt,
                        style: const TextStyle(
                            fontSize: 15, color: Colors.white),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_answered)
              KeyboardPressEffect(
                onTap: () {
                  _nextQuestion();
                },
                child: Container(
                  height: 52,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _currentIndex == _questions.length - 1
                        ? 'Finish (শেষ করুন)'
                        : 'Next Question (পরবর্তী প্রশ্ন)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioArea() {
    if (_loading || _audioLoading) {
      return Container(
        height: 255,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF164C2A), Color(0xFF0D2115)],
          ),
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.35),
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00E676)),
              SizedBox(height: 14),
              Text(
                'Finding a bird call…\nপাখির ডাক খোঁজা হচ্ছে…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_mediaError != null || _media?.audioUrl == null) {
      return Container(
        height: 255,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFF241916),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.volume_off_rounded,
              color: Colors.orangeAccent,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _mediaError ??
                  'No suitable call was found.\n'
                      'উপযুক্ত পাখির ডাক পাওয়া যায়নি।',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadCurrentMedia,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again / আবার চেষ্টা করুন'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF174D2B), Color(0xFF0B1D12)],
        ),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: _audioPlaying ? 94 : 82,
            height: _audioPlaying ? 94 : 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E676).withValues(
                alpha: _audioPlaying ? 0.22 : 0.12,
              ),
              border: Border.all(
                color: const Color(0xFF00E676).withValues(alpha: 0.65),
                width: 2,
              ),
            ),
            child: Icon(
              _audioPlaying
                  ? Icons.graphic_eq_rounded
                  : Icons.record_voice_over_rounded,
              color: const Color(0xFF00E676),
              size: 42,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Listen carefully',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'মন দিয়ে শুনে পাখিটিকে চিনুন',
            style: TextStyle(color: Color(0xFF9AD6A3), fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(19, (i) {
              final heights = [8, 14, 22, 12, 30, 18, 38, 24, 44, 18,
                34, 16, 42, 23, 31, 14, 25, 12, 8];
              return AnimatedContainer(
                duration: Duration(milliseconds: 160 + i * 8),
                curve: Curves.easeInOut,
                width: 3,
                height: _audioPlaying ? heights[i].toDouble() : 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(
                    alpha: _audioPlaying ? 0.78 : 0.28,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            child: KeyboardPressEffect(
              onTap: () async {
                final player = _quizAudioPlayer;
                final url = _media?.audioUrl;
                if (player == null || url == null || url.isEmpty) return;

                try {
                  if (_audioPlaying) {
                    await player.pause();
                    if (mounted) {
                      setState(() => _audioPlaying = false);
                    }
                    return;
                  }

                  setState(() => _audioLoading = true);
                  await player.stop();
                  await player.setSource(UrlSource(url));
                  await player.resume();

                  if (mounted) {
                    setState(() {
                      _audioLoading = false;
                      _audioPlaying = true;
                    });
                  }
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    _audioLoading = false;
                    _audioPlaying = false;
                    _mediaError =
                    'This call could not be played on this device.\n'
                        'এই ডাকটি এই ডিভাইসে চালানো যাচ্ছে না।';
                  });
                }
              },
              child: Container(
                height: 54,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _audioPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 30,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _audioPlaying
                          ? 'PAUSE CALL (বিরতি দিন)'
                          : 'PLAY BIRD CALL (ডাক শুনুন)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Listen as many times as you need before answering.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 9),
          ),
          const SizedBox(height: 8),
          _buildAttribution(commonsOnly: true),
        ],
      ),
    );
  }

  Widget _buildPhotoArea() {
    if (_loading) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF00E676)),
        ),
      );
    }

    if (_mediaError != null || _media?.imageUrl == null) {
      return _buildMediaError();
    }

    return Column(
      children: [
        Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: _media!.imageUrl!,
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E676)),
              ),
              errorWidget: (context, url, error) => _buildMediaError(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildAttribution(),
      ],
    );
  }

  Widget _buildHintArea(Map<String, dynamic> current) {
    final hints = List<String>.from(current['hints'] as List);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF81C784).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < hints.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: const Color(0xFF2E7D32),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hints[i],
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaError() {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          _mediaError ??
              'Wildlife media unavailable.\nবন্যপ্রাণের মিডিয়া পাওয়া যায়নি।',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60),
        ),
      ),
    );
  }

  Widget _buildAttribution({bool commonsOnly = false}) {
    final media = _media;
    if (media == null) return const SizedBox.shrink();

    // For the call game, only Wikimedia Commons is acknowledged — recordist
    // names, licenses or file pages could leak hints about the bird.
    if (commonsOnly) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Source: Wikimedia Commons',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 9,
          ),
        ),
      );
    }

    final parts = <String>[
      if (media.source.isNotEmpty) 'Source: ${media.source}',
      if (media.attribution != null && media.attribution!.isNotEmpty)
        media.attribution!,
    ];

    if (parts.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        parts.join(' • '),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 9,
        ),
      ),
    );
  }
}

class ScrambledImageGame extends StatefulWidget {
  final List<String>? weeklySpecies;

  const ScrambledImageGame({
    super.key,
    this.weeklySpecies,
  });

  @override
  State<ScrambledImageGame> createState() => _ScrambledImageGameState();
}

class _ScrambledImageGameState extends State<ScrambledImageGame> {
  late String _species;
  WildlifeMedia? _media;
  bool _loading = true;
  String? _error;
  int _moveCount = 0;
  int? _selectedTile;
  List<int> _tiles = List.generate(9, (index) => index);

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  Future<void> _initGame() async {
    final pool = (widget.weeklySpecies != null && widget.weeklySpecies!.isNotEmpty)
        ? widget.weeklySpecies!
        : WildlifeGameData.puzzleSpecies;

    _species = (pool.toList()..shuffle()).first;

    setState(() {
      _loading = true;
      _error = null;
      _moveCount = 0;
      _selectedTile = null;
      _tiles = List.generate(9, (index) => index)..shuffle();
    });

    final media = await WildlifeMediaService.fetchSpeciesPhoto(_species);
    if (!mounted) return;

    if (media == null || media.imageUrl == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load puzzle image for $_species.';
      });
      return;
    }

    setState(() {
      _media = media;
      _loading = false;
    });
  }

  bool get _isSolved {
    for (int i = 0; i < _tiles.length; i++) {
      if (_tiles[i] != i) return false;
    }
    return true;
  }

  void _onTileTap(int index) {
    if (_isSolved || _loading) return;

    if (_selectedTile == null) {
      setState(() {
        _selectedTile = index;
      });
      return;
    }

    final first = _selectedTile!;
    if (first == index) {
      setState(() {
        _selectedTile = null;
      });
      return;
    }

    setState(() {
      final temp = _tiles[first];
      _tiles[first] = _tiles[index];
      _tiles[index] = temp;
      _selectedTile = null;
      _moveCount++;
    });

    if (_isSolved) {
      _showSolvedDialog();
    }
  }

  void _showSolvedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18221B),
        title: const Text('Puzzle Solved! (ধাঁধা সমাধান!)'),
        content: Text(
          'Species: $_species\n'
          'Moves taken: $_moveCount\n\n'
          'অভিনন্দন! আপনি সঠিকভাবে ছবিটি মিলিয়েছেন।',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _initGame();
            },
            child: const Text(
              'Play Again (আবার খেলুন)',
              style: TextStyle(color: Color(0xFF00E676)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Back', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        title: const Text('SCRAMBLED IMAGE PUZZLE'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E676)),
            onPressed: _initGame,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'Solve the puzzle for: $_species',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Moves: $_moveCount',
              style: const TextStyle(color: Color(0xFF81C784), fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const SizedBox(
                height: 300,
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E676)),
                ),
              )
            else if (_error != null)
              SizedBox(
                height: 250,
                child: Center(
                  child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                ),
              )
            else
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00E676)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                      ),
                      itemCount: 9,
                      itemBuilder: (ctx, idx) {
                        final pieceIndex = _tiles[idx];
                        final isSelected = _selectedTile == idx;

                        final row = pieceIndex ~/ 3;
                        final col = pieceIndex % 3;

                        return GestureDetector(
                          onTap: () => _onTileTap(idx),
                          child: Container(
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              border: isSelected
                                  ? Border.all(color: Colors.amber, width: 3)
                                  : null,
                            ),
                            child: CustomPaint(
                              painter: _PuzzlePiecePainter(
                                imageUrl: _media!.imageUrl!,
                                pieceRow: row,
                                pieceCol: col,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PuzzlePiecePainter extends CustomPainter {
  final String imageUrl;
  final int pieceRow;
  final int pieceCol;

  _PuzzlePiecePainter({
    required this.imageUrl,
    required this.pieceRow,
    required this.pieceCol,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1E2E23);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GameDiagramPainter extends CustomPainter {
  final String type;
  final Color color;
  GameDiagramPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    if (type == 'photo') {
      // Large Camera with gradient feel
      final rrect = RRect.fromLTRBR(
          w * 0.1, h * 0.25, w * 0.9, h * 0.8, const Radius.circular(10));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, paint);
      canvas.drawCircle(Offset(w * 0.5, h * 0.52), w * 0.22, paint);
      canvas.drawCircle(
          Offset(w * 0.5, h * 0.52), w * 0.12, paint..strokeWidth = 1.5);
      canvas.drawRect(
          Rect.fromLTWH(w * 0.7, h * 0.18, w * 0.12, h * 0.07), paint);
    } else if (type == 'hint') {
      // Large Mind/Idea
      final brainPath = Path()
        ..addOval(Rect.fromCircle(
            center: Offset(w * 0.5, h * 0.38), radius: w * 0.28));
      canvas.drawPath(brainPath, fillPaint);
      canvas.drawPath(brainPath, paint);

      final neckPath = Path()
        ..moveTo(w * 0.25, h * 0.9)
        ..quadraticBezierTo(w * 0.25, h * 0.65, w * 0.5, h * 0.65)
        ..quadraticBezierTo(w * 0.75, h * 0.65, w * 0.75, h * 0.9);
      canvas.drawPath(neckPath, paint);
    } else if (type == 'call') {
      // Concentric Sound Waves
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
    } else {
      // Large Interlocking Jigsaw
      final piece = Path()
        ..moveTo(w * 0.15, h * 0.25)
        ..lineTo(w * 0.35, h * 0.25)
        ..arcToPoint(Offset(w * 0.55, h * 0.25),
            radius: Radius.circular(w * 0.1))
        ..lineTo(w * 0.75, h * 0.25)
        ..lineTo(w * 0.75, h * 0.45)
        ..arcToPoint(Offset(w * 0.75, h * 0.65),
            radius: Radius.circular(w * 0.1), clockwise: false)
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
