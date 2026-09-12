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
    expect(scan.address, isNot(contains('KOB')));
    expect(scan.address, isNot(contains('Manufacturing')));
    expect(scan.address, isNot(contains('Stall Holder')));
    expect(scan.validUntil, DateTime(2027, 9, 10));
    expect(fssaiLicenceIsExpired(scan.validUntil, now: DateTime(2026, 9, 12)), isFalse);
    expect(fssaiLicenceIsExpired(scan.validUntil, now: DateTime(2027, 9, 11)), isTrue);
  });

  test('reads a two-column OCR dump (labels then values)', () {
    const twoColumn = '''
Registration ID:
Valid Upto:
Name:
Address:
KOB:
12345678912345
10-09-27
Arushi Thakare
Gurukrupa Complex
Dange Chowk
Thergaon Pune 411033
General Manufacturing
''';
    final scan = parseFssaiCertificateText(twoColumn);
    expect(scan.registrationNumber, '12345678912345');
    expect(scan.legalName, 'Arushi Thakare');
    expect(scan.address, contains('Gurukrupa Complex'));
    expect(scan.address, isNot(contains('KOB')));
    expect(scan.address, isNot(contains('General Manufacturing')));
    expect(scan.validUntil, DateTime(2027, 9, 10));
    expect(scan.hasCoreFields, isTrue);
  });

  test('does not put the premises address in Name, and still reads Valid Upto', () {
    const messy = '''
FSSAI
Registration Certificate
Registration ID
Valid Upto
Name of Food Business Operator
Address of Premises
KOB
12345678912345
10-09-27
Arushi Thakare
Gurukrupa Complex
Dange Chowk
Thergaon Pune 411033
General Manufacturing
Issued On
10-09-26
''';
    final scan = parseFssaiCertificateText(messy);
    expect(scan.registrationNumber, '12345678912345');
    expect(scan.legalName, 'Arushi Thakare');
    expect(scan.legalName, isNot(contains('Gurukrupa')));
    expect(scan.address, contains('Gurukrupa Complex'));
    expect(scan.address, contains('411033'));
    expect(scan.address, isNot(contains('KOB')));
    expect(scan.address, isNot(contains('General Manufacturing')));
    expect(scan.validUntil, DateTime(2027, 9, 10));
  });

  test('reads a month-name validity date and ignores issued-on when it is earlier', () {
    final scan = parseFssaiCertificateText(
      'Registration ID 12345678912345 Issued On 10-09-26 Valid Upto 10 Sep 2027 Name: Arushi Thakare Address: Gurukrupa Complex, Dange Chowk',
    );
    expect(scan.validUntil, DateTime(2027, 9, 10));
    expect(scan.legalName, 'Arushi Thakare');
  });

  test('reads labels and values jammed on one line', () {
    final scan = parseFssaiCertificateText(
      'Registration ID: 12345678912345 Valid Upto: 10-09-27 Name: Arushi Thakare Address: Gurukrupa Complex, Dange Chowk KOB: Petty',
    );
    expect(scan.registrationNumber, '12345678912345');
    expect(scan.validUntil, DateTime(2027, 9, 10));
    expect(scan.legalName, contains('Arushi'));
    expect(scan.address, contains('Gurukrupa Complex'));
    expect(scan.address, isNot(contains('KOB')));
    expect(scan.address, isNot(contains('Petty')));
  });

  test('drops Kind of Business when OCR glues it onto the premises line', () {
    final scan = parseFssaiCertificateText(
      'Registration ID: 12345678912345 Valid Upto: 10-09-27 Name: Arushi Thakare '
      'Address of Premises: Gurukrupa Complex, Dange Chowk, Thergaon Pune 411033 '
      'Kind of Business Petty Manufacturer of food items, Permanent / Temporary Stall Holder',
    );
    expect(scan.address, contains('Thergaon Pune 411033'));
    expect(scan.address, isNot(contains('Kind of Business')));
    expect(scan.address, isNot(contains('Petty Manufacturer')));
    expect(scan.address, isNot(contains('Stall Holder')));
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
