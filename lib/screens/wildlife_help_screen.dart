import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/wildlife_help.dart';
import '../services/wildlife_help_service.dart';

class WildlifeHelpScreen extends StatefulWidget {
  const WildlifeHelpScreen({super.key});

  @override
  State<WildlifeHelpScreen> createState() => _WildlifeHelpScreenState();
}

class _WildlifeHelpScreenState extends State<WildlifeHelpScreen> {
  final WildlifeHelpService _helpService = WildlifeHelpService();
  
  List<WildlifeSafetyGuideline> _guidelines = [];
  List<VerifiedRescueContact> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final gl = await _helpService.fetchSafetyGuidelines();
    final ct = await _helpService.fetchVerifiedContacts();
    if (mounted) {
      setState(() {
        _guidelines = gl;
        _contacts = ct;
        _loading = false;
      });
    }
  }

  void _showRequestHelpDialog() {
    final catController = TextEditingController();
    final descController = TextEditingController();
    final locController = TextEditingController();
    final distController = TextEditingController();
    File? selectedMedia;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF18221B),
              title: const Text('বন্যপ্রাণী সহায়তার আবেদন', style: TextStyle(color: Colors.white, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('দয়া করে সঠিক তথ্য দিন। জরুরি অবস্থায় ফোন করুন।', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: catController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'ঘটনার ধরন (যেমন: সাপ উদ্ধার, আহত পাখি)', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'আনুমানিক স্থান', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: distController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'জেলা', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'বিস্তারিত বিবরণ', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.gallery);
                        if (picked != null) {
                          setDialogState(() => selectedMedia = File(picked.path));
                        }
                      },
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      label: Text(selectedMedia != null ? 'ছবি নির্বাচন করা হয়েছে' : 'ছবি যোগ করুন (ঐচ্ছিক)', style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('বাতিল', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                  onPressed: isSubmitting ? null : () async {
                    if (catController.text.trim().isEmpty || descController.text.trim().isEmpty) {
                      return;
                    }
                    setDialogState(() => isSubmitting = true);
                    final success = await _helpService.submitHelpRequest(
                      category: catController.text.trim(),
                      description: descController.text.trim(),
                      locationApprox: locController.text.trim(),
                      district: distController.text.trim(),
                      mediaFile: selectedMedia,
                    );
                    if (mounted) {
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? 'আপনার আবেদন জমা দেওয়া হয়েছে। আমরা শীঘ্রই যোগাযোগ করব।' : 'আবেদন জমা দিতে সমস্যা হয়েছে।')),
                      );
                    }
                  },
                  child: isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('জমা দিন', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        title: const Text('বন্যপ্রাণী সহায়তা', style: TextStyle(fontSize: 18)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
          : RefreshIndicator(
              color: const Color(0xFF00E676),
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Emergency Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2E1515), Color(0xFF1F0D0D)]),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 40),
                          const SizedBox(height: 12),
                          const Text(
                            'জরুরি বন্যপ্রাণী উদ্ধার',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'আহত বন্যপ্রাণী বা মানুষের সংঘাতের ক্ষেত্রে নিজে উদ্ধার করতে যাবেন না। সাহায্য চান।',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _showRequestHelpDialog,
                            icon: const Icon(Icons.health_and_safety, color: Colors.white),
                            label: const Text('সহায়তার আবেদন করুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Verified Contacts
                    const Text('যাচাইকৃত যোগাযোগ', style: TextStyle(color: Color(0xFF00E676), fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_contacts.isEmpty)
                      const Text('বর্তমানে কোনো যোগাযোগ তালিকাভুক্ত নেই।', style: TextStyle(color: Colors.white54))
                    else
                      ..._contacts.map((c) => Card(
                        color: const Color(0xFF16251A),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (c.organization != null) Text(c.organization!, style: const TextStyle(color: Color(0xFF81C784))),
                              if (c.phone != null) Text('Phone: ${c.phone}', style: const TextStyle(color: Colors.white70)),
                              if (c.district != null) Text('District: ${c.district}', style: const TextStyle(color: Colors.white54)),
                            ],
                          ),
                          trailing: const Icon(Icons.verified, color: Colors.blue, size: 20),
                        ),
                      )),
                    
                    const SizedBox(height: 32),

                    // Guidelines
                    const Text('জরুরি নির্দেশনা', style: TextStyle(color: Color(0xFF00E676), fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_guidelines.isEmpty)
                      const Text('নির্দেশনা শীঘ্রই আসছে।', style: TextStyle(color: Colors.white54))
                    else
                      ..._guidelines.map((g) => Card(
                        color: const Color(0xFF18221B),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ExpansionTile(
                          iconColor: const Color(0xFF00E676),
                          collapsedIconColor: Colors.white54,
                          title: Text(g.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(g.content, style: const TextStyle(color: Colors.white70, height: 1.5)),
                            )
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ),
    );
  }
}