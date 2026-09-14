import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/legal/legal_documents.dart';

void main() {
  test('legal documents are real copy, not coming-soon placeholders', () {
    for (final doc in LegalDocuments.all) {
      expect(doc.title, isNotEmpty);
      expect(doc.body.length, greaterThan(120));
      expect(doc.body.toLowerCase(), isNot(contains('coming soon')));
      expect(LegalDocuments.byPath(doc.routePath), same(doc));
    }
  });
}
