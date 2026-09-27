import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/wildlife_help.dart';

class WildlifeHelpAdminSection extends StatefulWidget {
  const WildlifeHelpAdminSection({super.key});

  @override
  State<WildlifeHelpAdminSection> createState() => _WildlifeHelpAdminSectionState();
}

class _WildlifeHelpAdminSectionState extends State<WildlifeHelpAdminSection> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<WildlifeHelpRequest> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);
    try {
      final response = await _supabase
          .from('wildlife_help_requests')
          .select()
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _requests = (response as List).map((e) => WildlifeHelpRequest.fromMap(e)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching requests: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateStatus(WildlifeHelpRequest req, String newStatus) async {
    try {
      await _supabase.from('wildlife_help_requests').update({'status': newStatus}).eq('id', req.id);
      _loadRequests();
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Divider(color: Colors.white24),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🆘 Wildlife Help / Rescue Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('(বন্যপ্রাণী সহায়তার আবেদন)', style: TextStyle(fontSize: 11, color: Color(0xFF00E676))),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
              tooltip: 'রিফ্রেশ করুন',
              onPressed: _loadRequests,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
            : _requests.isEmpty
                ? const Center(child: Text('কোনো আবেদন নেই।', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _requests.length,
                    itemBuilder: (ctx, i) {
                      final req = _requests[i];
                      return Card(
                        color: const Color(0xFF16251A),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(req.category, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(req.description, style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 4),
                              Text('District: ${req.district ?? "Unknown"}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              Text('Status: ${req.status}', style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 12)),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: Colors.white),
                            onSelected: (val) => _updateStatus(req, val),
                            itemBuilder: (ctx) => [
                              'submitted', 'under_review', 'verified', 'referred', 'in_progress', 'resolved', 'closed', 'invalid'
                            ].map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
                          ),
                        ),
                      );
                    },
                  ),
      ],
    );
  }
}
