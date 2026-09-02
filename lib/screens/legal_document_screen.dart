import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/legal_content.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final doc = legalDocumentFor(type);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppTheme.textMain;
    final muted = isDark ? Colors.white70 : AppTheme.textMuted;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.background,
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Last updated ${doc.updated}', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 16),
          for (final section in doc.sections) ...[
            Text(
              section.heading,
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              section.body,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
