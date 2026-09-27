import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/wildlife_sighting.dart';
import '../services/citizen_science_service.dart';
import '../services/sighting_validation.dart';
import '../services/sound_service.dart';
import '../widgets/citizen_science/sighting_card.dart';
import 'contributor_profile_screen.dart';
import 'citizen_science_screen.dart';
import 'sighting_detail_screen.dart';

/// Bengali-first "রিপোর্ট করুন" wizard: three short steps, no taxonomy
/// knowledge required, with an explicit location-privacy choice.
class SightingSubmissionScreen extends StatefulWidget {
  final WildlifeSighting? existing;

  const SightingSubmissionScreen({super.key, this.existing});

  @override
  State<SightingSubmissionScreen> createState() =>
      _SightingSubmissionScreenState();
}

class _SightingSubmissionScreenState extends State<SightingSubmissionScreen> {
  final CitizenScienceService _service = CitizenScienceService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  int _step = 0;
  bool _isSubmitting = false;

  final TextEditingController _commonNameCtrl = TextEditingController();
  final TextEditingController _bengaliNameCtrl = TextEditingController();
  final TextEditingController _scientificNameCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _districtCtrl = TextEditingController();
  final TextEditingController _stateCtrl = TextEditingController();
  final TextEditingController _countryCtrl = TextEditingController(text: 'India');
  final TextEditingController _behaviourCtrl = TextEditingController();
  final TextEditingController _countCtrl = TextEditingController(text: '1');
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _timeCtrl = TextEditingController();
  final TextEditingController _latitudeCtrl = TextEditingController();
  final TextEditingController _longitudeCtrl = TextEditingController();

  DateTime _observedAt = DateTime.now();
  String? _habitat;
  String _iucnStatus = 'unknown';
  String _locationPrecision = 'district';
  bool _breedingSite = false;
  String _contributorPrivacy = 'named';
  bool _includeCoordinates = false;
  String? _contributorName;

  final List<PlatformFile> _photos = <PlatformFile>[];
  final List<PlatformFile> _audioClips = <PlatformFile>[];
  final List<PlatformFile> _videoClips = <PlatformFile>[];
  final Map<PlatformFile, Uint8List> _photoPreviewBytes =
      <PlatformFile, Uint8List>{};

  WildlifeSighting? _created;

  static const List<String> _habitatOptions = <String>[
    'বন', 'জলাশয়', 'নদী', 'ঘাসজমি', 'পাহাড়', 'বাগান', 'কৃষিজমি', 'অন্যান্য',
  ];

