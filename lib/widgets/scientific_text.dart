import 'package:flutter/material.dart';

/// Renders text with automatic detection and formatting of scientific names.
/// Requirements:
/// 1. Genus and species names must be italicized (e.g. *Panthera tigris*)
/// 2. Genus name first letter capitalized, species lowercase.
/// 3. Bengali common names and normal text remain normal (not italicized).
/// 4. Surrounding Markdown asterisks are stripped so no literal asterisks appear to users.
class ScientificText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final bool selectable;

  const ScientificText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.selectable = false,
  });

  /// Regex matching:
  /// Group 1/2: Markdown wrapped binomial: *Panthera tigris*
  /// Group 3: Binomial Latin name: Panthera tigris (Genus lowercase-species)
  static final RegExp _scientificRegex = RegExp(
    r'(\*([A-Z][a-z]+\s+[a-z]+(?:\s+[a-z]+)?)\*|\b([A-Z][a-z]{2,}\s+[a-z]{2,}(?:\s+[a-z]{2,})?)\b)',
  );

  /// Words/phrases to exclude from scientific name italicization (e.g., brand names or proper nouns)
  static const Set<String> _exclusions = {
    'Google News',
    'Mongabay India',
    'Sanctuary Nature',
    'West Bengal',
    'New Delhi',
    'South Asia',
    'North America',
    'South America',
    'United States',
    'Sri Lanka',
  };

  static List<InlineSpan> buildSpans(String content, TextStyle baseStyle) {
    if (content.isEmpty) return const [];

    final List<InlineSpan> spans = [];
    int lastIndex = 0;

    for (final Match match in _scientificRegex.allMatches(content)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: content.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      final fullMatch = match.group(0)!;
      String scientificName = '';

      if (fullMatch.startsWith('*') && fullMatch.endsWith('*')) {
        scientificName = match.group(2) ?? fullMatch.replaceAll('*', '');
      } else if (!_exclusions.contains(fullMatch)) {
        // Verify candidate binomial: word1 starts with capital, word2 is lowercase
        final parts = fullMatch.split(RegExp(r'\s+'));
        if (parts.length >= 2 &&
            parts[0][0] == parts[0][0].toUpperCase() &&
            parts[1] == parts[1].toLowerCase() &&
            !RegExp(r'[\u0980-\u09FF]').hasMatch(fullMatch)) {
          scientificName = fullMatch;
        }
      }

      if (scientificName.isNotEmpty) {
        // Enforce Scientific Name Capitalization:
        // Genus: Capitalized (e.g. Panthera)
        // Species: Lowercase (e.g. tigris)
        final parts = scientificName.split(RegExp(r'\s+'));
        final formattedParts = parts.asMap().entries.map((entry) {
          final idx = entry.key;
          final word = entry.value;
          if (word.isEmpty) return word;
          if (idx == 0) {
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          } else {
            return word.toLowerCase();
          }
        }).join(' ');

        spans.add(TextSpan(
          text: formattedParts,
          style: baseStyle.copyWith(
            fontStyle: FontStyle.italic,
            fontWeight: baseStyle.fontWeight,
          ),
        ));
      } else {
        // Not a scientific name, render normally
        spans.add(TextSpan(
          text: fullMatch,
          style: baseStyle,
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final spans = buildSpans(text, style);

    if (selectable) {
      return SelectableText.rich(
        TextSpan(children: spans),
        textAlign: textAlign,
        maxLines: maxLines,
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
