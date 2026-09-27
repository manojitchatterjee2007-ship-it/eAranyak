import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/vanarakkhi_gamification_models.dart';

class VanarakkhiService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<VanarakkhiUserProgress?> getUserProgress() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _supabase
        .from('vanarakkhi_user_progress')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) {
      return VanarakkhiUserProgress(
        userId: userId,
        totalXp: 0,
        currentLevel: 1,
        unlockedSpecies: [],
      );
    }

    return VanarakkhiUserProgress.fromMap(response);
  }

  Future<List<VanarakkhiMission>> getMissions() async {
    final userId = _supabase.auth.currentUser?.id;
    final missionsResponse = await _supabase
        .from('vanarakkhi_missions')
        .select()
        .eq('is_active', true)
        .order('created_at');

    List<VanarakkhiMission> missions = [];
    if (userId != null) {
      final completionsResponse = await _supabase
          .from('vanarakkhi_mission_completions')
          .select('mission_id')
          .eq('user_id', userId);
          
      final completedMissionIds = (completionsResponse as List)
          .map((e) => e['mission_id'] as String)
          .toSet();

      for (var missionData in missionsResponse) {
        missions.add(VanarakkhiMission.fromMap(
          missionData,
          completed: completedMissionIds.contains(missionData['id']),
        ));
      }
    } else {
      for (var missionData in missionsResponse) {
        missions.add(VanarakkhiMission.fromMap(missionData));
      }
    }

    return missions;
  }

  Future<bool> completeMission(String missionId) async {
    try {
      final response = await _supabase.rpc('complete_mission', params: {'p_mission_id': missionId});
      return response as bool;
    } catch (e) {
      debugPrint('Error completing mission: $e');
      return false;
    }
  }

  Future<List<VanarakkhiBadge>> getBadges() async {
    final response = await _supabase
        .from('vanarakkhi_badges')
        .select()
        .eq('is_active', true);

    return (response as List)
        .map((e) => VanarakkhiBadge.fromMap(e))
        .toList();
  }

  Future<List<KishoreLearningModule>> getLearningModules() async {
    final response = await _supabase
        .from('kishore_learning_modules')
        .select()
        .eq('is_active', true)
        .order('created_at');

    return (response as List)
        .map((e) => KishoreLearningModule.fromMap(e))
        .toList();
  }
}
