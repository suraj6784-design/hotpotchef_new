import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';

Future<Map<String, String>> lookupChefDisplayNames(Iterable<String> chefIds) async {
  final ids = chefIds.where((id) => id.trim().isNotEmpty).toSet().toList();
  if (ids.isEmpty) return {};

  final rows = await Supabase.instance.client
      .from('users')
      .select('id, name, full_name, email')
      .inFilter('id', ids);

  final names = <String, String>{};
  for (final row in List<Map<String, dynamic>>.from(rows as List)) {
    names[row['id'].toString()] = chefDisplayName(row);
  }
  return names;
}

Future<String> lookupChefDisplayName(
  String? chefId, {
  Map<String, dynamic>? hint,
}) async {
  final hinted = chefDisplayName(hint, fallback: '');
  if (chefId == null || chefId.trim().isEmpty) {
    return hinted.isNotEmpty ? hinted : 'Home Kitchen';
  }
  try {
    final names = await lookupChefDisplayNames([chefId]);
    final live = names[chefId] ?? '';
    if (live.isNotEmpty) return live;
  } catch (_) {}
  if (hinted.isNotEmpty) return hinted;
  return 'Home Kitchen';
}
