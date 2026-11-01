import 'package:flutter_test/flutter_test.dart';
import 'package:earanyak/models/kishor_medal.dart';

void main() {
  group('KishorMedalEligibility Data Contract Tests', () {
    test('Correctly parses successful medal eligibility from RPC payload', () {
      final payload = {
        'participant_id': 'usr-123456',
        'completed_level': 2,
        'category': 'nature_quiz',
        'achievement_id': 'bdg-789',
        'completion_timestamp': '2026-10-11T12:00:00.000Z',
        'is_eligible': true,
        'score': 8,
        'max_score': 10,
        'xp_awarded': 105,
      };

      final medal = KishorMedalEligibility.fromMap(payload);

      expect(medal.participantId, equals('usr-123456'));
      expect(medal.completedLevel, equals(2));
      expect(medal.category, equals('nature_quiz'));
      expect(medal.achievementId, equals('bdg-789'));
      expect(medal.isEligible, isTrue);
      expect(medal.score, equals(8));
      expect(medal.maxScore, equals(10));
      expect(medal.xpAwarded, equals(105));
    });

    test('Correctly parses non-eligible completion from RPC payload', () {
      final payload = {
        'participant_id': 'usr-123456',
        'completed_level': 3,
        'category': 'nature_quiz',
        'achievement_id': null,
        'completion_timestamp': '2026-10-11T12:05:00.000Z',
        'is_eligible': false,
        'score': 4,
        'max_score': 10,
        'xp_awarded': 40,
      };

      final medal = KishorMedalEligibility.fromMap(payload);

      expect(medal.participantId, equals('usr-123456'));
      expect(medal.completedLevel, equals(3));
      expect(medal.isEligible, isFalse);
      expect(medal.achievementId, isNull);
      expect(medal.score, equals(4));
    });

    test('Serializes to Map cleanly without huge fields', () {
      final medal = KishorMedalEligibility(
        participantId: 'usr-999',
        completedLevel: 1,
        category: 'general',
        achievementId: 'ach-1',
        completionTimestamp: DateTime.parse('2026-10-11T10:00:00.000Z'),
        isEligible: true,
        score: 10,
        maxScore: 10,
        xpAwarded: 125,
      );

      final map = medal.toMap();

      expect(map['participant_id'], equals('usr-999'));
      expect(map['completed_level'], equals(1));
      expect(map['is_eligible'], isTrue);
      expect(map.containsKey('participant_photograph'), isFalse);
      expect(map.containsKey('base64_image'), isFalse);
    });
  });
}
