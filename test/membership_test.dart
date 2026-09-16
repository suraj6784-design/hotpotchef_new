import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/membership.dart';

void main() {
  test('flash offer price wins when the flash flag is on', () {
    expect(
      membershipOfferPrice({
        'flash_enabled': true,
        'offer_price_inr': 1,
        'list_price_inr': 149,
      }),
      1,
    );
    expect(
      membershipOfferPrice({
        'flash_enabled': false,
        'offer_price_inr': 1,
        'list_price_inr': 149,
      }),
      149,
    );
  });

  test('active members are not sold another plan on checkout', () {
    expect(
      membershipOfferEligible({'active_member': true, 'plan_id': 'abc', 'eligible': true}),
      isFalse,
    );
    expect(
      membershipOfferEligible({'reason': 'already_member', 'eligible': false}),
      isFalse,
    );
    expect(
      membershipOfferEligible({'eligible': true, 'plan_id': 'abc'}),
      isTrue,
    );
  });

  test('profile title defaults to Family member', () {
    expect(membershipMemberTitle(null), kFamilyMemberTitle);
    expect(membershipMemberTitle({'member_title': 'Family member'}), 'Family member');
  });

  test('membership days left follow the 1, 3, 6, 9 month plans', () {
    expect(membershipPlanMonthsFromDays(30), 1);
    expect(membershipPlanMonthsFromDays(90), 3);
    expect(membershipPlanMonthsFromDays(180), 6);
    expect(membershipPlanMonthsFromDays(270), 9);
    final now = DateTime(2026, 9, 17);
    expect(
      membershipDaysLeft(DateTime(2026, 9, 20), now: now),
      3,
    );
    expect(
      membershipDaysLeftLabel(
        endsAt: DateTime(2026, 12, 16),
        durationDays: 90,
        now: now,
      ),
      'Membership days left: 90 · 3 months plan',
    );
  });
}
