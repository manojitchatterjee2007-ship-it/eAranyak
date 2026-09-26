
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/daily_wildlife_feature.dart';

import '../services/sound_service.dart';

class DailyWildlifeScreen extends StatelessWidget {
  final DailyWildlifeFeature feature;

  const DailyWildlifeScreen({Key? key, required this.feature}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            SoundService.playButtonSound();
            Navigator.of(context).pop();
          },
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (feature.watercolourImageUrl != null)
              CachedNetworkImage(
                imageUrl: feature.watercolourImageUrl!,
                height: 400,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              )
            else if (feature.originalImageUrl != null)
              CachedNetworkImage(
                imageUrl: feature.originalImageUrl!,
                height: 400,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
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
                  const SizedBox(height: 24),

                  if (feature.habitat != null && feature.habitat!.isNotEmpty) ...[
                    _buildInfoChip(Icons.landscape, 'Habitat', feature.habitat!),
                    const SizedBox(height: 12),
                  ],
                  
                  if (feature.conservationStatus != null && feature.conservationStatus!.isNotEmpty) ...[
                    _buildInfoChip(Icons.security, 'Status', feature.conservationStatus!),
                    const SizedBox(height: 12),
                  ],

                  if (feature.interestingFacts != null && feature.interestingFacts!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Interesting Facts / জানেন কি?', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      feature.interestingFacts!,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                    ),
                  ],
                  
                  if (feature.didYouKnow != null && feature.didYouKnow!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Did You Know?', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      feature.didYouKnow!,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                    ),
                  ],

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00E676), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 14),
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

