import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/kyc_checklist.dart';

void main() {
  group('kycChecklistFor', () {
    test('driver denominator excludes FSSAI and kitchen name', () {
      final checklist = kycChecklistFor({
        'role': 'Driver',
        'name': 'Ravi',
      });
      expect(checklist.total, 7);
      expect(checklist.done, 1);
      expect(checklist.missing, isNot(contains('FSSAI number')));
      expect(checklist.missing, isNot(contains('FSSAI proof')));
      expect(checklist.missing, isNot(contains('FSSAI verified')));
      expect(checklist.missing, isNot(contains('Kitchen name')));
      expect(checklist.missing, containsAll(['Email', 'GSTIN', 'Bank account', 'IFSC', 'PAN', 'Aadhaar']));
    });

    test('driver FSSAI columns do not count toward progress', () {
      final checklist = kycChecklistFor({
        'role': 'Driver',
        'email': 'driver@example.com',
        'fssai_number': '11234567890123',
        'fssai_proof_url': 'https://example.com/fssai.jpg',
        'fssai_verification_status': 'verified',
        'local_kitchen_name': 'Should ignore',
      });
      expect(checklist.total, 7);
      expect(checklist.done, 1);
      expect(checklist.missing, isNot(contains(contains('FSSAI'))));
    });

    test('chef denominator includes FSSAI fields and kitchen name', () {
      final checklist = kycChecklistFor({
        'role': 'Chef',
        'name': 'Meera',
      });
      expect(checklist.total, 11);
      expect(checklist.done, 1);
      expect(
        checklist.missing,
        containsAll(['FSSAI number', 'FSSAI proof', 'FSSAI verified', 'Kitchen name']),
      );
    });

    test('chef complete when identity, payout, FSSAI, and kitchen are present', () {
      final checklist = kycChecklistFor({
        'role': 'Chef',
        'full_name': 'Meera Kitchen',
        'email': 'chef@example.com',
        'gstin': '27AAAAA0000A1Z5',
        'bank_account_number': '123456789012',
        'bank_ifsc': 'HDFC0001234',
        'pan_number': 'ABCDE1234F',
        'aadhaar_masked': 'XXXX-XXXX-1234',
        'fssai_number': '11234567890123',
        'fssai_proof_url': 'https://example.com/fssai.jpg',
        'fssai_verification_status': 'verified',
        'local_kitchen_name': 'Meera Home Kitchen',
      });
      expect(checklist.total, 11);
      expect(checklist.done, 11);
      expect(checklist.incomplete, isFalse);
      expect(checklist.missing, isEmpty);
    });

    test('driver complete without any FSSAI fields', () {
      final checklist = kycChecklistFor({
        'role': 'Driver',
        'name': 'Ravi',
        'email': 'driver@example.com',
        'gstin': '27AAAAA0000A1Z5',
        'bank_account_number': '123456789012',
        'ifsc_code': 'HDFC0001234',
        'pan_number': 'ABCDE1234F',
        'aadhaar_masked': 'XXXX-XXXX-1234',
      });
      expect(checklist.total, 7);
      expect(checklist.done, 7);
      expect(checklist.incomplete, isFalse);
    });
  });
}
