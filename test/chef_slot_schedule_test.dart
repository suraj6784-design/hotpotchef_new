import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('chefSlotDefaultSchedule', () {
    test('uses the chef window only — never invents now+40 ASAP times', () {
      final before = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 12),
      );
      expect(before, {'date': 'Today', 'time': '7:30 PM'});

      final inside = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 19, 45),
      );
      expect(inside, {'date': 'Today', 'time': '7:30 PM'});

      final after = chefSlotDefaultSchedule(
        '7:30 PM to 8:30 PM',
        now: DateTime(2026, 9, 6, 21),
      );
      expect(after, {'date': 'Tomorrow', 'time': '7:30 PM'});

      expect(preferredChefSlotClock('1:00 PM to 2:00 PM'), '1:00 PM');
      expect(preferredChefSlotClock('ASAP'), isNull);
    });
  });
}
