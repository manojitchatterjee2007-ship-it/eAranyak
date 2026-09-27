import 'package:flutter/material.dart';
import '../services/vanarakkhi_service.dart';
import '../models/vanarakkhi_gamification_models.dart';

class KishoreEaranyakScreen extends StatefulWidget {
  const KishoreEaranyakScreen({super.key});

  @override
  State<KishoreEaranyakScreen> createState() => _KishoreEaranyakScreenState();
}

class _KishoreEaranyakScreenState extends State<KishoreEaranyakScreen> {
  final VanarakkhiService _service = VanarakkhiService();
  VanarakkhiUserProgress? _progress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final progress = await _service.getUserProgress();
    if (mounted) {
      setState(() {
        _progress = progress;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB), // Warm natural colour
      appBar: AppBar(
        title: const Text('Kishore eআরণ্যক', style: TextStyle(fontFamily: 'Bengali')),
        backgroundColor: Colors.green[800],
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
                    _buildSectionTitle('Explore & Learn'),
                    const SizedBox(height: 12),
                    _buildGridMenu(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Vanarakkhi Missions'),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.green[200]!, width: 2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.green[100],
            child: Icon(Icons.eco, color: Colors.green[800], size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vanarakkhi Level',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  'Level ${_progress?.currentLevel ?? 1}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: ((_progress?.totalXp ?? 0) % 100) / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green[600]!),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_progress?.totalXp ?? 0} XP',
                  style: TextStyle(fontSize: 12, color: Colors.green[800], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildGridMenu() {
    final List<Map<String, dynamic>> items = [
      {'title': "Today's Wildlife", 'icon': Icons.calendar_today, 'color': Colors.orange},
      {'title': 'Explore Species', 'icon': Icons.search, 'color': Colors.blue},
      {'title': 'Quiz', 'icon': Icons.quiz, 'color': Colors.purple},
      {'title': 'Nature Facts', 'icon': Icons.lightbulb, 'color': Colors.yellow[700]},
      {'title': 'My Collection', 'icon': Icons.collections_bookmark, 'color': Colors.brown},
      {'title': 'Achievements', 'icon': Icons.emoji_events, 'color': Colors.red},
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
          onTap: () {
            // Navigate to appropriate screen
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item['icon'], color: item['color'], size: 32),
                const SizedBox(height: 8),
                Text(
                  item['title'],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
      future: _service.getMissions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No active missions right now.'),
            ),
          );
        }

        final missions = snapshot.data!.take(3).toList();
        return Column(
          children: missions.map((mission) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: mission.isCompleted ? Colors.green[100] : Colors.orange[100],
                  child: Icon(
                    mission.isCompleted ? Icons.check : Icons.assignment,
                    color: mission.isCompleted ? Colors.green : Colors.orange,
                  ),
                ),
                title: Text(mission.titleBn, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('+${mission.xpReward} XP', style: TextStyle(color: Colors.green[700])),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // Open mission detail
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
