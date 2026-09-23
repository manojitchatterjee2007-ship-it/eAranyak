import 'package:flutter/material.dart';

enum ForestEnvironmentType { library, bookshelf }

/// Legacy stub for Forest3dEnvironment. The application now uses
/// RealisticRackWidget with realistic image-based forest backgrounds
/// and rack overlays.
class Forest3dEnvironment extends StatelessWidget {
  final ForestEnvironmentType type;
  final Widget child;
  final int sceneIndex;

  const Forest3dEnvironment({
    super.key,
    required this.type,
    required this.child,
    this.sceneIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
