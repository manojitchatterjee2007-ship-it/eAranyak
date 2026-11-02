import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/daily_wildlife_feature.dart';
import '../models/kishor_medal.dart';
import '../models/vanarakkhi_gamification_models.dart';
import '../services/sound_service.dart';
import '../services/vanarakkhi_service.dart';
import 'citizen_science_screen.dart';
import 'daily_wildlife_screen.dart';
import 'kishor_medal_screen.dart';
import 'nature_games_screen.dart';
import 'user_bookshelf_screen.dart';

class KishoreEaranyakScreen extends StatefulWidget {
  const KishoreEaranyakScreen({super.key});

  @override
  State<KishoreEaranyakScreen> createState() => _KishoreEaranyakScreenState();
}

class _KishoreEaranyakScreenState extends State<KishoreEaranyakScreen> {
  final VanarakkhiService _service = VanarakkhiService();
  VanarakkhiUserProgress? _progress;
  List<KishorMedalEligibility> _medals = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final results = await Future.wait([
        _service.getUserProgress(),
        _service.getEarnedMedals(),
      ]).timeout(const Duration(seconds: 4));
      if (mounted) {
        setState(() {
          _progress = results[0] as VanarakkhiUserProgress?;
          _medals = (results[1] as List<KishorMedalEligibility>? ?? const [])
              .where((m) => m.isEligible)
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading Kishore Aranyak progress: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openTodaysWildlife() async {
    SoundService.playButtonSound();
    try {
      final response = await Supabase.instance.client
          .from('daily_wildlife_features')
          .select('*')
          .eq('is_published', true)
          .lte('feature_date', DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 10))
          .order('feature_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      if (response != null) {
        final feature = DailyWildlifeFeature.fromJson(response);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DailyWildlifeScreen(feature: feature),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('আজকের কোনো বন্যপ্রাণী তথ্য পাওয়া যায়নি। (No daily wildlife feature available today)'),
            backgroundColor: Color(0xFF142419),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching today\'s wildlife feature: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('তথ্য লোড করতে সমস্যা হয়েছে: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _handleGridItemTap(int index) {
    SoundService.playButtonSound();
    switch (index) {
      case 0:
        _openTodaysWildlife();
        break;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CitizenScienceScreen(),
          ),
        );
        break;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const WildlifeQuizGame(
              type: 'photo',
              difficulty: 'medium',
            ),
          ),
        );
        break;
      case 3:
        final uri = Uri.parse('https://kids.nationalgeographic.com/nature');
        launchUrl(uri, mode: LaunchMode.externalApplication);
        break;
      case 4:
        final email = Supabase.instance.client.auth.currentUser?.email ?? '';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserBookshelfScreen(userEmail: email),
          ),
        );
        break;
      case 5:
        final best = _medals.isNotEmpty
            ? _medals.reduce((a, b) => a.completedLevel >= b.completedLevel ? a : b)
            : null;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => KishorMedalScreen(
              level: best?.completedLevel ?? _progress?.currentLevel ?? 1,
              eligibility: best,
            ),
          ),
        );
        break;
      default:
        debugPrint('Unhandled grid index: $index');
        break;
    }
  }

  void _openMissionDetail(VanarakkhiMission mission) {
    SoundService.playButtonSound();
    bool isCompleting = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18221B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: mission.isCompleted
                          ? const Color(0xFF00E676).withValues(alpha: 0.2)
                          : Colors.orangeAccent.withValues(alpha: 0.2),
                      child: Icon(
                        mission.isCompleted ? Icons.check : Icons.assignment,
                        color: mission.isCompleted ? const Color(0xFF00E676) : Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mission.titleBn,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '+${mission.xpReward} XP • ${mission.difficulty.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if ((mission.descriptionBn ?? '').isNotEmpty) ...[
                  Text(
                    mission.descriptionBn!,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                ],
                if ((mission.educationalExplanation ?? '').isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142419),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      'শিক্ষণীয় তথ্য: ${mission.educationalExplanation}',
                      style: const TextStyle(color: Color(0xFF81C784), fontSize: 13, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: mission.isCompleted
                      ? Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: Color(0xFF00E676), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'মিশন সম্পন্ন হয়েছে! (Mission Completed)',
                                style: TextStyle(
                                  color: Color(0xFF00E676),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: isCompleting
                              ? null
                              : () async {
                                  setModalState(() => isCompleting = true);
                                  SoundService.playButtonSound();
                                  final messenger = ScaffoldMessenger.of(context);
                                  final success = await _service.completeMission(mission.id);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  if (success) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('অভিনন্দন! "${mission.titleBn}" মিশন সম্পন্ন হয়েছে (+${mission.xpReward} XP)!'),
                                        backgroundColor: const Color(0xFF142419),
                                      ),
                                    );
                                    _loadProgress();
                                  } else {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('মিশন সম্পন্ন করা সম্ভব হয়নি। অনুগ্রহ করে পরে আবার চেষ্টা করুন।'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                },
                          child: isCompleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                                )
                              : const Text(
                                  'মিশন সম্পন্ন করুন (Complete Mission)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410), // Dark forest green theme
      appBar: AppBar(
        title: const Text('কিশোর আরণ্যক', style: TextStyle(fontFamily: 'Bengali')),
        backgroundColor: const Color(0xFF142419),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProgress,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProgressCard(),
                    const SizedBox(height: 24),
                    if (_medals.isNotEmpty) ...[
                      _buildSectionTitle('পদক', 'Medals'),
                      const SizedBox(height: 12),
                      _buildMedalSection(),
                      const SizedBox(height: 24),
                    ],
                    _buildSectionTitle('অন্বেষণ এবং শেখা', 'Explore & Learn'),
                    const SizedBox(height: 12),
                    _buildGridMenu(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('বনরক্ষী অভিযান', 'Vanarakkhi Missions'),
                    const SizedBox(height: 12),
                    _buildMissionsPreview(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18221B),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.2),
            child: const Icon(Icons.eco, color: Color(0xFF00E676), size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'বনরক্ষী স্তর (Vanarakkhi Level)',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  'স্তর (Level) ${_progress?.currentLevel ?? 1}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: ((_progress?.totalXp ?? 0) % 100) / 100,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_progress?.totalXp ?? 0} XP',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the highest server-verified medal and opens the medal studio.
  ///
  /// The level is taken from [KishorMedalEligibility.completedLevel] returned by
  /// Supabase — the client never computes or persists a completion itself.
  Widget _buildMedalSection() {
    final best = _medals.reduce((a, b) =>
        a.completedLevel >= b.completedLevel ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18221B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE7EFB7).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Color(0xFF2A3F1E),
            child: Icon(Icons.military_tech,
                color: Color(0xFFE7EFB7), size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'স্তর (Level) ${best.completedLevel} পদক অর্জিত!\n'
                  'Level ${best.completedLevel} medal earned!',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${best.score}/${best.maxScore} • +${best.xpAwarded} XP',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00E676),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              SoundService.playButtonSound();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => KishorMedalScreen(
                    level: best.completedLevel,
                    eligibility: best,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE7EFB7),
              foregroundColor: const Color(0xFF0D1410),
            ),
            child: const Text('দেখুন (View)'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String titleBn, String titleEn) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleBn,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          '($titleEn)',
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildGridMenu() {
    final List<Map<String, dynamic>> items = [
      {'titleBn': 'আজকের বন্যপ্রাণী', 'titleEn': "Today's Wildlife", 'icon': Icons.calendar_today, 'color': Colors.orangeAccent},
      {'titleBn': 'প্রজাতি অন্বেষণ', 'titleEn': 'Explore Species', 'icon': Icons.search, 'color': Colors.lightBlueAccent},
      {'titleBn': 'কুইজ', 'titleEn': 'Quiz', 'icon': Icons.quiz, 'color': Colors.purpleAccent},
      {'titleBn': 'প্রকৃতির তথ্য', 'titleEn': 'Nature Facts', 'icon': Icons.lightbulb, 'color': Colors.yellowAccent},
      {'titleBn': 'আমার সংগ্রহ', 'titleEn': 'My Collection', 'icon': Icons.collections_bookmark, 'color': Colors.brown[300]},
      {'titleBn': 'অর্জন', 'titleEn': 'Achievements', 'icon': Icons.emoji_events, 'color': Colors.redAccent},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () => _handleGridItemTap(index),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF18221B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item['icon'], color: item['color'], size: 32),
                const SizedBox(height: 8),
                Text(
                  item['titleBn'],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  '(${item['titleEn']})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMissionsPreview() {
    return FutureBuilder<List<VanarakkhiMission>>(
      future: _service.getMissions().timeout(const Duration(seconds: 4)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Card(
            color: const Color(0xFF18221B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('এই মুহূর্তে কোনো সক্রিয় মিশন নেই।\n(No active missions right now.)', style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        final missions = snapshot.data!.take(3).toList();
        return Column(
          children: missions.map((mission) {
            return Card(
              color: const Color(0xFF18221B),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: mission.isCompleted 
                      ? const Color(0xFF00E676).withValues(alpha: 0.2) 
                      : Colors.orangeAccent.withValues(alpha: 0.2),
                  child: Icon(
                    mission.isCompleted ? Icons.check : Icons.assignment,
                    color: mission.isCompleted ? const Color(0xFF00E676) : Colors.orangeAccent,
                  ),
                ),
                title: Text(mission.titleBn, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('+${mission.xpReward} XP', style: const TextStyle(color: Color(0xFF00E676))),
                trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                onTap: () => _openMissionDetail(mission),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
