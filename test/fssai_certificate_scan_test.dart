import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/fssai_certificate_scan.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  const demoCard = '''
Registration ID: 12345678912345
Valid Upto: 10-09-27
Name: Arushi Thakare
Address: Gurukrupa Complex,
Dange Chowk,
Thergaon Pune 411033
KOB: General Manufacturing, Permanent / Temporary Stall Holder
Govt ID Card: N/A
Issuing Authority: Sindhudurg
Issued On: 10-09-26
''';

  test('scans registration, name, address, and validity from an FSSAI card', () {
    final scan = parseFssaiCertificateText(demoCard);
    expect(scan.registrationNumber, '12345678912345');
    expect(scan.legalName, 'Arushi Thakare');
    expect(scan.address, contains('Gurukrupa Complex'));
    expect(scan.address, contains('Thergaon Pune 411033'));
    expect(scan.validUntil, DateTime(2027, 9, 10));
    expect(fssaiLicenceIsExpired(scan.validUntil, now: DateTime(2026, 9, 12)), isFalse);
    expect(fssaiLicenceIsExpired(scan.validUntil, now: DateTime(2027, 9, 11)), isTrue);
  });

  test('does not treat issued-on as validity', () {
    final scan = parseFssaiCertificateText(demoCard);
    expect(scan.validUntil, isNot(DateTime(2026, 9, 10)));
  });

  test('publish blocks when the scanned licence date has lapsed', () {
    expect(
      chefFssaiPublishBlockReason(
        fssaiNumber: '12345678912345',
        proofUrl: 'https://example.com/fssai.jpg',
        verificationStatus: 'verified',
        validUntil: DateTime(2026, 9, 10),
        now: DateTime(2026, 9, 12),
      ),
      contains('expired'),
    );
    expect(
      chefCanPublishWithFssai(
        fssaiNumber: '12345678912345',
        proofUrl: 'https://example.com/fssai.jpg',
        verificationStatus: 'verified',
        validUntil: DateTime(2027, 9, 10),
        now: DateTime(2026, 9, 12),
      ),
      isTrue,
    );
  });
}
