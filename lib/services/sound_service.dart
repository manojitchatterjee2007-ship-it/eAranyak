import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central, authoritative pool for significant-update notification sounds.
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

/// Shuffled pool specifically for the Boot Splash Screen (7 sounds)
class BootSoundPool {
  static const List<String> bootSounds = [
    'welcome_tone',
    'bird_call',
    'cricket',
    'deer_call',
    'elephant_trumpet',
    'owl_hoot',
    'tiger_roar',
  ];

  static List<String> _bag = [];
  static String? _lastConsumedSound;

  static Future<String> getNextSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastConsumedSound = prefs.getString('last_boot_sound');
      final savedBag = prefs.getStringList('boot_sound_bag');

      if (savedBag != null && savedBag.isNotEmpty) {
        _bag = List<String>.from(savedBag);
      }

      if (_bag.isEmpty) {
        _bag = List<String>.from(bootSounds)..shuffle();
        if (_bag.length > 1 && _bag.first == _lastConsumedSound) {
          final first = _bag.first;
          _bag[0] = _bag.last;
          _bag[_bag.length - 1] = first;
        }
      }

      final selected = _bag.removeAt(0);
      _lastConsumedSound = selected;

      await prefs.setString('last_boot_sound', selected);
      await prefs.setStringList('boot_sound_bag', _bag);

      return selected;
    } catch (_) {
      return bootSounds.first;
    }
  }
}

class SoundService {
  static final AudioPlayer _player = AudioPlayer();

  static final ValueNotifier<bool> keyPressSoundNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<bool> mutedNotifier =
      ValueNotifier<bool>(false);

  static bool get isMuted => mutedNotifier.value;
  static bool get isKeyPressSoundEnabled => keyPressSoundNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    keyPressSoundNotifier.value = prefs.getBool('key_press_sound_enabled') ?? false;
    mutedNotifier.value = prefs.getBool('sound_muted') ?? false;
  }

  static Future<void> setMuted(bool muted) async {
    mutedNotifier.value = muted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_muted', muted);

    if (muted) {
      await stopAllSounds();
    }
  }

  static Future<void> stopAllSounds() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  static Future<void> playBootSound() async {
    if (isMuted) return;
    try {
      final soundName = await BootSoundPool.getNextSound();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(AssetSource('audio/$soundName.mp3'), volume: 1.0);
    } catch (_) {}
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
    if (isMuted || !keyPressSoundNotifier.value) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/button_press.mp3'), volume: 0.45);
    } catch (_) {}
  }

  static Future<void> playWildlifeSound(String assetName) async {
    if (isMuted) return;
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
  static Future<void> playElephantTrumpet() => playWildlifeSound('elephant_trumpet.mp3');
}