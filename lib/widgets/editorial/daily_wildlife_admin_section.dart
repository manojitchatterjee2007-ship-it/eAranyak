import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/daily_wildlife_feature.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/config.dart';

class DailyWildlifeAdminSection extends StatefulWidget {
  const DailyWildlifeAdminSection({Key? key}) : super(key: key);

  @override
  State<DailyWildlifeAdminSection> createState() => _DailyWildlifeAdminSectionState();
}

class _DailyWildlifeAdminSectionState extends State<DailyWildlifeAdminSection> {
  final _supabase = Supabase.instance.client;
  List<DailyWildlifeFeature> _features = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFeatures();
  }

  Future<void> _fetchFeatures() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('daily_wildlife_features')
          .select('*')
          .order('feature_date', ascending: false)
          .limit(30);

      setState(() {
        _features = (response as List).map((e) => DailyWildlifeFeature.fromJson(e)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateFeature() async {
    // Generate next available feature using Edge Function
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starting generation...')));
    }
    try {
      final response = await _supabase.functions.invoke('daily-wildlife-automation');
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generation complete: ${response.data}')));
         _fetchFeatures();
      }
    } catch(e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generation error: $e')));
      }
    }
  }

  void _openEditor(DailyWildlifeFeature feature) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => DailyWildlifeEditor(feature: feature, onSave: _fetchFeatures),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Daily Wildlife Features', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _fetchFeatures,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _generateFeature,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Run Automation'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_features.isEmpty)
          const Center(child: Text('No features found', style: TextStyle(color: Colors.white70)))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _features.length,
            itemBuilder: (context, index) {
              final f = _features[index];
              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: SizedBox(
                    width: 60,
                    height: 60,
                    child: f.watercolourImageUrl != null
                        ? CachedNetworkImage(imageUrl: f.watercolourImageUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.image, color: Colors.white24),
                  ),
                  title: Text('${f.featureDate.toLocal().toString().split(' ')[0]} - ${f.title}'),
                  subtitle: Text('Status: ${f.status} | Generated: ${f.imageGenerationStatus}', style: const TextStyle(color: Colors.white70)),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: () => _openEditor(f),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class DailyWildlifeEditor extends StatefulWidget {
  final DailyWildlifeFeature feature;
  final VoidCallback onSave;

  const DailyWildlifeEditor({Key? key, required this.feature, required this.onSave}) : super(key: key);

  @override
  State<DailyWildlifeEditor> createState() => _DailyWildlifeEditorState();
}

class _DailyWildlifeEditorState extends State<DailyWildlifeEditor> {
  final _supabase = Supabase.instance.client;
  late TextEditingController _titleController;
  late TextEditingController _titleBnController;
  late TextEditingController _commonNameController;
  late TextEditingController _scientificNameController;
  late TextEditingController _habitatController;
  late TextEditingController _interestingFactsController;
  late TextEditingController _didYouKnowController;
  bool _isPublished = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.feature.title);
    _titleBnController = TextEditingController(text: widget.feature.titleBn);
    _commonNameController = TextEditingController(text: widget.feature.commonName);
    _scientificNameController = TextEditingController(text: widget.feature.scientificName);
    _habitatController = TextEditingController(text: widget.feature.habitat);
    _interestingFactsController = TextEditingController(text: widget.feature.interestingFacts);
    _didYouKnowController = TextEditingController(text: widget.feature.didYouKnow);
    _isPublished = widget.feature.isPublished;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _supabase.from('daily_wildlife_features').update({
        'title': _titleController.text,
        'title_bn': _titleBnController.text,
        'common_name': _commonNameController.text,
        'scientific_name': _scientificNameController.text,
        'habitat': _habitatController.text,
        'interesting_facts': _interestingFactsController.text,
        'did_you_know': _didYouKnowController.text,
        'is_published': _isPublished,
        'status': _isPublished ? 'published' : 'draft',
        'editor_override': true,
      }).eq('id', widget.feature.id);
      
      widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _regenerateImage() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regenerating image...')));
    }
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) return;
      final response = await http.post(
        Uri.parse('${supabaseUrl}/functions/v1/generate-wildlife-watercolor'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'featureId': widget.feature.id,
        })
      );
      if (response.statusCode == 200) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image regenerated successfully.')));
           widget.onSave();
           Navigator.pop(context);
        }
      } else {
        throw Exception(response.body);
      }
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF142419),
      appBar: AppBar(
        title: const Text('Edit Feature'),
        backgroundColor: const Color(0xFF1B3322),
        actions: [
          IconButton(icon: const Icon(Icons.image), onPressed: _regenerateImage, tooltip: 'Regenerate Image'),
          IconButton(icon: const Icon(Icons.save), onPressed: _isSaving ? null : _save),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (widget.feature.watercolourImageUrl != null)
              CachedNetworkImage(
                imageUrl: widget.feature.watercolourImageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            else
              Container(height: 200, color: Colors.white10, child: const Center(child: Text('No Image Generated', style: TextStyle(color: Colors.white70)))),
            const SizedBox(height: 16),
            TextField(controller: _titleController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: Colors.white70))),
            TextField(controller: _titleBnController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Title (Bengali)', labelStyle: TextStyle(color: Colors.white70))),
            TextField(controller: _commonNameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Common Name', labelStyle: TextStyle(color: Colors.white70))),
            TextField(controller: _scientificNameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Scientific Name', labelStyle: TextStyle(color: Colors.white70))),
            TextField(controller: _habitatController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Habitat', labelStyle: TextStyle(color: Colors.white70))),
            TextField(controller: _interestingFactsController, style: const TextStyle(color: Colors.white), maxLines: 3, decoration: const InputDecoration(labelText: 'Interesting Facts', labelStyle: TextStyle(color: Colors.white70))),
            TextField(controller: _didYouKnowController, style: const TextStyle(color: Colors.white), maxLines: 3, decoration: const InputDecoration(labelText: 'Did You Know', labelStyle: TextStyle(color: Colors.white70))),
            SwitchListTile(
              title: const Text('Publish', style: TextStyle(color: Colors.white)),
              value: _isPublished,
              onChanged: (v) => setState(() => _isPublished = v),
              activeColor: const Color(0xFF00E676),
            ),
          ],
        ),
      ),
    );
  }
}

