import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/daily_wildlife_feature.dart';

class DailyWildlifeAdminSection extends StatefulWidget {
  const DailyWildlifeAdminSection({super.key});

  @override
  State<DailyWildlifeAdminSection> createState() =>
      _DailyWildlifeAdminSectionState();
}

class _DailyWildlifeAdminSectionState
    extends State<DailyWildlifeAdminSection> {
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
          .limit(15);

      setState(() {
        _features = (response as List)
            .map((e) => DailyWildlifeFeature.fromJson(e))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading Daily Wildlife: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isGenerating = false;

  Future<void> _generateFeature() async {
    if (_isGenerating) return;
    
    setState(() => _isGenerating = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Starting Daily Wildlife automation...'),
        ),
      );
    }

    try {
      /*
       * IMPORTANT:
       *
       * Do NOT put DAILY_WILDLIFE_INTERNAL_SECRET in the Flutter app.
       *
       * The Supabase client automatically sends the authenticated
       * user's session when invoking the Edge Function.
       *
       * The Edge Function must therefore authorize an authenticated
       * admin user on the server side.
       */
      final response = await _supabase.functions.invoke(
        'daily-wildlife-automation',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Automation complete: ${response.data}',
          ),
        ),
      );

      await _fetchFeatures();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Automation error: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _openEditor(DailyWildlifeFeature feature) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DailyWildlifeEditor(
          feature: feature,
          onSave: _fetchFeatures,
        ),
      ),
    );
  }

  bool _hasBengaliContent(DailyWildlifeFeature feature) {
    final combinedText = '${feature.titleBn} ${feature.descriptionBn} ${feature.habitat} ${feature.interestingFacts}'.trim();
    final bengaliRegex = RegExp(r'[\u0980-\u09FF]');
    return bengaliRegex.hasMatch(combinedText);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            const Text(
              'Daily Wildlife Features',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _fetchFeatures,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateFeature,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isGenerating ? 'Running...' : 'Run Automation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          )
        else if (_features.isEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'No features found',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          )
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
                  leading: Builder(builder: (_) {
                    // Hi-res admin thumb: provenance large.jpg, never the
                    // 75px iNat square.jpg from the stored row URL.
                    final thumb = f.displayImageUrl ?? f.verifiedOriginalImageUrl;
                    if (thumb == null || thumb.isEmpty) {
                      return const Icon(Icons.image, color: Colors.white24);
                    }
                    return SizedBox(
                      width: 60,
                      height: 60,
                      child: CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        memCacheWidth: 240,
                        maxWidthDiskCache: 480,
                        filterQuality: FilterQuality.high,
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.broken_image,
                          color: Colors.white24,
                        ),
                      ),
                    );
                  }),
                  title: Text(
                    '${f.featureDate.toLocal().toString().split(' ')[0]} - ${f.title}',
                  ),
                  subtitle: Text(
                    'Status: ${f.status} | '
                    'Source Image: ${f.imageGenerationStatus}'
                    '${_hasBengaliContent(f) ? "" : " | ⚠️ Missing Bengali Content"}',
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.edit,
                      color: Colors.white,
                    ),
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

  const DailyWildlifeEditor({
    super.key,
    required this.feature,
    required this.onSave,
  });

  @override
  State<DailyWildlifeEditor> createState() =>
      _DailyWildlifeEditorState();
}

