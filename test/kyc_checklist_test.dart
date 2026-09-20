import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/kyc_checklist.dart';
import 'package:hotpotchef_new/widgets/chef_onboarding_coach.dart';

void main() {
  test('chef KYC requires FSSAI and pin, not GSTIN or PAN', () {
    final incomplete = kycChecklistFor({
      'role': 'chef',
      'name': 'Asha',
      'phone': '9999999999',
      'fssai_number': '11234567890123',
      'fssai_proof_url': 'https://example.com/fssai.jpg',
      'fssai_verification_status': 'pending',
      'lat': 18.5,
      'lng': 73.8,
    });
    expect(incomplete.missing, isNot(contains('FSSAI verified')));
    expect(incomplete.missing, contains('Aadhaar card'));
    expect(incomplete.missing, isNot(contains('GSTIN')));
    expect(incomplete.missing, isNot(contains('PAN')));
    expect(incomplete.payoutMissing, containsAll(['Bank account', 'IFSC']));

    final live = kycChecklistFor({
      'role': 'chef',
      'name': 'Asha',
      'phone': '9999999999',
      'fssai_number': '11234567890123',
      'fssai_proof_url': 'https://example.com/fssai.jpg',
      'fssai_verification_status': 'verified',
      'aadhaar_proof_url': 'https://example.com/aadhaar.jpg',
      'lat': 18.5,
      'lng': 73.8,
      'bank_account_number': '****1234',
      'bank_ifsc': 'HDFC0001234',
    });
    expect(live.incomplete, isFalse);
    expect(live.payoutMissing, isEmpty);
  });

  test('chef payout IFSC prefers bank_ifsc over a stale ifsc_code', () {
    final live = kycChecklistFor({
      'role': 'chef',
      'name': 'Asha',
      'phone': '9999999999',
      'fssai_number': '11234567890123',
      'fssai_proof_url': 'https://example.com/fssai.jpg',
      'fssai_verification_status': 'verified',
      'aadhaar_proof_url': 'https://example.com/aadhaar.jpg',
      'lat': 18.5,
      'lng': 73.8,
      'bank_account_number': '****1234',
      'ifsc_code': '',
      'bank_ifsc': 'HDFC0001234',
    });
    expect(live.payoutMissing, isEmpty);

    final staleOnly = kycChecklistFor({
      'role': 'chef',
      'name': 'Asha',
      'phone': '9999999999',
      'fssai_number': '11234567890123',
      'fssai_proof_url': 'https://example.com/fssai.jpg',
      'fssai_verification_status': 'verified',
      'aadhaar_proof_url': 'https://example.com/aadhaar.jpg',
      'lat': 18.5,
      'lng': 73.8,
      'bank_account_number': '****1234',
      'ifsc_code': 'SBIN0001234',
    });
    expect(staleOnly.payoutMissing, isEmpty);
  });

  test('driver KYC still requires vehicle, PAN and Aadhaar', () {
    final row = kycChecklistFor({
      'role': 'driver',
      'name': 'Ravi',
      'phone': '9999999999',
    });
    expect(row.missing, containsAll(['PAN', 'Aadhaar', 'Aadhaar card', 'Driving licence', 'Insurance policy', 'Vehicle type', 'Vehicle number']));
    expect(row.missing, isNot(contains('FSSAI number')));
  });

  test('driver KYC turns complete after licence, insurance, and Aadhaar photos', () {
    final row = kycChecklistFor({
      'role': 'driver',
      'name': 'Ravi',
      'phone': '9999999999',
      'bank_account_number': '****1234',
      'bank_ifsc': 'HDFC0001234',
      'pan_number': 'ABCDE1234F',
      'aadhaar_masked': 'XXXX-XXXX-4556',
      'aadhaar_proof_url': 'https://example.com/aadhaar.jpg',
      'driving_license_url': 'https://example.com/dl.jpg',
      'insurance_policy_url': 'https://example.com/ins.jpg',
      'vehicle_type': '2-Wheeler (Petrol)',
      'vehicle_reg_no': 'MH12AB1234',
    });
    expect(row.incomplete, isFalse);
  });

  test('diners and admins are not scored on kitchen FSSAI', () {
    for (final role in ['customer', 'admin']) {
      final row = kycChecklistFor({
        'role': role,
        'name': 'Arushi',
        'fssai_verification_status': 'unsubmitted',
      });
      expect(row.incomplete, isFalse, reason: role);
      expect(row.missing, isEmpty);
    }
  });

  test('setup strip asks for FSSAI before publish', () {
    final next = chefSetupNextAction(
      profile: {
        'fssai_number': '',
        'fssai_proof_url': '',
        'fssai_verification_status': 'unsubmitted',
      },
      isKitchenOpen: false,
      hasActiveDish: false,
    );
    expect(next?.$3, ChefSetupTarget.profile);
  });
}