  static const Map<String, String> _iucnOptions = <String, String>{
    'unknown': 'জানা নেই / জানি না',
    'LC': 'Least Concern — কম উদ্বেগজনক',
    'NT': 'Near Threatened — প্রায় সংকটাপন্ন',
    'VU': 'Vulnerable — সংকটাপন্ন',
    'EN': 'Endangered — বিপন্ন',
    'CR': 'Critically Endangered — মহাবিপন্ন',
  };

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _commonNameCtrl.text = existing.commonName;
      _bengaliNameCtrl.text = existing.bengaliName ?? '';
      _scientificNameCtrl.text = existing.scientificName ?? '';
      _descriptionCtrl.text = existing.description ?? '';
      _districtCtrl.text = existing.district ?? '';
      _stateCtrl.text = existing.state ?? '';
      _countryCtrl.text = existing.country ?? 'India';
      _behaviourCtrl.text = existing.behaviour ?? '';
      _timeCtrl.text = existing.observedTime ?? '';
      _notesCtrl.text = existing.observationNotes ?? '';
      _countCtrl.text = '${existing.individualCount ?? 1}';
      _habitat = existing.habitat;
      _locationPrecision = existing.locationPrecision;
      _breedingSite = existing.breedingSite;
      _contributorPrivacy = existing.contributorPrivacy;
      _observedAt = existing.observedAt ?? DateTime.now();
    } else {
      _loadContributorDefaults();
    }
  }

  Future<void> _loadContributorDefaults() async {
    final profile = await _service.fetchContributorProfile();
    if (!mounted || profile == null) return;
    setState(() {
      _contributorName = profile.displayName;
      _contributorPrivacy = profile.privacy;
      if ((profile.district ?? '').isNotEmpty) _districtCtrl.text = profile.district!;
      if ((profile.state ?? '').isNotEmpty) _stateCtrl.text = profile.state!;
    });
  }

  @override
  void dispose() {
    _commonNameCtrl.dispose();
    _bengaliNameCtrl.dispose();
    _scientificNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    _countryCtrl.dispose();
    _behaviourCtrl.dispose();
    _countCtrl.dispose();
    _notesCtrl.dispose();
    _timeCtrl.dispose();
    _latitudeCtrl.dispose();
    _longitudeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return;
      final allowed = picked
          .where((f) => SightingValidation.isAllowedExtension('photo', f.extension))
          .toList();
      if (allowed.isEmpty) {
        _snack('সমর্থিত ছবির ফরম্যাট: JPG, PNG, WEBP');
        return;
      }
      for (final file in allowed) {
        try {
          _photoPreviewBytes[file] = await file.readAsBytes();
        } catch (_) {}
      }
      setState(() {
        _photos.addAll(allowed);
        if (_photos.length > SightingValidation.maxPhotos) {
          _photos.removeRange(SightingValidation.maxPhotos, _photos.length);
        }
      });
    } catch (e) {
      _snack('ছবি নির্বাচন করা যায়নি: $e');
    }
  }

  Future<void> _pickMedia(
      String kind, FileType type, List<PlatformFile> target) async {
    try {
      final picked = await FilePicker.pickFiles(type: type);
      if (picked.isEmpty) return;
      final allowed = picked
          .where((f) => SightingValidation.isAllowedExtension(kind, f.extension))
          .toList();
      if (allowed.isEmpty) {
        _snack(kind == 'audio'
            ? 'সমর্থিত অডিও ফরম্যাট: MP3, M4A, WAV, OGG'
            : 'সমর্থিত ভিডিও ফরম্যাট: MP4, MOV, WEBM');
        return;
      }
      setState(() {
        target.addAll(allowed);
        final cap = SightingValidation.maxCountForKind(kind);
        if (target.length > cap) target.removeRange(cap, target.length);
      });
    } catch (e) {
      _snack('ফাইল নির্বাচন করা যায়নি: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _observedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: CitizenSciencePalette.accent,
            surface: CitizenSciencePalette.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _observedAt = picked);
  }

  void _nextStep() {
    if (_step == 0) {
      final error = SightingValidation.validateSpeciesName(_commonNameCtrl.text);
      if (error != null) {
        _snack(error);
        return;
      }
    }
    if (_step == 1 && _districtCtrl.text.trim().isEmpty) {
      _snack('অন্তত জেলার নাম লিখুন — প্রকাশ্যে শুধু সেটিই দেখানো হবে');
      return;
    }
    setState(() => _step = (_step + 1).clamp(0, 2));
  }

  void _previousStep() => setState(() => _step = (_step - 1).clamp(0, 2));

  Future<void> _submit({bool asDraft = false}) async {
    if (_isSubmitting) return;
    if (!asDraft) {
      final error = SightingValidation.validateSpeciesName(_commonNameCtrl.text);
      if (error != null) {
        _snack(error);
        return;
      }
    }

    // Soft duplicate detection — a warning, never a hard block.
    if (!asDraft && _commonNameCtrl.text.trim().isNotEmpty) {
      final duplicate = await _service.findDuplicate(
        commonName: _commonNameCtrl.text.trim(),
        observedAt: _observedAt,
        district: _districtCtrl.text.trim(),
      );
      if (duplicate != null && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: CitizenSciencePalette.surface,
            title: const Text('একই ধরনের দর্শন আগেই জমা হয়েছে',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: const Text(
              'একই প্রজাতি, একই তারিখ ও একই জেলার একটি দর্শন ইতিমধ্যে আপনার নামে জমা আছে। '
              'এটি যদি আলাদা পর্যবেক্ষণ হয়, তবে নিশ্চিত করে জমা দিন।',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('বাতিল', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('তবুও জমা দিন',
                    style: TextStyle(color: CitizenSciencePalette.accent)),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final sensitivity = SightingValidation.sensitivityFromIucn(
        _iucnStatus == 'unknown' ? null : _iucnStatus,
        current: _breedingSite ? 'critical' : 'normal',
      );

      double? latitude;
      double? longitude;
      if (_includeCoordinates &&
          SightingValidation.allowsPreciseCoordinates(sensitivity)) {
        latitude =
            SightingValidation.parseCoordinate(_latitudeCtrl.text, isLatitude: true);
        longitude = SightingValidation.parseCoordinate(_longitudeCtrl.text,
            isLatitude: false);
      }

      final sighting = await _service.submitSighting(
        commonName: _commonNameCtrl.text,
        bengaliName: _bengaliNameCtrl.text,
        scientificName: _scientificNameCtrl.text,
        description: _descriptionCtrl.text,
        observationNotes: _notesCtrl.text,
        iucnStatus: _iucnStatus == 'unknown' ? null : _iucnStatus,
        observedAt: _observedAt,
        observedTime: _timeCtrl.text,
        habitat: _habitat,
        individualCount: SightingValidation.parseCount(_countCtrl.text),
        behaviour: _behaviourCtrl.text,
        district: _districtCtrl.text,
        state: _stateCtrl.text,
        country: _countryCtrl.text,
        latitude: latitude,
        longitude: longitude,
        locationPrecision: _locationPrecision,
        breedingSite: _breedingSite,
        contributorPrivacy: _contributorPrivacy,
        contributorDisplayName: _contributorName,
        status: asDraft ? 'draft' : 'submitted',
        photos: _photos,
        audioClips: _audioClips,
        videoClips: _videoClips,
      );

      if (!mounted) return;
      setState(() {
        _created = sighting;
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    if (created != null) return _buildSuccessView(created);

    return Scaffold(
      backgroundColor: CitizenSciencePalette.background,
      appBar: AppBar(
        backgroundColor: CitizenSciencePalette.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            SoundService.playButtonSound();
            if (_step > 0) {
              _previousStep();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('বন্যপ্রাণ দর্শন রিপোর্ট',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            Text('আপনার পর্যবেক্ষণ আমাদের জানান',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
          children: [
            _buildStepIndicator(),
            const SizedBox(height: 18),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _step == 0
                  ? _buildSpeciesStep()
                  : _step == 1
                      ? _buildLocationStep()
                      : _buildObservationStep(),
            ),
            const SizedBox(height: 24),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    const titles = <String>['কী দেখেছেন?', 'কোথায়?', 'কখন ও কীভাবে?'];
    return Row(
      children: List<Widget>.generate(3, (index) {
        final active = index <= _step;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active
                        ? CitizenSciencePalette.accent
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${index + 1}. ${titles[index]}',
                  style: TextStyle(
                    color: active ? Colors.white70 : Colors.white30,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNavigationButtons() {
    final isLast = _step == 2;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CitizenSciencePalette.accent,
              foregroundColor: Colors.black,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed:
                _isSubmitting ? null : (isLast ? () => _submit() : _nextStep),
            child: _isSubmitting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('পাঠানো হচ্ছে...',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  )
                : Text(
                    isLast ? '📤 দর্শন জমা দিন' : 'পরবর্তী ➔',
                    style:
                        const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        if (isLast) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _isSubmitting ? null : () => _submit(asDraft: true),
            child: const Text('খসড়া হিসেবে সংরক্ষণ করুন',
                style: TextStyle(color: CitizenSciencePalette.accentSoft)),
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          'জমা দেওয়ার পরে সম্পাদকমণ্ডলী যাচাই করে প্রকাশ করবেন। প্রতিটি ধাপের বার্তা আপনি পাবেন।',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}
