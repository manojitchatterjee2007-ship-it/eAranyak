import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/daily_wildlife_feature.dart';

import '../services/sound_service.dart';
import 'package:earanyak/widgets/animated_button_wrapper.dart';

class DailyWildlifeScreen extends StatefulWidget {
  final DailyWildlifeFeature feature;

  const DailyWildlifeScreen({super.key, required this.feature});

  @override
  State<DailyWildlifeScreen> createState() => _DailyWildlifeScreenState();
}

class _DailyWildlifeScreenState extends State<DailyWildlifeScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _toggleAudio() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (widget.feature.audioUrl != null && widget.feature.audioAvailable) {
        try {
          await _audioPlayer.stop();
          String url = widget.feature.audioUrl!;
          if (url.startsWith('//')) {
            url = 'https:$url';
          }
          await _audioPlayer.play(UrlSource(url));
        } catch (e) {
          debugPrint('DailyWildlife: Error playing audio URL - $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('অডিও সংযোগে সমস্যা হচ্ছে (Failed to load audio)')),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Builder(
                  builder: (_) {
                    final hero =
                        feature.displayImageUrl ?? feature.verifiedOriginalImageUrl;
                if (hero != null && hero.isNotEmpty) {
                  return CachedNetworkImage(
                    imageUrl: hero,
                    cacheKey: feature.imageCacheKey,
                    height: 400,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF00E676),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 220,
                      alignment: Alignment.center,
                      color: const Color(0xFF142419),
                      padding: const EdgeInsets.all(24),
                      child: const Text(
                        'চিত্র লোড করা যায়নি',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  );
                }
                return Container(
                  height: 220,
                  alignment: Alignment.center,
                  color: const Color(0xFF142419),
                  padding: const EdgeInsets.all(24),
                  child: const Text(
                    'মূল ছবি যাচাই করা যায়নি — তথ্য নিচে দেখুন',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                );
              },
            ),
            
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('আজকের বন্যপ্রাণী', style: TextStyle(color: Color(0xFF00E676), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text(
                    feature.titleBn ?? feature.title,
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  if (feature.scientificName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      feature.scientificName!,
                      style: const TextStyle(color: Colors.white70, fontSize: 18, fontStyle: FontStyle.italic),
                    ),
                  ],
                  if ((feature.commonName ?? '').isNotEmpty &&
                      feature.commonName != feature.title) ...[
                    const SizedBox(height: 4),
                    Text(
                      feature.commonName!,
                      style: const TextStyle(color: Colors.white54, fontSize: 15),
                    ),
                  ],
                  if ((feature.iucnStatus ?? feature.conservationStatus ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142419),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        'IUCN: ${feature.iucnStatus ?? feature.conservationStatus}',
                        style: const TextStyle(color: Color(0xFF00E676), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (feature.audioAvailable && feature.audioUrl != null && feature.audioUrl!.trim().isNotEmpty)
                    InkWell(
                      onTap: _toggleAudio,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF142419),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Color(0xFF00E676),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'পাখির ডাক শুনুন (Bird Call)',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (_isPlaying) ...[
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Playing...',
                                      style: TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    AnimatedButtonWrapper(child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.volume_off),
                      label: const Text('ডাক উপলব্ধ নেই (Audio Unavailable)'),
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white54,
                      ),
                    )),
                  const SizedBox(height: 24),
                  
                  if (feature.descriptionBn != null && feature.descriptionBn!.isNotEmpty) ...[
                    Text(
                      feature.descriptionBn!,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                  ] else if (feature.speciesDescription != null && feature.speciesDescription!.isNotEmpty) ...[
                    Text(
                      feature.speciesDescription!,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (feature.habitat != null && feature.habitat!.isNotEmpty) ...[
                    _buildInfoChip(Icons.landscape, 'আবাসস্থল (Habitat)', feature.habitat!),
                    const SizedBox(height: 12),
                  ],
                  
                  if (feature.distribution != null && feature.distribution!.isNotEmpty) ...[
                    _buildInfoChip(Icons.map, 'ভৌগলিক বিস্তার (Distribution)', feature.distribution!),
                    const SizedBox(height: 12),
                  ],

                  if (feature.diet != null && feature.diet!.isNotEmpty) ...[
                    _buildInfoChip(Icons.restaurant, 'খাদ্যাভ্যাস (Diet)', feature.diet!),
                    const SizedBox(height: 12),
                  ],
                  
                  if (feature.behaviour != null && feature.behaviour!.isNotEmpty) ...[
                    _buildInfoChip(Icons.psychology, 'আচরণ (Behaviour)', feature.behaviour!),
                    const SizedBox(height: 12),
                  ],

                  if (feature.ecologicalRole != null && feature.ecologicalRole!.isNotEmpty) ...[
                    _buildInfoChip(Icons.eco, 'পরিবেশগত ভূমিকা (Ecological Role)', feature.ecologicalRole!),
                    const SizedBox(height: 12),
                  ],

                  if (feature.conservationStatus != null && feature.conservationStatus!.isNotEmpty) ...[
                    _buildInfoChip(Icons.security, 'সংরক্ষণ অবস্থা (Status)', feature.conservationStatus!),
                    const SizedBox(height: 12),
                  ],
                  
                  if (feature.iucnStatus != null && feature.iucnStatus!.isNotEmpty) ...[
                    _buildInfoChip(Icons.public, 'আইইউসিএন (IUCN) অবস্থা', feature.iucnStatus!),
                    const SizedBox(height: 12),
                  ],

                  if (feature.interestingFacts != null && feature.interestingFacts!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('আকর্ষণীয় তথ্য (Interesting Facts)', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      feature.interestingFacts!,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                    ),
                  ],
                  
                  if (feature.didYouKnow != null && feature.didYouKnow!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('আপনি কি জানেন? (Did You Know?)', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      feature.didYouKnow!,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text('ছবি ও তথ্যসূত্র', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final credit = feature.formattedImageCredit;
                    final refs = feature.formattedSourceRefs;
                    // CC compliance: always show a human credit line when we
                    // have any provenance — never the raw JSON blob.
                    if (credit == null && refs.isEmpty) {
                      return const Text(
                        'ছবি: iNaturalist / Wikimedia Commons (CC)',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (credit != null) ...[
                          Text(
                            'ছবি: $credit',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                        ],
                        for (final r in refs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'উৎস: $r',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                      ],
                    );
                  }),
                    if (feature.audioAttribution != null && feature.audioAttribution!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'অডিও: ${feature.audioAttribution}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                SoundService.playButtonSound();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF00E676), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
