import 'dart:async';
import 'package:flutter/material.dart';

class NatureBackgroundSwitcher extends StatefulWidget {
  const NatureBackgroundSwitcher({super.key});

  @override
  State<NatureBackgroundSwitcher> createState() =>
      _NatureBackgroundSwitcherState();
}

class _NatureBackgroundSwitcherState extends State<NatureBackgroundSwitcher> {
  final List<String> _bgAssets = [
    'assets/images/tribute_bg.jpg',
    'assets/images/bg2.png',
  ];
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final asset in _bgAssets) {
      precacheImage(AssetImage(asset), context);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 12), (timer) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _bgAssets.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(seconds: 4),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Image.asset(
        _bgAssets[_currentIndex],
        key: ValueKey<int>(_currentIndex),
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        errorBuilder: (c, e, s) => const SizedBox.shrink(),
      ),
    );
  }
}
