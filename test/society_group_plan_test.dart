import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('society group plan helpers', () {
    test('normalizes place kinds and builds WhatsApp invite copy', () {
      expect(normalizeGroupPlaceKind('Society'), 'society');
      expect(normalizeGroupPlaceKind('desk'), 'friends');
      expect(groupPlaceKindLabel('office'), 'Office lunch');
      expect(groupPlaceKindHint('society'), contains('Building'));

      expect(
        societyGroupInviteText(
          roomCode: 'grp-ab12cd',
          placeKind: 'society',
          placeLabel: 'Sunshine Towers',
          dropoffNote: 'Gate 2',
          timeSlot: 'Tomorrow 1:00 PM',
        ),
        'Society lunch at Sunshine Towers\n'
        'Join my HotPotChef group cart: GRP-AB12CD\n'
        'https://hotpotchef.com/group/GRP-AB12CD\n'
        'Slot: Tomorrow 1:00 PM\n'
        'Drop: Gate 2\n'
        'Add your plates — I pay once at checkout.',
      );
      expect(groupCartShareUri('grp-ab12cd'), 'https://hotpotchef.com/group/GRP-AB12CD');
      expect(
        parseGroupRoomCode('https://hotpotchef.com/group/GRP-AB12CD'),
        'GRP-AB12CD',
      );
      expect(
        parseGroupRoomCode('Join my HotPotChef group cart: grp-ab12cd'),
        'GRP-AB12CD',
      );
      expect(dinerGroupReturnPath('/group/GRP-AB12CD'), '/group/GRP-AB12CD');
      expect(dinerGroupReturnPath('https://hotpotchef.com/group/GRP-AB12CD'), isNull);

      expect(
        societyGroupInviteText(roomCode: 'GRP-1', placeKind: 'friends'),
        'Group order\n'
        'Join my HotPotChef group cart: GRP-1\n'
        'Add your plates — I pay once at checkout.',
      );
    });
  });
}
