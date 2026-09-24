import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sound_service.dart';

class ForestAmbienceService {
  static bool get isPlaying => _player.state == PlayerState.playing;

  static final AudioPlayer _player = AudioPlayer();
  
  // The 3 specific ambient forest sounds
  static const List<String> ambienceSounds = [
    'forest-sound',
    'forest-ambience',
    'forest-river',
  ];

  static List<String> _bag = [];
  static String? _lastConsumedSound;

  static Future<void> startAmbience() async {
    if (SoundService.isMuted) return;

    // Ensure nothing is currently playing before starting a new track
    await stopAmbience();

    try {
      final prefs = await SharedPreferences.getInstance();
      _lastConsumedSound = prefs.getString('last_ambience_sound');
      final savedBag = prefs.getStringList('ambience_sound_bag');

      if (savedBag != null && savedBag.isNotEmpty) {
        _bag = List<String>.from(savedBag);
      }

      if (_bag.isEmpty) {
        _bag = List<String>.from(ambienceSounds)..shuffle();
        // Prevent immediate repetition across shuffles
        if (_bag.length > 1 && _bag.first == _lastConsumedSound) {
          final first = _bag.first;
          _bag[0] = _bag.last;
          _bag[_bag.length - 1] = first;
        }
      }

      final selected = _bag.removeAt(0);
      _lastConsumedSound = selected;

      await prefs.setString('last_ambience_sound', selected);
      await prefs.setStringList('ambience_sound_bag', _bag);

      // Loop the selected ambient track indefinitely
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('audio/$selected.mp3'), volume: 0.35);
    } catch (e) {
      // Fail silently if audio engine isn't ready
    }
  }

  static Future<void> stopAmbience() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}