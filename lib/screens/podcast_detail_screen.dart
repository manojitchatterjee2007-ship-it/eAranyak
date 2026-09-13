import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/podcast.dart';
import '../services/sound_service.dart';
import '../widgets/keyboard_press_effect.dart';
import '../widgets/nature_background.dart';

class PodcastDetailScreen extends StatefulWidget {
  final Podcast podcast;
  const PodcastDetailScreen({super.key, required this.podcast});

  @override
  State<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<PodcastDetailScreen> {
  late final AudioPlayer _audioPlayer;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  bool _isLoadingAudio = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudioListeners();
    _playAudio();
  }

  void _initAudioListeners() {
    _posSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _position = p;
        });
      }
    });

    _durSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() {
          _duration = d;
        });
      }
    });

    _stateSub = _audioPlayer.onPlayerStateChanged.listen((s) {
      if (mounted) {
        setState(() {
          _playerState = s;
          if (s == PlayerState.playing) {
            _isLoadingAudio = false;
          }
        });
      }
    });
  }

  String? _resolveAudioUrl() {
    if (widget.podcast.audioUrl != null && widget.podcast.audioUrl!.trim().isNotEmpty) {
      return widget.podcast.audioUrl!.trim();
    }
    if (widget.podcast.storagePath != null && widget.podcast.storagePath!.trim().isNotEmpty) {
      return Supabase.instance.client.storage
          .from('podcasts')
          .getPublicUrl(widget.podcast.storagePath!.trim());
    }
    return null;
  }

  Future<void> _playAudio() async {
    final url = _resolveAudioUrl();
    if (url == null || url.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'অডিও ফাইল উপলব্ধ নেই (Audio file not available)';
      });
      return;
    }

    setState(() {
      _isLoadingAudio = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAudio = false;
          _hasError = true;
          _errorMessage = 'অডিও প্লে করতে ব্যর্থ হয়েছে / Unable to play audio';
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    SoundService.playButtonSound();
    if (_hasError) {
      await _playAudio();
      return;
    }

    if (_playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else if (_playerState == PlayerState.paused) {
      await _audioPlayer.resume();
    } else {
      await _playAudio();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    SoundService.playButtonSound();
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    await _audioPlayer.seek(clamped);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      final hours = twoDigits(d.inHours);
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  void _sharePodcast() {
    SoundService.playButtonSound();
    final audioUrl = _resolveAudioUrl() ?? '';
    final text = '🎙️ eAranyak Podcast Episode #${widget.podcast.episodeNumber ?? ''}\n'
        '${widget.podcast.title}\n\n'
        '${widget.podcast.snippet ?? widget.podcast.description ?? ''}\n\n'
        'Listen in eAranyak App! $audioUrl';
    Share.share(text, subject: widget.podcast.title);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final podcast = widget.podcast;
    final totalDurationSec = podcast.durationSeconds ?? 0;
    final effectiveMaxSec = _duration.inSeconds > 0
        ? _duration.inSeconds.toDouble()
        : (totalDurationSec > 0 ? totalDurationSec.toDouble() : 1.0);
    final currentPosSec = _position.inSeconds.toDouble().clamp(0.0, effectiveMaxSec);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1410).withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        title: Text(
          podcast.episodeNumber != null
              ? 'পর্ব ${podcast.episodeNumber} / Episode #${podcast.episodeNumber}'
              : 'পডকাস্ট পর্ব / Podcast Episode',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF00E676)),
            tooltip: 'শেয়ার করুন / Share',
            onPressed: _sharePodcast,
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: Opacity(
              opacity: 0.3,
              child: NatureBackgroundSwitcher(),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Podcast Thumbnail Artwork
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      color: const Color(0xFF142419),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E676).withValues(alpha: 0.2),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: podcast.thumbnailUrl != null && podcast.thumbnailUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: podcast.thumbnailUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(color: Color(0xFF00E676)),
                              ),
                              errorWidget: (_, __, ___) => Image.asset(
                                'assets/images/podcast.png',
                                fit: BoxFit.contain,
                              ),
                            )
                          : Image.asset(
                              'assets/images/podcast.png',
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Badges (Featured, Episode, Category)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (podcast.isFeatured)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFD54F)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD54F)),
                              SizedBox(width: 4),
                              Text(
                                'বিশেষ / Featured',
                                style: TextStyle(
                                  color: Color(0xFFFFD54F),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (podcast.episodeNumber != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: Text(
                            'পর্ব #${podcast.episodeNumber}',
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (podcast.category != null && podcast.category!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            podcast.category!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    podcast.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Date
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: Color(0xFF81C784), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'প্রকাশ: ${_formatDate(podcast.publishedAt ?? podcast.createdAt)}',
                        style: const TextStyle(
                          color: Color(0xFF81C784),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Audio Control Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18221B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        if (_hasError) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage ?? 'Error loading audio',
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _playAudio,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('পুনরায় চেষ্টা করুন / Retry'),
                          ),
                        ] else ...[
                          // Seekbar Slider
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF00E676),
                              inactiveTrackColor: Colors.white12,
                              thumbColor: const Color(0xFF00E676),
                              overlayColor: const Color(0xFF00E676).withValues(alpha: 0.2),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: currentPosSec,
                              min: 0.0,
                              max: effectiveMaxSec,
                              onChanged: (val) {
                                setState(() {
                                  _position = Duration(seconds: val.toInt());
                                });
                              },
                              onChangeEnd: (val) async {
                                await _audioPlayer.seek(Duration(seconds: val.toInt()));
                              },
                            ),
                          ),

                          // Timestamps Row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                Text(
                                  _duration > Duration.zero
                                      ? _formatDuration(_duration)
                                      : (podcast.formattedDuration),
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Controls Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Replay 10s
                              IconButton(
                                iconSize: 36,
                                icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                                tooltip: '১০ সেকেন্ড পিছনে',
                                onPressed: () => _seekRelative(-10),
                              ),
                              const SizedBox(width: 20),

                              // Play / Pause Button
                              KeyboardPressEffect(
                                onTap: _togglePlayPause,
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E676),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                                        blurRadius: 16,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: _isLoadingAudio
                                        ? const SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              color: Colors.black,
                                              strokeWidth: 3,
                                            ),
                                          )
                                        : Icon(
                                            _playerState == PlayerState.playing
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            size: 40,
                                            color: Colors.black,
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),

                              // Forward 10s
                              IconButton(
                                iconSize: 36,
                                icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                                tooltip: '১০ সেকেন্ড সামনে',
                                onPressed: () => _seekRelative(10),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Episode Description / Snippet
                  if ((podcast.description != null && podcast.description!.trim().isNotEmpty) ||
                      (podcast.snippet != null && podcast.snippet!.trim().isNotEmpty)) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF142419),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.description_rounded, size: 16, color: Color(0xFF00E676)),
                            SizedBox(width: 6),
                            Text(
                              'পর্বের বিবরণ (Description)',
                              style: TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18221B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: SelectableText(
                        (podcast.description?.isNotEmpty == true
                            ? podcast.description!
                            : podcast.snippet!),
                        style: const TextStyle(
                          color: Color(0xE6FFFFFF),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
