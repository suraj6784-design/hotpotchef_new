import 'dart:math';

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

  test('share copy tells friends both sides earn on the first order', () {
    expect(referralInviteText('CHEFAB12'), contains('CHEFAB12'));
    expect(referralInviteText('CHEFAB12'), contains('50 HotPot Coins'));
    expect(referralInviteText('CHEFAB12'), contains('auth?ref=CHEFAB12'));
  });

  test('generated referral codes match the signup field', () {
    final code = generateReferralCode(Random(1));
    expect(isPlausibleReferralCode(code), isTrue);
    expect(code.startsWith('CHEF'), isTrue);
  });

  test('a person cannot refer themselves', () {
    expect(sanitizeReferredBy(referredBy: 'CHEFAB12', ownCode: 'chefab12'), isNull);
    expect(sanitizeReferredBy(referredBy: 'CHEFAB12', ownCode: 'CHEFZZ99'), 'CHEFAB12');
  });

  test('referral coins come from rewarded friends, not the whole wallet', () {
    expect(referralCoinsFromRewardedFriends(0), 0);
    expect(referralCoinsFromRewardedFriends(2), 100);
  });

  test('chef and driver signups do not store referral fields', () {
    expect(roleUsesReferral('Chef'), isFalse);
    expect(roleUsesReferral('Driver'), isFalse);
    expect(roleUsesReferral('Customer'), isTrue);
    final chef = signupUserPayload(
      id: 'u2',
      email: 'chef@b.com',
      name: 'Asha',
      phone: '9876543210',
      role: 'Chef',
      referredBy: 'CHEFAB12',
      referralCode: 'CHEFNEW12',
    );
    expect(chef.containsKey('referred_by'), isFalse);
    expect(chef.containsKey('referral_code'), isFalse);
  });

  test('signup payload also stores the new user referral code', () {
    expect(
      signupUserPayload(
        id: 'u1',
        email: 'a@b.com',
        name: 'Ann',
        phone: '9876543210',
        role: 'Customer',
        referredBy: 'CHEFAB12',
        referralCode: 'CHEFNEW12',
      ),
      allOf(
        containsPair('referred_by', 'CHEFAB12'),
        containsPair('referral_code', 'CHEFNEW12'),
      ),
    );
  });
}
