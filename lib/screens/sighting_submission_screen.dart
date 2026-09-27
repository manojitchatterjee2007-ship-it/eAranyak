import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/wildlife_sighting.dart';
import '../services/citizen_science_service.dart';
import '../services/sighting_validation.dart';
import '../services/sound_service.dart';
import '../widgets/citizen_science/sighting_card.dart';

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
  final TextEditingController _individualCountCtrl = TextEditingController(text: '1');
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _timeCtrl = TextEditingController();
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();
  final TextEditingController _habitatCtrl = TextEditingController();
  final TextEditingController _behaviourNotesCtrl = TextEditingController();
  final TextEditingController _customAttributionCtrl = TextEditingController();

  DateTime _observedDate = DateTime.now();
  TimeOfDay? _observedTime;
  final String _iucnStatus = 'unknown';
  String _locationPrecision = 'district';
  bool _isNestingOrRoost = false;
  String _attributionPreference = 'real_name';
  final bool _includeCoordinates = false;
  String? _selectedLifeStage;
  String? _selectedBehaviour;

  final List<PlatformFile> _photos = <PlatformFile>[];
  final List<PlatformFile> _audioClips = <PlatformFile>[];
  final List<PlatformFile> _videoClips = <PlatformFile>[];
  final Map<PlatformFile, Uint8List> _photoPreviewBytes =
      <PlatformFile, Uint8List>{};

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
      _individualCountCtrl.text = '${existing.individualCount ?? 1}';
      _habitatCtrl.text = existing.habitat ?? '';
      _locationPrecision = existing.locationPrecision;
      _isNestingOrRoost = existing.breedingSite;
      _attributionPreference = existing.contributorPrivacy == 'anonymous' ? 'anonymous' : 'real_name';
      _customAttributionCtrl.text = existing.contributorDisplayName ?? '';
      _observedDate = existing.observedAt ?? DateTime.now();
      if (existing.observedTime != null) {
        final parts = existing.observedTime!.split(':');
        if (parts.length >= 2) {
          _observedTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
        }
      }
    } else {
      _loadContributorDefaults();
    }
  }

  Future<void> _loadContributorDefaults() async {
    final profile = await _service.fetchContributorProfile();
    if (!mounted || profile == null) return;
    setState(() {
      _customAttributionCtrl.text = profile.displayName;
      _attributionPreference = profile.privacy == 'anonymous' ? 'anonymous' : 'real_name';
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
    _individualCountCtrl.dispose();
    _notesCtrl.dispose();
    _timeCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _habitatCtrl.dispose();
    _behaviourNotesCtrl.dispose();
    _customAttributionCtrl.dispose();
    super.dispose();
  }

  void _removePhoto(int index) {
    setState(() {
      final photo = _photos.removeAt(index);
      _photoPreviewBytes.remove(photo);
    });
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _observedDate,
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
    if (picked != null) setState(() => _observedDate = picked);
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
        observedAt: _observedDate,
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
        current: _isNestingOrRoost ? 'critical' : 'normal',
      );

      double? latitude;
      double? longitude;
      if (_includeCoordinates &&
          SightingValidation.allowsPreciseCoordinates(sensitivity)) {
        latitude =
            SightingValidation.parseCoordinate(_latCtrl.text, isLatitude: true);
        longitude = SightingValidation.parseCoordinate(_lngCtrl.text,
            isLatitude: false);
      }

      final sighting = await _service.submitSighting(
        commonName: _commonNameCtrl.text,
        bengaliName: _bengaliNameCtrl.text,
        scientificName: _scientificNameCtrl.text,
        description: _descriptionCtrl.text,
        observationNotes: _notesCtrl.text,
        iucnStatus: _iucnStatus == 'unknown' ? null : _iucnStatus,
        observedAt: _observedDate,
        observedTime: _observedTime != null
            ? '${_observedTime!.hour.toString().padLeft(2, '0')}:${_observedTime!.minute.toString().padLeft(2, '0')}'
            : null,
        habitat: _habitatCtrl.text,
        individualCount: SightingValidation.parseCount(_individualCountCtrl.text),
        behaviour: _selectedBehaviour ?? _behaviourCtrl.text,
        district: _districtCtrl.text,
        state: _stateCtrl.text,
        country: _countryCtrl.text,
        latitude: latitude,
        longitude: longitude,
        locationPrecision: _locationPrecision,
        breedingSite: _isNestingOrRoost,
        contributorPrivacy: _attributionPreference,
        contributorDisplayName: _customAttributionCtrl.text,
        status: asDraft ? 'draft' : 'submitted',
        photos: _photos,
        audioClips: _audioClips,
        videoClips: _videoClips,
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SightingSuccessScreen(sighting: sighting),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Navigation is handled via pushReplacement now
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
                  ? _buildStep1()
                  : _step == 1
                      ? _buildStep2()
                      : _buildStep3(),
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


  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          '১. বন্যপ্রাণীর আলোকচিত্র',
          'সর্বোচ্চ ৫টি ছবি আপলোড করতে পারেন (প্রতিটি সর্বোচ্চ ১০ মেগাবাইট)',
          Icons.photo_library_outlined,
        ),
        const SizedBox(height: 12),
        _buildPhotoPickerGrid(),
        const SizedBox(height: 24),
        _buildSectionTitle(
          '২. আপনি কী দেখেছেন?',
          'সাধারণ বাংলা বা ইংরেজি নাম লিখুন (বৈজ্ঞানিক নাম জানা না থাকলেও ক্ষতি নেই)',
          Icons.nature_outlined,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _bengaliNameCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: _inputDecoration(
            label: 'বাংলা নাম *',
            hint: 'যেমন: মেছো বিড়াল, লাল ঘুঘু, পদ্ম গোখরো',
            prefixIcon: Icons.edit_outlined,
          ),
          validator: (v) {
            final val = v?.trim() ?? '';
            final eng = _commonNameCtrl.text.trim();
            if (val.isEmpty && eng.isEmpty) {
              return 'বাংলা অথবা সাধারণ নাম লিখুন';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _commonNameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'ইংরেজি / সাধারণ নাম (ঐচ্ছিক)',
            hint: 'Fishing Cat, Red Turtle Dove, etc.',
            prefixIcon: Icons.language,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _scientificNameCtrl,
          style: const TextStyle(
              color: Colors.white, fontStyle: FontStyle.italic),
          decoration: _inputDecoration(
            label: 'বৈজ্ঞানিক নাম (যদি জানা থাকে — সম্পাদকমণ্ডলী যাচাই করবেন)',
            hint: 'Prionailurus viverrinus',
            prefixIcon: Icons.school_outlined,
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionTitle(
          '৩. বন্যপ্রাণীর সংখ্যা ও আচরণ',
          'আপনি কী ধরনের আচরণ লক্ষ্য করেছেন?',
          Icons.visibility_outlined,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _individualCountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  label: 'সংখ্যা',
                  hint: '১',
                  prefixIcon: Icons.format_list_numbered,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedLifeStage,
                dropdownColor: CitizenSciencePalette.surfaceAlt,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  label: 'অবস্থা',
                  prefixIcon: Icons.pets_outlined,
                ),
                items: const [
                  DropdownMenuItem(value: 'adult', child: Text('পূর্ণবয়স্ক')),
                  DropdownMenuItem(value: 'juvenile', child: Text('কিশোর / ছানা')),
                  DropdownMenuItem(value: 'larva', child: Text('কীটপতঙ্গের শূককীট')),
                  DropdownMenuItem(value: 'egg', child: Text('ডিম / বাসা')),
                  DropdownMenuItem(value: 'mixed', child: Text('মিশ্র দল')),
                  DropdownMenuItem(value: 'unknown', child: Text('অজ্ঞাত')),
                ],
                onChanged: (v) => setState(() => _selectedLifeStage = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedBehaviour,
          dropdownColor: CitizenSciencePalette.surfaceAlt,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'প্রধান আচরণ',
            prefixIcon: Icons.psychology_outlined,
          ),
          items: const [
            DropdownMenuItem(value: 'বিশ্রামরত', child: Text('বিশ্রামরত')),
            DropdownMenuItem(value: 'খাদ্যগ্রহণ / শিকাররত', child: Text('খাদ্যগ্রহণ / শিকাররত')),
            DropdownMenuItem(value: 'বিচরণ / ওড়া', child: Text('বিচরণ / ওড়া')),
            DropdownMenuItem(value: 'ডাক / গান', child: Text('ডাক / গান')),
            DropdownMenuItem(value: 'বাসা তৈরি / প্রজনন', child: Text('বাসা তৈরি / প্রজনন')),
            DropdownMenuItem(value: 'সতর্ক / পলায়নরত', child: Text('সতর্ক / পলায়নরত')),
            DropdownMenuItem(value: 'অন্যান্য', child: Text('অন্যান্য')),
          ],
          onChanged: (v) => setState(() => _selectedBehaviour = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _behaviourNotesCtrl,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'আচরণের বিশদ বিবরণ (ঐচ্ছিক)',
            hint: 'যেমন: বাঁশবাগানে ছোট মাছ শিকার করছিল...',
          ),
        ),
      ],
    );
  }




  Widget _buildPhotoPickerGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              InkWell(
                onTap: _photos.length >= 5 ? null : _pickPhotos,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: CitizenSciencePalette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _photos.length >= 5
                          ? Colors.white12
                          : CitizenSciencePalette.accent.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        color: _photos.length >= 5
                            ? Colors.white24
                            : CitizenSciencePalette.accent,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ছবি যোগ করুন\n(${_photos.length}/৫)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _photos.length >= 5
                              ? Colors.white24
                              : Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ..._photos.asMap().entries.map((entry) {
                final idx = entry.key;
                final photo = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 100,
                          height: 100,
                          color: Colors.black26,
                          child: _photoPreviewBytes[photo] != null
                              ? Image.memory(
                                  _photoPreviewBytes[photo]!,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.image, color: Colors.white24),
                        ),
                      ),
                      if (idx == 0)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('মূল ছবি',
                                style: TextStyle(
                                    color: CitizenSciencePalette.accent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () => _removePhoto(idx),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '🔒 আলোকচিত্রগুলি সুরক্ষিতভাবে আপলোড হবে এবং সর্বসাধারণে সরাসরি লিঙ্ক প্রকাশিত হবে না।',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          '৪. স্থান ও গোপনীয়তা',
          'আমরা কখনোই সংবেদনশীল প্রাণীর নিখুঁত অবস্থান সর্বসাধারণে প্রকাশ করি না।',
          Icons.shield_outlined,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CitizenSciencePalette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: CitizenSciencePalette.accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gps_fixed,
                      size: 16, color: CitizenSciencePalette.accent),
                  const SizedBox(width: 8),
                  const Text('জিপিএস স্থানাঙ্ক (ঐচ্ছিক)',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: CitizenSciencePalette.accent,
                    ),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('আমার অবস্থান নিন',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _fetchCurrentLocation,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration(
                        label: 'অক্ষাংশ (Lat)',
                        hint: '22.5726',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration(
                        label: 'দ্রাঘিমাংশ (Lng)',
                        hint: '88.3639',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'নিখুঁত স্থানাঙ্ক ডেটাবেসে সুরক্ষিত থাকবে। কেবল সম্পাদকগণ দেখতে পাবেন।',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _locationPrecision,
          dropdownColor: CitizenSciencePalette.surfaceAlt,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'সাধারণের জন্য অবস্থানের মাত্রা',
            prefixIcon: Icons.lock_outline,
          ),
          items: const [
            DropdownMenuItem(
                value: 'district',
                child: Text('জেলা পর্যায়ে সাধারণীকরণ (প্রস্তাবিত)')),
            DropdownMenuItem(
                value: 'locality',
                child: Text('এলাকা পর্যায়ে (প্রায় ৫ কিমি পরিসর)')),
            DropdownMenuItem(
                value: 'state',
                child: Text('রাজ্য পর্যায়ে (সর্বাধিক গোপনীয়তা)')),
            DropdownMenuItem(
                value: 'exact',
                child: Text('সরাসরি স্থানাঙ্ক (সাধারণ পাখির ক্ষেত্রে)')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _locationPrecision = v);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _districtCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  label: 'জেলা *',
                  hint: 'হাওড়া, বাঁকুড়া, দার্জিলিং ইত্যাদি',
                  prefixIcon: Icons.location_city,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'জেলার নাম আবশ্যক'
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _stateCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  label: 'রাজ্য',
                  hint: 'পশ্চিমবঙ্গ',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _habitatCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'আবাসস্থল / পরিবেশ',
            hint: 'শালবন, আর্দ্রভূমি, নদীর পাড়, কৃষি জমি, শহুরে বাগান',
            prefixIcon: Icons.forest_outlined,
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _isNestingOrRoost,
          activeColor: CitizenSciencePalette.accent,
          checkColor: Colors.black,
          contentPadding: EdgeInsets.zero,
          title: const Text('এটি কি বাসা, বাচ্চা প্রতিপালন বা আশ্রয়ের স্থান?',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: const Text(
            'সংবেদনশীল প্রজনন অঞ্চল চিহ্নিত হলে স্বয়ংক্রিয়ভাবে বর্ধিত গোপনীয়তা প্রয়োগ করা হবে।',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          onChanged: (v) => setState(() => _isNestingOrRoost = v ?? false),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle(
          '৫. দর্শনের তারিখ ও সময়',
          'কখন আপনি এটি প্রত্যক্ষ করেছেন?',
          Icons.calendar_today_outlined,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.date_range,
                    color: CitizenSciencePalette.accent, size: 18),
                label: Text(
                  '${_observedDate.year}-${_observedDate.month.toString().padLeft(2, '0')}-${_observedDate.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.access_time,
                    color: CitizenSciencePalette.accent, size: 18),
                label: Text(
                  _observedTime != null
                      ? _observedTime!.format(context)
                      : 'সময় বাছুন',
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: _selectTime,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          '৬. পর্যবেক্ষণের বিশদ বিবরণ',
          'অন্যান্য প্রকৃতিপ্রেমী ও গবেষকদের জন্য গুরুত্বপূর্ণ তথ্য',
          Icons.description_outlined,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionCtrl,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'দর্শনের বিবরণ *',
            hint: 'প্রাণীটি কী অবস্থায় ছিল? পরিবেশ কেমন ছিল? কোন বিশেষ আচরণ লক্ষ্য করেছিলেন?',
          ),
          validator: (v) {
            final val = v?.trim() ?? '';
            if (val.length < 10) {
              return 'অন্তত ১০টি অক্ষরে বিস্তারিত বিবরণ দিন';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesCtrl,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(
            label: 'সম্পাদকদের উদ্দেশ্যে কোনো নোট (ঐচ্ছিক)',
            hint: 'যেমন: ছবিটি অনেক দূর থেকে তোলা, প্রজাতি শনাক্তকরণে সাহায্য চাই...',
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionTitle(
          '৭. অবদানকারী পরিচিতি',
          'সর্বসাধারণে আপনার নাম কীভাবে প্রদর্শিত হবে?',
          Icons.badge_outlined,
        ),
        const SizedBox(height: 12),
        RadioGroup<String>(
          groupValue: _attributionPreference,
          onChanged: (v) {
            if (v != null) setState(() => _attributionPreference = v);
          },
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'real_name',
                activeColor: CitizenSciencePalette.accent,
                title: const Text('আমার নাম প্রকাশ করুন',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: const Text('যেমন: নজরদারি: মনোজিত রায়',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              if (_attributionPreference == 'real_name') ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: TextFormField(
                    controller: _customAttributionCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      label: 'যে নামে স্বীকৃতি চান',
                      hint: 'আপনার নাম / ডাকনাম',
                      prefixIcon: Icons.person_outline,
                    ),
                  ),
                ),
              ],
              RadioListTile<String>(
                value: 'pseudonym',
                activeColor: CitizenSciencePalette.accent,
                title: const Text('ছদ্মনামে প্রকাশ করুন',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              RadioListTile<String>(
                value: 'anonymous',
                activeColor: CitizenSciencePalette.accent,
                title: const Text('বেনামে প্রকাশ করুন (গোপনীয়)',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: const Text('সর্বসাধারণে কোনো নাম দৃশ্যমান হবে না',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CitizenSciencePalette.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 16, color: CitizenSciencePalette.accent),
                  SizedBox(width: 8),
                  Text('নাগরিক বিজ্ঞানের নীতি',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
              SizedBox(height: 6),
              Text(
                '• বন্যপ্রাণীকে কোনোভাবেই বিরক্ত বা ক্ষতিসাধন না করে ছবি তুলুন।\n'
                '• মিথ্যা বা ইন্টারনেট থেকে সংগৃহীত অন্য কারও ছবি জমা দেওয়া দণ্ডনীয়।\n'
                '• সম্পাদকগণ প্রয়োজনে সঠিক বৈজ্ঞানিক নাম এবং সংবেদনশীলতা হালনাগাদ করবেন।',
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, String subtitle, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: CitizenSciencePalette.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: CitizenSciencePalette.accentSoft, size: 20)
          : null,
      filled: true,
      fillColor: CitizenSciencePalette.surfaceAlt,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: CitizenSciencePalette.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _observedTime ?? TimeOfDay.now(),
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
    if (time != null) setState(() => _observedTime = time);
  }

  Future<void> _fetchCurrentLocation() async {
    _snack('অক্ষাংশ ও দ্রাঘিমাংশ প্রবেশ করুন অথবা জেলা নির্দিষ্ট করুন');
  }
}

class SightingSuccessScreen extends StatelessWidget {
  final WildlifeSighting sighting;

  const SightingSuccessScreen({super.key, required this.sighting});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CitizenSciencePalette.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: CitizenSciencePalette.surface,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: CitizenSciencePalette.accent, size: 54),
              ),
              const SizedBox(height: 20),
              const Text(
                'আপনার দর্শন সফলভাবে জমা হয়েছে!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                sighting.displaySpeciesName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CitizenSciencePalette.accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CitizenSciencePalette.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    _row(Icons.tag, 'আইডি', sighting.id.length >= 8 ? sighting.id.substring(0, 8) : sighting.id),
                    const Divider(color: Colors.white10),
                    _row(Icons.location_on_outlined, 'স্থান',
                        sighting.publicLocationLabel ?? sighting.district ?? 'ভারত'),
                    const Divider(color: Colors.white10),
                    _row(Icons.hourglass_empty, 'বর্তমান অবস্থা',
                        sighting.statusLabelBn),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'আমাদের বন্যপ্রাণী সম্পাদকমণ্ডলী এটি যাচাই করবেন। কোনো অতিরিক্ত তথ্যের প্রয়োজন হলে বা দর্শনটি প্রকাশিত হলে আপনি নোটিফিকেশনের মাধ্যমে জানতে পারবেন।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CitizenSciencePalette.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('নাগরিক বিজ্ঞান পাতায় ফিরে যান',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: CitizenSciencePalette.accentSoft),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
