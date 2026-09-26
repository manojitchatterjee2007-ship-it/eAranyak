
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/about_us_content.dart';

class AboutUsAdminSection extends StatefulWidget {
  const AboutUsAdminSection({Key? key}) : super(key: key);

  @override
  State<AboutUsAdminSection> createState() => _AboutUsAdminSectionState();
}

class _AboutUsAdminSectionState extends State<AboutUsAdminSection> {
  final _supabase = Supabase.instance.client;
  AboutUsContent? _content;
  bool _isLoading = true;

  late TextEditingController _titleController;
  late TextEditingController _subtitleController;
  late TextEditingController _bodyController;
  late TextEditingController _whatWeDoTitleController;
  late TextEditingController _whatWeDoBodyController;
  late TextEditingController _heroImageUrlController;
  bool _isPublished = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _subtitleController = TextEditingController();
    _bodyController = TextEditingController();
    _whatWeDoTitleController = TextEditingController();
    _whatWeDoBodyController = TextEditingController();
    _heroImageUrlController = TextEditingController();
    _fetchContent();
  }

  Future<void> _fetchContent() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('about_us_content')
          .select('*')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        _content = AboutUsContent.fromJson(response);
        _titleController.text = _content!.titleBn;
        _subtitleController.text = _content!.subtitleBn ?? '';
        _bodyController.text = _content!.bodyBn ?? '';
        _whatWeDoTitleController.text = _content!.whatWeDoTitleBn ?? '';
        _whatWeDoBodyController.text = _content!.whatWeDoBodyBn ?? '';
        _heroImageUrlController.text = _content!.heroImageUrl ?? '';
        _isPublished = _content!.isPublished;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final data = {
        'title_bn': _titleController.text.isNotEmpty ? _titleController.text : 'About Us',
        'subtitle_bn': _subtitleController.text,
        'body_bn': _bodyController.text,
        'what_we_do_title_bn': _whatWeDoTitleController.text,
        'what_we_do_body_bn': _whatWeDoBodyController.text,
        'hero_image_url': _heroImageUrlController.text,
        'is_published': _isPublished,
      };

      if (_content == null) {
        await _supabase.from('about_us_content').insert(data);
      } else {
        await _supabase.from('about_us_content').update(data).eq('id', _content!.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved successfully!')));
        _fetchContent();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('About Us & What We Do', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 16),
        TextField(controller: _titleController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Main Heading (Bengali)', labelStyle: TextStyle(color: Colors.white70))),
        TextField(controller: _subtitleController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Subheading (Bengali)', labelStyle: TextStyle(color: Colors.white70))),
        TextField(controller: _bodyController, style: const TextStyle(color: Colors.white), maxLines: 5, decoration: const InputDecoration(labelText: 'About Us Body (Bengali)', labelStyle: TextStyle(color: Colors.white70))),
        TextField(controller: _whatWeDoTitleController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'What We Do Heading (Bengali)', labelStyle: TextStyle(color: Colors.white70))),
        TextField(controller: _whatWeDoBodyController, style: const TextStyle(color: Colors.white), maxLines: 5, decoration: const InputDecoration(labelText: 'What We Do Body (Bengali)', labelStyle: TextStyle(color: Colors.white70))),
        TextField(controller: _heroImageUrlController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Hero Image URL', labelStyle: TextStyle(color: Colors.white70))),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Publish to Public', style: TextStyle(color: Colors.white)),
          value: _isPublished,
          onChanged: (v) => setState(() => _isPublished = v),
          activeColor: const Color(0xFF00E676),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Save Content'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
        )
      ],
    );
  }
}

