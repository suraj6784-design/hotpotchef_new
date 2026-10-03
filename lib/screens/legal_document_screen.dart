import 'package:flutter/material.dart';

import '../legal/legal_documents.dart' as audit_legal;
import '../utils/app_theme.dart';
import '../utils/legal_content.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    this.type,
    this.document,
  }) : assert(type != null || document != null);

  final LegalDocumentType? type;
  final audit_legal.LegalDocument? document;

  @override
  Widget build(BuildContext context) {
    final auditDoc = document;
    if (auditDoc != null) {
      return _AuditLegalView(document: auditDoc);
    }
    return _CreamLegalView(type: type!);
  }
}

class _CreamLegalView extends StatelessWidget {
  const _CreamLegalView({required this.type});

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

class _AuditLegalView extends StatelessWidget {
  const _AuditLegalView({required this.document});

  final audit_legal.LegalDocument document;

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
              document.body,
              style: TextStyle(fontSize: 15, height: 1.55, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
