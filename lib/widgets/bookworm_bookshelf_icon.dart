import 'package:flutter/material.dart';

class BookwormBookshelfIcon extends StatelessWidget {
  final bool isSelected;
  const BookwormBookshelfIcon({super.key, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final assetPath = isSelected
        ? 'assets/images/bookworm_bookshelf_animated.gif'
        : 'assets/images/bookworm_bookshelf.png';

    final img = Image.asset(
      assetPath,
      key: ValueKey(isSelected),
      width: 48,
      height: 48,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Error loading Bookworm Bookshelf icon $assetPath: $error');
        return Icon(
          Icons.collections_bookmark_rounded,
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
