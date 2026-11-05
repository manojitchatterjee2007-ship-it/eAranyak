import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/daily_wildlife_feature.dart';
import '../screens/daily_wildlife_screen.dart';
import '../services/sound_service.dart';
import 'package:earanyak/widgets/animated_button_wrapper.dart';

/// Daily wildlife photo card. Front = verified high-resolution source photo
/// (no oil-painting conversion), back = Gemini info bullets.
class DailyWildlifeOilCard extends StatefulWidget {
  final DailyWildlifeFeature feature;
  final double imageHeight;
  const DailyWildlifeOilCard({super.key, required this.feature, this.imageHeight = 220});
  @override
  State<DailyWildlifeOilCard> createState() => _DailyWildlifeOilCardState();
}

class _DailyWildlifeOilCardState extends State<DailyWildlifeOilCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  late final Animation<double> _angle;
  bool _showingBack = false;
  bool _busy = false;
  DailyWildlifeFeature get _f => widget.feature;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _angle = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _flip, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() { _flip.dispose(); super.dispose(); }

  Future<void> _toggle() async {
    if (_busy) return;
    final reduce = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    SoundService.playButtonSound();
    if (reduce) {
      setState(() => _showingBack = !_showingBack);
      _flip.value = _showingBack ? 1.0 : 0.0;
      return;
    }
    _busy = true;
    try {
      if (_showingBack) { await _flip.reverse(); } else { await _flip.forward(); }
      if (mounted) setState(() => _showingBack = !_showingBack);
    } finally { _busy = false; }
  }

  void _open() {
    SoundService.playButtonSound();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DailyWildlifeScreen(feature: _f)));
  }

  List<String> _bullets() {
    final out = <String>[];
    void add(String? v) {
      final t = (v ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) return;
      out.add(t.length > 110 ? '${t.substring(0, 109).trim()}…' : t);
    }
    add(_f.habitat);
    add(_f.behaviour);
    final st = (_f.iucnStatus ?? _f.conservationStatus ?? '').trim();
    if (st.isNotEmpty) out.add('IUCN: $st');
    add(_f.didYouKnow ?? _f.interestingFacts);
    return out.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF142419),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: AnimatedBuilder(
              animation: _angle,
              builder: (context, _) {
                final back = _angle.value >= math.pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(_angle.value),
                  child: SizedBox(
                    height: widget.imageHeight,
                    width: double.infinity,
                    child: back
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(math.pi),
                            child: _back(),
                          )
                        : _front(),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_f.titleBn ?? _f.title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if ((_f.scientificName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_f.scientificName!,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, fontStyle: FontStyle.italic)),
                ],
                Row(
                  children: [
                    AnimatedButtonWrapper(child: TextButton.icon(
                      onPressed: _toggle,
                      icon: Icon(_showingBack ? Icons.image : Icons.info_outline,
                          size: 18, color: const Color(0xFF00E676)),
                      label: Text(_showingBack ? 'ছবি দেখুন' : 'তথ্য দেখুন',
                          style: const TextStyle(color: Color(0xFF00E676))),
                    )),
                    const Spacer(),
                    AnimatedButtonWrapper(child: TextButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.open_in_new, size: 18, color: Colors.white70),
                      label: const Text('বিস্তারিত',
                          style: TextStyle(color: Colors.white70)),
                    )),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _front() {
    final url = _f.displayImageUrl;
    if (url == null || url.isEmpty) return _empty();
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: url,
          cacheKey: _f.imageCacheKey,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: const Color(0xFF0D1A10),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00E676)),
            ),
          ),
          errorWidget: (_, __, ___) => _empty(fail: true),
        ),
        if (_f.formattedImageCredit != null) ...[
          Positioned(
            left: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: const Color(0xCC07130B),
                  borderRadius: const BorderRadius.all(Radius.circular(6))),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'ছবি: ${_f.formattedImageCredit}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _empty({bool fail = false}) {
    return Container(
      color: const Color(0xFF0D1A10),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(18),
      child: Text(
        fail ? 'ছবি প্রস্তুত হচ্ছে / যাচাই করা যায়নি' : 'ছবি উপলব্ধ নেই',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );
  }

  Widget _back() {
    final items = _bullets();
    return Container(
      color: const Color(0xFF0D1A10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('সংক্ষিপ্ত তথ্য',
              style: TextStyle(color: Color(0xFF00E676), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Text('তথ্য যুক্ত হচ্ছে…',
                    style: TextStyle(color: Colors.white70, fontSize: 13))
                : ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ',
                            style: TextStyle(color: Color(0xFF00E676), fontSize: 13)),
                        Expanded(
                          child: Text(items[i],
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
          ),
          const Text('ট্যাপ করলে ছবি / তথ্য বদলাবে',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
