import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central, authoritative pool for significant-update notification sounds.
/// Contains all 5 animal/nature sounds and implements a shuffled-bag approach.
class NotificationSoundPool {
  static const List<String> notificationSounds = [
    'tiger_roar',
    'elephant_trumpet',
    'deer_call',
    'owl_hoot',
    'cricket',
  ];

  static List<String> _bag = [];
  static String? _lastConsumedSound;

  /// Selects the next sound using a shuffled-bag approach, avoiding
  /// immediate repetition across bag refills.
  static Future<String> getNextSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastConsumedSound = prefs.getString('last_notif_sound');
      final savedBag = prefs.getStringList('notif_sound_bag');

      if (savedBag != null && savedBag.isNotEmpty) {
        _bag = List<String>.from(savedBag);
      }

      if (_bag.isEmpty) {
        _bag = List<String>.from(notificationSounds)..shuffle();
        if (_bag.length > 1 && _bag.first == _lastConsumedSound) {
          final first = _bag.first;
          _bag[0] = _bag.last;
          _bag[_bag.length - 1] = first;
        }
      }

      final selected = _bag.removeAt(0);
      _lastConsumedSound = selected;

      await prefs.setString('last_notif_sound', selected);
      await prefs.setStringList('notif_sound_bag', _bag);

      return selected;
    } catch (_) {
      return notificationSounds.first;
    }
  }

  static String soundToAssetPath(String soundName) => 'audio/$soundName.mp3';
}

class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static final ValueNotifier<bool> keyPressSoundNotifier =
      ValueNotifier<bool>(false);

  static bool get isMuted => false;
  static bool get isKeyPressSoundEnabled => keyPressSoundNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    keyPressSoundNotifier.value =
        prefs.getBool('key_press_sound_enabled') ?? false;
  }

  static Future<void> setKeyPressSoundEnabled(bool enabled) async {
    keyPressSoundNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('key_press_sound_enabled', enabled);
  }

  static Future<void> toggleKeyPressSound() async {
    await setKeyPressSoundEnabled(!keyPressSoundNotifier.value);
  }

  static Future<void> playButtonSound() async {
    if (!keyPressSoundNotifier.value) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/button_press.mp3'), volume: 0.45);
    } catch (_) {}
  }

  static Future<void> playWildlifeSound(String assetName) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/$assetName'), volume: 0.5);
    } catch (_) {}
  }

  static Future<void> playOwlHoot() => playWildlifeSound('owl_hoot.mp3');
  static Future<void> playTigerRoar() => playWildlifeSound('tiger_roar.mp3');
  static Future<void> playBirdCall() => playWildlifeSound('bird_call.mp3');
  static Future<void> playCricket() => playWildlifeSound('cricket.mp3');
  static Future<void> playDeerCall() => playWildlifeSound('deer_call.mp3');
  static Future<void> playElephantTrumpet() =>
      playWildlifeSound('elephant_trumpet.mp3');
}
