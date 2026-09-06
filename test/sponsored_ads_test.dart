import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/widgets/sponsored_placement_banner.dart';

void main() {
  test('overall ads always eligible; targeted filters by city when known', () {
    final now = DateTime.utc(2026, 9, 6, 12);
    final rows = [
      {
        'id': '1',
        'status': 'live',
        'reach_mode': 'overall',
        'title': 'Overall brand',
        'starts_at': '2026-09-01T00:00:00Z',
      },
      {
        'id': '2',
        'status': 'live',
        'reach_mode': 'targeted',
        'city': 'Pune',
        'title': 'Pune only',
        'starts_at': '2026-09-01T00:00:00Z',
      },
      {
        'id': '3',
        'status': 'draft',
        'reach_mode': 'overall',
        'title': 'Hidden draft',
      },
      {
        'id': '4',
        'status': 'live',
        'reach_mode': 'targeted',
        'city': 'Mumbai',
        'title': 'Mumbai only',
        'starts_at': '2026-09-01T00:00:00Z',
      },
    ];

    final pune = liveSponsoredCampaigns(rows, cityHint: 'Pune', now: now);
    expect(pune.map((e) => e['id']), ['1', '2']);

    final unknownCity = liveSponsoredCampaigns(rows, now: now);
    expect(unknownCity.map((e) => e['id']), containsAll(['1', '2', '4']));
  });
}
