import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  const chefId = 'chef-a';
  const chefPin = {'lat': 18.52, 'lng': 73.85};

  group('catering leads header count', () {
    test('counts every card the kitchen list shows', () {
      final requests = [
        {
          'id': 'paid',
          'title': 'Biryani paid',
          'status': 'Paid',
          'accepted_chef_id': chefId,
          'request_type': 'broadcast',
          'latitude': 18.53,
          'longitude': 73.86,
          'target_date_time': '2026-09-06T05:30:00.000Z',
        },
        {
          'id': 'quote',
          'title': 'puran poli quote',
          'status': 'Open',
          'request_type': 'broadcast',
          'latitude': 18.52,
          'longitude': 73.85,
          'target_date_time': '06 Sep 2026, 11:00 AM',
        },
        {
          'id': 'selected',
          'title': 'Biryani selected',
          'status': 'Accepted',
          'accepted_chef_id': chefId,
          'request_type': 'broadcast',
          'target_date_time': '2026-09-06T05:30:00.000Z',
        },
        {
          'id': 'other-kitchen',
          'title': 'Someone else',
          'status': 'Accepted',
          'accepted_chef_id': 'chef-b',
          'request_type': 'broadcast',
        },
        {
          'id': 'far-open',
          'title': 'Far open',
          'status': 'Open',
          'latitude': 19.07,
          'longitude': 72.87,
          'request_type': 'broadcast',
        },
        {
          'id': 'packaging',
          'title': 'Boxes',
          'status': 'Open',
          'request_type': 'packaging',
        },
        {
          'id': 'cancelled',
          'title': 'Cancelled biryani',
          'status': 'Cancelled',
          'accepted_chef_id': chefId,
          'request_type': 'broadcast',
        },
      ];

      final shown = cateringLeadsShownToChef(
        requests,
        chefId: chefId,
        chefPin: chefPin,
      );

      expect(shown.map((row) => row['title']), [
        'puran poli quote',
        'Biryani paid',
        'Biryani selected',
      ]);
      expect(cateringLeadsHeaderTitle(shown.length), 'Catering leads (3)');
      expect(
        shown.where((row) => cateringLeadStatus(row) == 'open').length,
        1,
      );
    });

    test('hides the number when no cards are shown', () {
      expect(cateringLeadsHeaderTitle(0), 'Catering leads');
      expect(
        cateringLeadsShownToChef(const [], chefId: chefId, chefPin: chefPin),
        isEmpty,
      );
    });

    test('keeps a targeted invite even when it is outside 25 km', () {
      final shown = cateringLeadsShownToChef(
        [
          {
            'title': 'Invited thali',
            'status': 'Open',
            'latitude': 19.07,
            'longitude': 72.87,
            'target_chef_ids': [chefId],
          },
        ],
        chefId: chefId,
        chefPin: chefPin,
      );
      expect(shown, hasLength(1));
      expect(cateringLeadsHeaderTitle(shown.length), 'Catering leads (1)');
    });
  });

  group('formatCateringNeededBy', () {
    test('turns UTC ISO into the diner pattern in IST', () {
      expect(
        formatCateringNeededBy('2026-09-06T05:30:00.000Z'),
        '06 Sep 2026, 11:00 AM',
      );
      expect(
        formatCateringNeededBy('2026-09-06T05:30:00+00:00'),
        '06 Sep 2026, 11:00 AM',
      );
      expect(
        formatCateringNeededBy(DateTime.utc(2026, 9, 6, 5, 30)),
        '06 Sep 2026, 11:00 AM',
      );
      expect(
        formatCateringNeededBy('2026-09-06T11:00:00+05:30'),
        '06 Sep 2026, 11:00 AM',
      );
    });

    test('keeps an already friendly label on the same pattern', () {
      expect(
        formatCateringNeededBy('06 Sep 2026, 11:00 AM'),
        '06 Sep 2026, 11:00 AM',
      );
      expect(
        formatCateringNeededBy('Sun, 6th Sep 2026 at 11:00 AM'),
        '06 Sep 2026, 11:00 AM',
      );
    });

    test('never returns a raw ISO string', () {
      for (final raw in [
        '2026-09-06T05:30:00.000Z',
        '2026-09-06 05:30:00.000Z',
        '2026-09-06',
        null,
        '',
        'ASAP',
        '06 Sep 2026, 11:00 AM',
      ]) {
        final label = formatCateringNeededBy(raw);
        expect(label, isNot(contains('T')));
        expect(label, isNot(contains('Z')));
        expect(label, isNot(contains('000')));
      }
      expect(formatCateringNeededBy(null), 'ASAP');
      expect(formatCateringNeededBy(''), 'ASAP');
      expect(formatCateringNeededBy('ASAP'), 'ASAP');
      expect(formatCateringNeededBy('2026-09-06'), '06 Sep 2026');
    });
  });
}
