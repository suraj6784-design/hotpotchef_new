import 'group_cart_permissions.dart';
import 'helpers.dart';

/// Shared time, date, venue, place, and drop note for one Society/Office HotPOT.
class GroupRoomSettings {
  final String? placeKind;
  final String? placeLabel;
  final String? dropoffNote;
  final String? timeSlot;
  final DateTime? selectedDate;

  const GroupRoomSettings({
    this.placeKind,
    this.placeLabel,
    this.dropoffNote,
    this.timeSlot,
    this.selectedDate,
  });
}

/// Copy for an organizer change that other members should see in Alerts.
class GroupRoomChange {
  final String change;
  final String title;
  final String body;
  final String placeName;

  const GroupRoomChange({
    required this.change,
    required this.title,
    required this.body,
    required this.placeName,
  });
}

/// One diner alert. The host is never a recipient.
class GroupRoomNotice {
  final String userId;
  final String title;
  final String body;
  final String change;

  const GroupRoomNotice({
    required this.userId,
    required this.title,
    required this.body,
    required this.change,
  });
}

String _text(String? value) => (value ?? '').trim();

bool _sameSlot(String? a, String? b) => _text(a) == _text(b);

bool _sameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Office or society name members already know, with the place when it is set.
String groupRoomPlaceName({String? placeKind, String? placeLabel}) {
  final kind = groupPlaceKindLabel(placeKind);
  final label = _text(placeLabel);
  if (label.isEmpty) return kind;
  return '$kind at $label';
}

/// Null when the actor is not the host, or when time and place are unchanged.
/// A plate edit does not change these fields, so it does not produce a notice.
GroupRoomChange? describeGroupRoomChange({
  required String? actorId,
  required String? hostId,
  required GroupRoomSettings before,
  required GroupRoomSettings after,
}) {
  if (!isSharedCartHost(userId: actorId, hostId: hostId)) return null;

  final timeChanged = !_sameSlot(before.timeSlot, after.timeSlot) ||
      !_sameDay(before.selectedDate, after.selectedDate);
  final placeChanged = normalizeGroupPlaceKind(before.placeKind) != normalizeGroupPlaceKind(after.placeKind) ||
      _text(before.placeLabel) != _text(after.placeLabel) ||
      _text(before.dropoffNote) != _text(after.dropoffNote);
  if (!timeChanged && !placeChanged) return null;

  final change = timeChanged && placeChanged
      ? 'both'
      : timeChanged
          ? 'time'
          : 'place';
  final placeName = groupRoomPlaceName(placeKind: after.placeKind, placeLabel: after.placeLabel);
  final what = switch (change) {
    'both' => 'Time and place changed',
    'place' => 'Place changed',
    _ => 'Time changed',
  };
  return GroupRoomChange(
    change: change,
    title: kSocietyOfficeHotpotLabel,
    body: '$what for $placeName.',
    placeName: placeName,
  );
}

/// One alert for each other member. The host is omitted, and a guest actor yields none.
List<GroupRoomNotice> groupRoomChangeNotices({
  required String? actorId,
  required String? hostId,
  required Iterable<String?> memberIds,
  required GroupRoomSettings before,
  required GroupRoomSettings after,
}) {
  final change = describeGroupRoomChange(
    actorId: actorId,
    hostId: hostId,
    before: before,
    after: after,
  );
  if (change == null) return const [];

  final host = hostId?.trim() ?? '';
  final seen = <String>{};
  final notices = <GroupRoomNotice>[];
  for (final raw in memberIds) {
    final id = raw?.trim() ?? '';
    if (id.isEmpty || id == host || !seen.add(id)) continue;
    notices.add(GroupRoomNotice(
      userId: id,
      title: change.title,
      body: change.body,
      change: change.change,
    ));
  }
  return notices;
}
