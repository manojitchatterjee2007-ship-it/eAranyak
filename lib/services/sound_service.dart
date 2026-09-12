import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static Future<void> playElephantTrumpet() => playWildlifeSound('elephant_trumpet.mp3');
}
