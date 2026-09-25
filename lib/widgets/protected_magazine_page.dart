import 'package:flutter/material.dart';
import '../models/content_protection_models.dart';
import 'protected_content.dart';
import 'protected_image.dart';

/// Renders a single protected magazine page.
class ProtectedMagazinePage extends StatelessWidget {
  final String magazineId;
  final String storagePath;
  final String userIdentity;
  final BoxFit fit;

  const ProtectedMagazinePage({
    super.key,
    required this.magazineId,
    required this.storagePath,
    required this.userIdentity,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return ProtectedContent(
      scope: ContentProtectionScope.magazine,
      contentId: magazineId,
      userIdentity: userIdentity,
      child: ProtectedImage(
        bucket: 'magazine_pages',
        storagePath: storagePath,
        fit: fit,
      ),
    );
  }
}
