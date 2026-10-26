import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Renders the AI report's light markup: "## " headings, "- " bullets, other lines as paragraphs.
class ReportText extends StatelessWidget {
  const ReportText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12, bottom: 4),
          child: Text(
            line.replaceFirst(RegExp(r'^#+\s*'), ''),
            style: const TextStyle(fontWeight: FontWeight.w800, color: BiviColors.forestLight),
          ),
        ));
      } else if (line.startsWith('- ') || line.startsWith('• ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(height: 1.5)),
              Expanded(child: Text(line.substring(2), style: const TextStyle(height: 1.5))),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line, style: const TextStyle(height: 1.5)),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
