import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/group_room_notices.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

GroupRoomSettings _room({
  String placeKind = 'office',
  String placeLabel = 'DeskBay3',
  String dropoffNote = 'Reception',
  String timeSlot = '3:00 AM to 4:00 AM',
  DateTime? selectedDate,
}) {
  return GroupRoomSettings(
    placeKind: placeKind,
    placeLabel: placeLabel,
    dropoffNote: dropoffNote,
    timeSlot: timeSlot,
    selectedDate: selectedDate ?? DateTime.utc(2026, 10, 3),
  );
}

void main() {
  const members = ['kiranag', 'arushi', 'ravi', 'arushi', ''];

  test('a host time change notifies each other member and not the host', () {
    final notices = groupRoomChangeNotices(
      actorId: 'kiranag',
      hostId: 'kiranag',
      memberIds: members,
      before: _room(),
      after: _room(timeSlot: '4:00 AM to 5:00 AM'),
    );

    expect(notices.map((notice) => notice.userId).toList(), ['arushi', 'ravi']);
    expect(notices.every((notice) => notice.userId != 'kiranag'), isTrue);
    expect(notices.every((notice) => notice.change == 'time'), isTrue);
    expect(notices.every((notice) => notice.title == kSocietyOfficeHotpotLabel), isTrue);
    expect(notices.every((notice) => notice.body == 'Time changed for Office lunch at DeskBay3.'), isTrue);
  });

  test('a host place change names the society and a time-and-place change says both', () {
    final place = groupRoomChangeNotices(
      actorId: 'kiranag',
      hostId: 'kiranag',
      memberIds: const ['kiranag', 'arushi'],
      before: _room(placeKind: 'society', placeLabel: 'Sunshine Towers'),
      after: _room(placeKind: 'society', placeLabel: 'Sunshine Towers', dropoffNote: 'Gate 2'),
    );
    expect(place, hasLength(1));
    expect(place.single.userId, 'arushi');
    expect(place.single.change, 'place');
    expect(place.single.body, 'Place changed for Society lunch at Sunshine Towers.');

    final both = groupRoomChangeNotices(
      actorId: 'kiranag',
      hostId: 'kiranag',
      memberIds: const ['kiranag', 'arushi'],
      before: _room(),
      after: _room(timeSlot: '2:00 PM', placeLabel: 'Tower B'),
    );
    expect(both.single.change, 'both');
    expect(both.single.body, 'Time and place changed for Office lunch at Tower B.');
    expect(both.single.userId, 'arushi');
  });

  test('a date change counts as time and a venue change counts as place', () {
    final date = groupRoomChangeNotices(
      actorId: 'kiranag',
      hostId: 'kiranag',
      memberIds: const ['arushi'],
      before: _room(),
      after: _room(selectedDate: DateTime.utc(2026, 10, 4)),
    );
    expect(date.single.change, 'time');
    expect(date.single.body, contains('DeskBay3'));

    final venue = groupRoomChangeNotices(
      actorId: 'kiranag',
      hostId: 'kiranag',
      memberIds: const ['arushi'],
      before: _room(placeKind: 'office', placeLabel: ''),
      after: _room(placeKind: 'society', placeLabel: ''),
    );
    expect(venue.single.change, 'place');
    expect(venue.single.body, 'Place changed for Society lunch.');
  });

  test('a guest change and a plate edit do not notify the room', () {
    final guest = groupRoomChangeNotices(
      actorId: 'arushi',
      hostId: 'kiranag',
      memberIds: members,
      before: _room(),
      after: _room(timeSlot: '9:00 PM', placeLabel: 'Somewhere else'),
    );
    expect(guest, isEmpty);

    final plateEdit = groupRoomChangeNotices(
      actorId: 'kiranag',
      hostId: 'kiranag',
      memberIds: members,
      before: _room(),
      after: _room(),
    );
    expect(plateEdit, isEmpty);

    final guestPlate = groupRoomChangeNotices(
      actorId: 'arushi',
      hostId: 'kiranag',
      memberIds: members,
      before: _room(),
      after: _room(),
    );
    expect(guestPlate, isEmpty);
  });

  test('a group room alert opens from the diner alerts inbox', () {
    expect(
      alertOpenPath(
        alertDataFromNotificationRow({
          'kind': 'group_room',
          'title': kSocietyOfficeHotpotLabel,
          'body': 'Time changed for Office lunch at DeskBay3.',
          'data': {
            'kind': 'group_room',
            'room_code': 'GRP-IZDYWZ',
            'change': 'time',
          },
        }),
        role: 'customer',
      ),
      '/group/GRP-IZDYWZ',
    );
  });
}
