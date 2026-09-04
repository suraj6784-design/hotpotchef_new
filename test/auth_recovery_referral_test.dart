import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  test('password reset link matches the app scheme the OS already opens', () {
    expect(passwordResetRedirectUri, 'hotpotchef://app/reset-password');
    expect(isPasswordRecoveryPath('/reset-password'), isTrue);
    expect(isPasswordRecoveryPath('/reset-callback'), isTrue);
    expect(isPasswordRecoveryPath('/auth'), isFalse);
  });

  test('reset password form requires 8 characters and a matching confirm', () {
    expect(
      resetPasswordValidationError(password: 'short', confirm: 'short'),
      'Password must be at least 8 characters long.',
    );
    expect(
      resetPasswordValidationError(password: 'longenough', confirm: 'different1'),
      'Passwords do not match.',
    );
    expect(
      resetPasswordValidationError(password: 'longenough', confirm: 'longenough'),
      isNull,
    );
  });

  test('referral codes are trimmed and uppercased', () {
    expect(normalizeReferralCode('  chefab12  '), 'CHEFAB12');
    expect(normalizeReferralCode('   '), isNull);
    expect(isPlausibleReferralCode('CHEFABC1'), isTrue);
    expect(isPlausibleReferralCode('NO'), isFalse);
    expect(isPlausibleReferralCode('CHEF ABC1'), isFalse);
  });

  test('signup payload writes referred_by only when a code is present', () {
    expect(
      signupUserPayload(
        id: 'u1',
        email: 'a@b.com',
        name: 'Ann',
        phone: '9876543210',
        role: 'Customer',
        referredBy: 'CHEFAB12',
      ),
      containsPair('referred_by', 'CHEFAB12'),
    );
    expect(
      signupUserPayload(
        id: 'u1',
        email: 'a@b.com',
        name: 'Ann',
        phone: '9876543210',
        role: 'Customer',
      ).containsKey('referred_by'),
      isFalse,
    );
  });

  test('share copy tells friends to enter the code at signup', () {
    expect(referralInviteText('CHEFAB12'), contains('CHEFAB12'));
    expect(referralInviteText('CHEFAB12'), contains('when you sign up'));
  });
}
