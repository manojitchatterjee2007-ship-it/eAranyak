class KishoreLearningModule {
  final String id;
  final String titleBn;
  final String? descriptionBn;
  final String category;
  final int difficultyLevel;
  final Map<String, dynamic>? contentPayload;

  KishoreLearningModule({
    required this.id,
    required this.titleBn,
    this.descriptionBn,
    required this.category,
    required this.difficultyLevel,
    this.contentPayload,
  });

  factory KishoreLearningModule.fromMap(Map<String, dynamic> map) {
    return KishoreLearningModule(
      id: map['id'],
      titleBn: map['title_bn'] ?? '',
      descriptionBn: map['description_bn'],
      category: map['category'] ?? '',
      difficultyLevel: map['difficulty_level'] ?? 1,
      contentPayload: map['content_payload'],
    );
  }
}

class VanarakkhiMission {
  final String id;
  final String titleBn;
  final String? descriptionBn;
  final String category;
  final String difficulty;
  final int xpReward;
  final String? educationalExplanation;
  final Map<String, dynamic>? completionCriteria;
  final bool isCompleted;

  VanarakkhiMission({
    required this.id,
    required this.titleBn,
    this.descriptionBn,
    required this.category,
    required this.difficulty,
    required this.xpReward,
    this.educationalExplanation,
    this.completionCriteria,
    this.isCompleted = false,
  });

  factory VanarakkhiMission.fromMap(Map<String, dynamic> map, {bool completed = false}) {
    return VanarakkhiMission(
      id: map['id'],
      titleBn: map['title_bn'] ?? '',
      descriptionBn: map['description_bn'],
      category: map['category'] ?? 'WILDLIFE',
      difficulty: map['difficulty'] ?? 'easy',
      xpReward: map['xp_reward'] ?? 10,
      educationalExplanation: map['educational_explanation'],
      completionCriteria: map['completion_criteria'],
      isCompleted: completed,
    );
  }
}

class VanarakkhiBadge {
  final String id;
  final String nameBn;
  final String? descriptionBn;
  final String? iconUrl;
  final Map<String, dynamic>? criteria;

  VanarakkhiBadge({
    required this.id,
    required this.nameBn,
    this.descriptionBn,
    this.iconUrl,
    this.criteria,
  });

  factory VanarakkhiBadge.fromMap(Map<String, dynamic> map) {
    return VanarakkhiBadge(
      id: map['id'],
      nameBn: map['name_bn'] ?? '',
      descriptionBn: map['description_bn'],
      iconUrl: map['icon_url'],
      criteria: map['criteria'],
    );
  }
}

class VanarakkhiUserProgress {
  final String userId;
  final int totalXp;
  final int currentLevel;
  final List<String> unlockedSpecies;

  VanarakkhiUserProgress({
    required this.userId,
    required this.totalXp,
    required this.currentLevel,
    required this.unlockedSpecies,
  });

  factory VanarakkhiUserProgress.fromMap(Map<String, dynamic> map) {
    return VanarakkhiUserProgress(
      userId: map['user_id'],
      totalXp: map['total_xp'] ?? 0,
      currentLevel: map['current_level'] ?? 1,
      unlockedSpecies: List<String>.from(map['unlocked_species'] ?? []),
    );
  }
}

class VanarakkhiChallenge {
  final String id;
  final String titleBn;
  final String? descriptionBn;
  final int xpReward;
  final String? speciesId;
  final Map<String, dynamic>? tasks;

  VanarakkhiChallenge({
    required this.id,
    required this.titleBn,
    this.descriptionBn,
    required this.xpReward,
    this.speciesId,
    this.tasks,
  });

  factory VanarakkhiChallenge.fromMap(Map<String, dynamic> map) {
    return VanarakkhiChallenge(
      id: map['id'],
      titleBn: map['title_bn'] ?? '',
      descriptionBn: map['description_bn'],
      xpReward: map['xp_reward'] ?? 20,
      speciesId: map['species_id'],
      tasks: map['tasks'],
    );
  }
}

class VanarakkhiQuestionSet {
  final String id;
  final String titleBn;
  final List<dynamic> questions;

  VanarakkhiQuestionSet({
    required this.id,
    required this.titleBn,
    required this.questions,
  });

  factory VanarakkhiQuestionSet.fromMap(Map<String, dynamic> map) {
    return VanarakkhiQuestionSet(
      id: map['id'],
      titleBn: map['title_bn'] ?? '',
      questions: map['questions'] ?? [],
    );
  }
}