class _DailyWildlifeEditorState
    extends State<DailyWildlifeEditor> {
  final _supabase = Supabase.instance.client;

  late TextEditingController _titleController;
  late TextEditingController _titleBnController;
  late TextEditingController _commonNameController;
  late TextEditingController _scientificNameController;
  late TextEditingController _habitatController;
  late TextEditingController _interestingFactsController;
  late TextEditingController _didYouKnowController;

  late TextEditingController _animalTypeController;
  late TextEditingController _selectionReasonController;
  late TextEditingController _regionalSignificanceController;
  late TextEditingController _economicImportanceController;
  late TextEditingController _habitatThreatController;
  late TextEditingController _educationalValueController;

  late TextEditingController _audioUrlController;
  late TextEditingController _audioProviderController;
  late TextEditingController _audioIdController;
  late TextEditingController _audioRecordistController;
  late TextEditingController _audioLicenseController;
  late TextEditingController _audioAttributionController;

  /*
   * This remains a UI convenience only.
   *
   * The current database schema does NOT contain audio_available,
   * so this value is deliberately NOT written to Supabase.
   */
  bool _audioAvailable = false;

  bool _isPublished = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _titleController =
        TextEditingController(text: widget.feature.title);

    _titleBnController =
        TextEditingController(text: widget.feature.titleBn);

    _commonNameController =
        TextEditingController(text: widget.feature.commonName);

    _scientificNameController =
        TextEditingController(text: widget.feature.scientificName);

    _habitatController =
        TextEditingController(text: widget.feature.habitat);

    _interestingFactsController =
        TextEditingController(text: widget.feature.interestingFacts);

    _didYouKnowController =
        TextEditingController(text: widget.feature.didYouKnow);

    _animalTypeController =
        TextEditingController(text: widget.feature.animalType);

    _selectionReasonController =
        TextEditingController(text: widget.feature.selectionReason);

    _regionalSignificanceController =
        TextEditingController(text: widget.feature.regionalSignificance);

    _economicImportanceController =
        TextEditingController(text: widget.feature.economicImportance);

    _habitatThreatController =
        TextEditingController(text: widget.feature.habitatThreat);

    _educationalValueController =
        TextEditingController(text: widget.feature.educationalValue);

    _audioUrlController =
        TextEditingController(text: widget.feature.audioUrl);

    _audioProviderController =
        TextEditingController(text: widget.feature.audioProvider);

    _audioIdController =
        TextEditingController(text: widget.feature.audioId);

    _audioRecordistController =
        TextEditingController(text: widget.feature.audioRecordist);

    _audioLicenseController =
        TextEditingController(text: widget.feature.audioLicense);

    _audioAttributionController =
        TextEditingController(text: widget.feature.audioAttribution);

    _audioAvailable = widget.feature.audioAvailable;

    _isPublished = widget.feature.isPublished;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleBnController.dispose();
    _commonNameController.dispose();
    _scientificNameController.dispose();
    _habitatController.dispose();
    _interestingFactsController.dispose();
    _didYouKnowController.dispose();

    _animalTypeController.dispose();
    _selectionReasonController.dispose();
    _regionalSignificanceController.dispose();
    _economicImportanceController.dispose();
    _habitatThreatController.dispose();
    _educationalValueController.dispose();

    _audioUrlController.dispose();
    _audioProviderController.dispose();
    _audioIdController.dispose();
    _audioRecordistController.dispose();
    _audioLicenseController.dispose();
    _audioAttributionController.dispose();

    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      /*
       * IMPORTANT:
       *
       * audio_available has intentionally been removed from this
       * update because the current Supabase table does not contain
       * that column.
       */
      await _supabase
          .from('daily_wildlife_features')
          .update({
        'title': _titleController.text.trim(),
        'title_bn': _titleBnController.text.trim(),
        'common_name': _commonNameController.text.trim(),
        'scientific_name': _scientificNameController.text.trim(),
        'habitat': _habitatController.text.trim(),
        'interesting_facts':
            _interestingFactsController.text.trim(),
        'did_you_know':
            _didYouKnowController.text.trim(),

        'animal_type':
            _animalTypeController.text.trim(),
        'selection_reason':
            _selectionReasonController.text.trim(),
        'regional_significance':
            _regionalSignificanceController.text.trim(),
        'economic_importance':
            _economicImportanceController.text.trim(),
        'habitat_threat':
            _habitatThreatController.text.trim(),
        'educational_value':
            _educationalValueController.text.trim(),

        'audio_url':
            _audioUrlController.text.trim(),
        'audio_provider':
            _audioProviderController.text.trim(),
        'audio_id':
            _audioIdController.text.trim(),
        'audio_recordist':
            _audioRecordistController.text.trim(),
        'audio_license':
            _audioLicenseController.text.trim(),
        'audio_attribution':
            _audioAttributionController.text.trim(),

        'is_published': _isPublished,
        'status':
            _isPublished ? 'published' : (widget.feature.status == 'scheduled' ? 'scheduled' : 'draft'),

        'editor_override': true,
      }).eq('id', widget.feature.id);

      widget.onSave();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Daily Wildlife feature saved successfully.',
            ),
          ),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving feature: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hi-res preview: provenance original (large.jpg), upgraded from any
    // lingering square/small/medium thumbnail. This is the editorial
    // pixelation fix — never render the 75px square.jpg at 200px height.
    final sourceImageUrl = widget.feature.displayImageUrl ??
        widget.feature.verifiedOriginalImageUrl ??
        widget.feature.originalImageUrl;

    return Scaffold(
      backgroundColor: const Color(0xFF142419),
      appBar: AppBar(
        title: const Text('Edit Feature'),
        backgroundColor: const Color(0xFF1B3322),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /*
             * Daily Wildlife now displays the ORIGINAL SOURCE PHOTO.
             *
             * No watercolor/AI-generated image is used here.
             */
            if (sourceImageUrl != null &&
                sourceImageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: sourceImageUrl,
                cacheKey: widget.feature.imageCacheKey,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 900,
                maxWidthDiskCache: 1200,
                filterQuality: FilterQuality.high,
                placeholder: (context, url) =>
                    const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) =>
                    Container(
                  height: 200,
                  color: Colors.white10,
                  child: const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 200,
                width: double.infinity,
                color: Colors.white10,
                child: const Center(
                  child: Text(
                    'No Source Image Available',
                    style: TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Title',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _titleBnController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Title (Bengali)',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _commonNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Common Name',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _scientificNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Scientific Name',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _habitatController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Habitat',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _interestingFactsController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Interesting Facts',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _didYouKnowController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Did You Know',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Metadata',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            TextField(
              controller: _animalTypeController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Animal Type',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _selectionReasonController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Selection Reason',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _regionalSignificanceController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Regional Significance',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _economicImportanceController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Economic Importance',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _habitatThreatController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Habitat Threat',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _educationalValueController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Educational Value',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Audio Info',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            SwitchListTile(
              title: const Text(
                'Audio Available',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'UI indicator only; not stored as a separate database column.',
                style: TextStyle(color: Colors.white54),
              ),
              value: _audioAvailable,
              onChanged: (v) {
                setState(() {
                  _audioAvailable = v;
                });
              },
              activeThumbColor:
                  const Color(0xFF00E676),
            ),

            TextField(
              controller: _audioUrlController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Audio URL',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _audioProviderController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Audio Provider',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _audioIdController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Audio ID',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _audioRecordistController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Audio Recordist',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _audioLicenseController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Audio License',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            TextField(
              controller: _audioAttributionController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Audio Attribution',
                labelStyle:
                    TextStyle(color: Colors.white70),
              ),
            ),

            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text(
                'Publish',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Publish this feature on the Daily Wildlife feed.',
                style: TextStyle(color: Colors.white54),
              ),
              value: _isPublished,
              onChanged: (v) {
                setState(() {
                  _isPublished = v;
                });
              },
              activeThumbColor:
                  const Color(0xFF00E676),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : 'Save Changes',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}