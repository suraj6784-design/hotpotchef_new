import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/legal/legal_documents.dart';
import 'package:hotpotchef_new/screens/legal_document_screen.dart';

void main() {
  test('legal documents are real copy, not coming-soon placeholders', () {
    for (final doc in LegalDocuments.all) {
      expect(doc.title, isNotEmpty);
      expect(doc.body.length, greaterThan(120));
      expect(doc.body.toLowerCase(), isNot(contains('coming soon')));
      expect(LegalDocuments.byPath(doc.routePath), same(doc));
    }
  });

  testWidgets('privacy screen renders policy body instead of a snackbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: LegalDocumentScreen(document: LegalDocuments.privacy)),
    );
    expect(find.text('Privacy policy'), findsWidgets);
    expect(find.textContaining('DPDP'), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
  });
}

