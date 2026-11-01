import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/kishor_medal.dart';
import '../services/medal_composer_service.dart';
import '../services/medal_export_service.dart';

/// Builds, previews, saves and shares a personalised Kishor Aranyak medal.
///
/// The [level] always comes from a server-verified [KishorMedalEligibility]
/// result; this screen never invents or persists a completion of its own.
class KishorMedalScreen extends StatefulWidget {
  final int level;

  /// Server-reported eligibility, shown so the participant sees the real score.
  final KishorMedalEligibility? eligibility;

  const KishorMedalScreen({
    super.key,
    required this.level,
    this.eligibility,
  });

  @override
  State<KishorMedalScreen> createState() => _KishorMedalScreenState();
}

class _KishorMedalScreenState extends State<KishorMedalScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _photoBytes;
  double _focusX = 0.5;
  double _focusY = 0.42;
  double _zoom = 1.0;

  bool _rendering = false;
  bool _busy = false;
  bool _includeBackground = true;
  MedalRenderResult? _rendered;
  String? _error;

  @override
  void initState() {
    super.initState();
    _render();
  }

  MedalRequest get _request => MedalRequest(
        level: widget.level,
        photoBytes: _photoBytes,
        focusX: _focusX,
        focusY: _focusY,
        zoom: _zoom,
      );

  Future<void> _render() async {
    if (!mounted) return;
    setState(() {
      _rendering = true;
      _error = null;
    });
    try {
      final result = _includeBackground
          ? await MedalComposerService.renderMedalOnWelcomeBackground(_request)
          : await MedalComposerService.renderMedal(_request);
      if (!mounted) return;
      setState(() {
        _rendered = result;
        _rendering = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'মেডেল রেন্ডার করা যায়নি। (Could not render the medal.)';
        _rendering = false;
      });
    }
  }

  // ---------------------------------------------------------------- photo input

  /// Normalises an EXIF-rotated pick so portrait phone photos are not sideways.
  /// `image_picker` already applies EXIF orientation on Android and iOS, so we
  /// only guard against an unreadable or empty selection here.
  Future<Uint8List?> _readPicked(XFile? file) async {
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      // `package:image` is tolerant of format detection; reject obvious junk so
      // the participant gets a clear message instead of a silent fallback.
      if (bytes.length < 16) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickFromCamera() async {
    // A missing camera or a denied permission must not block the achievement:
    // the medal renders fine without a photograph.
    var status = await Permission.camera.status;
    if (status.isPermanentlyDenied) {
      _showMessage(
        'ক্যামেরা অনুমতি বন্ধ আছে। সেটিংস থেকে চালু করুন, অথবা গ্যালারি ব্যবহার করুন।\n'
        '(Camera permission is off. Enable it in Settings, or use the gallery.)',
      );
      return;
    }
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        _showMessage(
          status.isPermanentlyDenied
              ? 'ক্যামেরা অনুমতি স্থায়ীভাবে বাতিল। গ্যালারি ব্যবহার করুন।\n'
                  '(Camera permission permanently denied. Please use the gallery.)'
              : 'ক্যামেরা অনুমতি বাতিল। গ্যালরি থেকে ছবি নিতে পারেন।\n'
                  '(Camera permission denied. You can still pick from the gallery.)',
        );
        return;
      }
    }
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
        requestFullMetadata: false,
      );
      final bytes = await _readPicked(picked);
      if (bytes == null) {
        if (picked != null) {
          _showMessage(
            'ছবিটি পড়া যায়নি। অন্য একটি ছবি বেছে নিন।\n'
            '(That image could not be read. Please choose another.)',
          );
        }
        return;
      }
      setState(() {
        _photoBytes = bytes;
        _focusX = 0.5;
        _focusY = 0.42;
        _zoom = 1.0;
      });
      await _render();
    } catch (e) {
      _showMessage(
        'ক্যামেরা খোলা যায়নি (যন্ত্রে ক্যামেরা না থাকতে পারে)। গ্যালারি ব্যবহার করুন।\n'
        '(Could not open the camera — the device may not have one. '
        'Please use the gallery.)',
      );
    }
  }

  Future<void> _pickFromGallery() async {
    final status = await Permission.photos.status;
    if (status.isPermanentlyDenied) {
      _showMessage(
        'গ্যালারি অনুমতি বন্ধ আছে। সেটিংস থেকে চালু করুন।\n'
        '(Photo permission is off. Enable it in Settings.)',
      );
      return;
    }
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
        requestFullMetadata: false,
      );
      // Cancellation is a normal outcome: simply return without a message.
      if (picked == null) return;
      final bytes = await _readPicked(picked);
      if (bytes == null) {
        _showMessage(
          'ছবিটি পড়া যায়নি। অন্য একটি ছবি বেছে নিন।\n'
          '(That image could not be read. Please choose another.)',
        );
        return;
      }
      setState(() {
        _photoBytes = bytes;
        _focusX = 0.5;
        _focusY = 0.42;
        _zoom = 1.0;
      });
      await _render();
    } catch (e) {
      _showMessage(
        'গ্যালারি খোলা যায়নি।\n(Could not open the gallery.)',
      );
    }
  }

  // ------------------------------------------------------------------- export

  Future<void> _save() async {
    final render = _rendered;
    if (render == null) {
      _showMessage('আগে মেডেলটি তৈরি হোক।\n(Generate the medal first.)');
      return;
    }
    setState(() => _busy = true);
    final outcome = await MedalExportService.saveToGallery(
      render.pngBytes,
      level: widget.level,
      withBackground: render.width != render.height,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _showMessage(outcome.message);
  }

  Future<void> _share() async {
    final render = _rendered;
    if (render == null) {
      _showMessage('আগে মেডেলটি তৈরি হোক।\n(Generate the medal first.)');
      return;
    }
    setState(() => _busy = true);
    final outcome =
        await MedalExportService.shareImage(render, level: widget.level);
    if (!mounted) return;
    setState(() => _busy = false);
    _showMessage(outcome.message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF18221B),
        duration: const Duration(seconds: 4),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final render = _rendered;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14231A),
        foregroundColor: const Color(0xFFE7EFB7),
        title: Text(
          'কিশোর আরণ্যক পদক (Level ${widget.level})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ------------------------------------------------- medal preview
            AspectRatio(
              aspectRatio: render == null
                  ? 1
                  : render.width / render.height,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1109),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF28402D)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildPreview(render, theme),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _includeBackground
                  ? 'শেয়ারযোগ্য ছবি (৪:৫ ব্যাকগ্রাউন্ডসহ)'
                  : 'স্বচ্ছ মেডেল (পারদর্শী ছবি)',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFF9FB2A2)),
            ),
            const SizedBox(height: 16),

            // -------------------------------------------------- photo sources
            Row(
              children: [
                Expanded(
                  child: _sourceButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'ক্যামেরা',
                    onPressed: _busy || _rendering ? null : _pickFromCamera,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _sourceButton(
                    icon: Icons.photo_library_outlined,
                    label: 'গ্যালারি',
                    onPressed: _busy || _rendering ? null : _pickFromGallery,
                  ),
                ),
                if (_photoBytes != null) ...[
                  const SizedBox(width: 12),
                  _sourceButton(
                    icon: Icons.close,
                    label: 'ছবি সরান',
                    onPressed: _busy || _rendering
                        ? null
                        : () {
                            setState(() {
                              _photoBytes = null;
                              _focusX = 0.5;
                              _focusY = 0.42;
                              _zoom = 1.0;
                            });
                            _render();
                          },
                  ),
                ],
              ],
            ),


            // ---------------------------------------- pan / zoom crop controls
            if (_photoBytes != null) ...[
              const SizedBox(height: 8),
              _cropSlider(
                label: 'কাটছাঁট — ডান/বাম (crop left/right)',
                value: _focusX,
                onChanged: (v) => setState(() => _focusX = v),
                onEnd: _render,
              ),
              _cropSlider(
                label: 'কাটছাঁট — উপর/নিচ (crop top/bottom)',
                value: _focusY,
                onChanged: (v) => setState(() => _focusY = v),
                onEnd: _render,
              ),
              _cropSlider(
                label: 'জুম (zoom)',
                value: _zoom,
                min: 1.0,
                max: 2.5,
                onChanged: (v) => setState(() => _zoom = v),
                onEnd: _render,
              ),
            ],
            const SizedBox(height: 4),

            // ------------------------------------------------ background switch
            SwitchListTile(
              value: _includeBackground,
              onChanged:
                  _busy || _rendering ? null : _onBackgroundToggle,
              activeThumbColor: const Color(0xFFB7D97B),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'ব্যাকগ্রাউন্ডসহ ছবি (শেয়ার করার জন্য)',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: const Color(0xFFDDE7CE)),
              ),
              subtitle: Text(
                'বন্ধ করলে স্বচ্ছ PNG পাবেন। Off = transparent PNG.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFF8FA293)),
              ),
            ),

            // ------------------------------------------------------- error line
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFF2A6A6)),
                ),
              ),
            const SizedBox(height: 12),

            // ----------------------------------------------------- action row
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.download_outlined,
                    label: 'ডাউনলোড (Save)',
                    filled: true,
                    onPressed:
                        _busy || _rendering || render == null ? null : _save,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionButton(
                    icon: Icons.share_outlined,
                    label: 'শেয়ার (Share)',
                    filled: false,
                    onPressed:
                        _busy || _rendering || render == null ? null : _share,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }


  void _onBackgroundToggle(bool value) {
    setState(() => _includeBackground = value);
    _render();
  }

  // ------------------------------------------------------------------- pieces

  Widget _buildPreview(MedalRenderResult? render, ThemeData theme) {
    if (render != null) {
      return Image.memory(
        render.pngBytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            const Center(child: Text('ছবি দেখানো যায়নি। (Preview failed.)')),
      );
    }
    if (_rendering) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFB7D97B)),
      );
    }
    return const Center(
      child: Text(
        'মেডেল তৈরি হচ্ছে… (Generating…)',
        style: TextStyle(color: Color(0xFF8FA293)),
      ),
    );
  }

  Widget _sourceButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF213827),
        foregroundColor:
            enabled ? const Color(0xFFE7EFB7) : const Color(0xFF5E7566),
        disabledBackgroundColor: const Color(0xFF16241A),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _cropSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required VoidCallback onEnd,
    double min = 0.0,
    double max = 1.0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF9FB2A2)),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: const Color(0xFFB7D97B),
          inactiveColor: const Color(0xFF2A3F2E),
          onChanged: onChanged,
          onChangeEnd: (_) => onEnd(),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback? onPressed,
  }) {
    final busy = _busy;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFB7D97B),
              ),
            )
          : Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            filled ? const Color(0xFFB7D97B) : const Color(0xFF213827),
        foregroundColor:
            filled ? const Color(0xFF0E1712) : const Color(0xFFE7EFB7),
        disabledBackgroundColor: const Color(0xFF16241A),
        disabledForegroundColor: const Color(0xFF5E7566),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}


