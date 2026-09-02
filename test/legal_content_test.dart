import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/legal_content.dart';

void main() {
  test('every help document has a title and at least three sections', () {
    for (final type in LegalDocumentType.values) {
      final doc = legalDocumentFor(type);
      expect(doc.title, isNotEmpty, reason: '$type title');
      expect(doc.sections.length, greaterThanOrEqualTo(3), reason: '$type sections');
      expect(doc.sections.every((s) => s.heading.isNotEmpty && s.body.isNotEmpty), isTrue);
    }
  });

  test('privacy policy says we do not sell personal information', () {
    final privacy = legalDocumentFor(LegalDocumentType.privacy);
    expect(
      privacy.sections.any((s) => s.body.toLowerCase().contains('do not sell')),
      isTrue,
    );
  });
}
