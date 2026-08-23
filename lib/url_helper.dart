import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchExternalNewsUrl(BuildContext context, String urlString) async {
  // Clean up any trailing/leading whitespace from the source link string
  final cleanUrl = urlString.trim();
  final Uri? uri = Uri.tryParse(cleanUrl);

  if (uri == null || (!uri.hasScheme)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invalid or corrupted source link address.')),
    );
    return;
  }

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      throw 'Could not launch $cleanUrl';
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open external link: $e')),
      );
    }
  }
}