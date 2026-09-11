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
    expect(incomplete.missing, contains('FSSAI verified'));
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
      'lat': 18.5,
      'lng': 73.8,
      'bank_account_number': '****1234',
      'bank_ifsc': 'HDFC0001234',
    });
    expect(live.incomplete, isFalse);
    expect(live.payoutMissing, isEmpty);
  });

  test('driver KYC still requires vehicle, PAN and Aadhaar', () {
    final row = kycChecklistFor({
      'role': 'driver',
      'name': 'Ravi',
      'phone': '9999999999',
    });
    expect(row.missing, containsAll(['PAN', 'Aadhaar', 'Vehicle type', 'Vehicle number']));
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
