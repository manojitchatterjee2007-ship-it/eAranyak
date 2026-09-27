import 'package:flutter/material.dart';

class GamificationAdminSection extends StatelessWidget {
  const GamificationAdminSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kishore eআরণ্যক & Vanarakkhi Control Centre',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        const Text(
          'Manage missions, badges, and learning modules for the gamified experience.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 24),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAdminCard(context, 'Missions', Icons.assignment, Colors.orange),
            _buildAdminCard(context, 'Badges', Icons.stars, Colors.yellow),
            _buildAdminCard(context, 'Modules', Icons.library_books, Colors.blue),
            _buildAdminCard(context, 'Daily Challenges', Icons.calendar_today, Colors.redAccent),
          ],
        ),
        
        const SizedBox(height: 32),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              'Editor interface under construction. Manage schema via Supabase dashboard in the interim.',
              style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildAdminCard(BuildContext context, String title, IconData icon, Color color) {
    return Card(
      color: const Color(0xFF1E2E23),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {}, // Future extension
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 48),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
