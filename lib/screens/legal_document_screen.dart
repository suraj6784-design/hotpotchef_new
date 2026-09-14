import 'package:flutter/material.dart';

import '../legal/legal_documents.dart';
import '../utils/app_theme.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade300 : AppTheme.textMuted;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : AppTheme.background,
      appBar: AppBar(
        title: Text(document.title, style: TextStyle(color: textColor)),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(
              document.title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'HotPotChef · working draft for Test-mode dogfood',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 20),
            Text(
              document.body.trim(),
              style: TextStyle(fontSize: 15, height: 1.45, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
