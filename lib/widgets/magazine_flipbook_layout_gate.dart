import 'package:flutter/material.dart';

/// Keeps size-dependent flipbook state unmounted until its viewport is usable.
class MagazineFlipbookLayoutGate extends StatelessWidget {
  const MagazineFlipbookLayoutGate({
    super.key,
    required this.builder,
    this.loading,
  });

  final Widget Function(BuildContext context, BoxConstraints constraints)
      builder;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0) {
          return loading ??
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E676)),
              );
        }
        return builder(context, constraints);
      },
    );
  }
}
