class KishorMedalEligibility {
  final String participantId;
  final int completedLevel;
  final String category;
  final String? achievementId;
  final DateTime completionTimestamp;
  final bool isEligible;
  final int score;
  final int maxScore;
  final int xpAwarded;

  KishorMedalEligibility({
    required this.participantId,
    required this.completedLevel,
    this.category = 'general',
    this.achievementId,
    required this.completionTimestamp,
    required this.isEligible,
    required this.score,
    required this.maxScore,
    this.xpAwarded = 0,
  });

  factory KishorMedalEligibility.fromMap(Map<String, dynamic> map) {
    return KishorMedalEligibility(
      participantId: (map['participant_id'] ?? map['user_id'] ?? '').toString(),
      completedLevel: (map['completed_level'] ?? map['level_number'] ?? 1) as int,
      category: (map['category'] ?? 'general').toString(),
      achievementId: map['achievement_id']?.toString() ?? map['badge_id']?.toString(),
      completionTimestamp: map['completion_timestamp'] != null
          ? DateTime.parse(map['completion_timestamp'].toString())
          : (map['completed_at'] != null ? DateTime.parse(map['completed_at'].toString()) : DateTime.now()),
      isEligible: map['is_eligible'] == true || map['eligible'] == true,
      score: (map['score'] ?? 0) as int,
      maxScore: (map['max_score'] ?? 0) as int,
      xpAwarded: (map['xp_awarded'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participant_id': participantId,
      'completed_level': completedLevel,
      'category': category,
      'achievement_id': achievementId,
      'completion_timestamp': completionTimestamp.toIso8601String(),
      'is_eligible': isEligible,
      'score': score,
      'max_score': maxScore,
      'xp_awarded': xpAwarded,
    };
  }
}
