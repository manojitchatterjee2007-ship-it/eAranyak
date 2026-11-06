import 'package:flutter/material.dart';

class LibraryIcon extends StatelessWidget {
  final bool isSelected;
  const LibraryIcon({super.key, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final assetPath = isSelected
        ? 'assets/images/library_animated.gif'
        : 'assets/images/library.png';

    final img = Image.asset(
      assetPath,
      key: ValueKey(isSelected),
      width: 48,
      height: 48,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Error loading Library icon $assetPath: $error');
        return Icon(
          Icons.local_library_rounded,
          size: 44,
          color: isSelected ? const Color(0xFF00E676) : Colors.white54,
        );
      },
    );

    if (isSelected) return img;
    return Opacity(
      opacity: 0.6,
      child: img,
    );
  }
}
