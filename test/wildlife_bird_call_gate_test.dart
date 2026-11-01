import 'package:flutter_test/flutter_test.dart';
import 'package:earanyak/screens/home_screen.dart';

void main() {
  group('WildlifeLiveObservation bird-call gating', () {
    WildlifeLiveObservation build({
      required String source,
      String scientificName = 'Columba livia',
      String? iconicTaxon,
    }) {
      return WildlifeLiveObservation(
        id: 'obs-1',
        commonName: 'Common Pigeon',
        scientificName: scientificName,
        location: 'Lower Subansiri',
        observedAt: '2026-10-05',
        source: source,
        iconicTaxon: iconicTaxon,
      );
    }

    test('iNaturalist bird identified to species shows the play button', () {
      final observation = build(source: 'iNaturalist', iconicTaxon: 'Aves');
      expect(observation.isBird, isTrue);
      expect(observation.hasBinomialScientificName, isTrue);
    });

    test('iNaturalist non-bird never shows the play button', () {
      for (final iconic in <String?>['Insecta', 'Mammalia', 'Plantae', null]) {
        final observation =
            build(source: 'iNaturalist', iconicTaxon: iconic);
        expect(observation.isBird, isFalse, reason: 'iconic=$iconic');
      }
    });

    test('iNaturalist bird identified only to genus is not playable', () {
      final observation = build(
        source: 'iNaturalist',
        scientificName: 'Upupa',
        iconicTaxon: 'Aves',
      );
      expect(observation.isBird, isTrue);
      expect(observation.hasBinomialScientificName, isFalse);
    });

    test('eBird stays playable without an iconic taxon', () {
      final observation = build(source: 'eBird');
      expect(observation.isBird, isTrue);
      expect(observation.hasBinomialScientificName, isTrue);
    });

    test('copyWith keeps the bird classification', () {
      final observation = build(source: 'iNaturalist', iconicTaxon: 'Aves');
      final verified = observation.copyWith(
        sourceLocationVerified: true,
        location: 'Kolkata, West Bengal',
      );
      expect(verified.isBird, isTrue);
      expect(verified.iconicTaxon, 'Aves');
      expect(verified.sourceLocationVerified, isTrue);
    });

    test('fromMap parses the live feed iconic_taxon field', () {
      final observation = WildlifeLiveObservation.fromMap(<String, dynamic>{
        'id': 'inaturalist-1',
        'source': 'iNaturalist',
        'common_name': 'Indian Roller',
        'scientific_name': 'Coracias benghalensis',
        'location': 'Kolkata, West Bengal',
        'observed_at': '2026-10-05',
        'iconic_taxon': 'Aves',
      });
      expect(observation.isBird, isTrue);
      expect(observation.hasBinomialScientificName, isTrue);
    });
  });
}
