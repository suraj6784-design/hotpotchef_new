/// P1-2: forgot-email lookup. The RPC always returns the same envelope;
/// a non-null hint is the only extra data the client may show.
const accountHintGenericMessage =
    'If an account matches, a masked email hint is shown. You can only try this a few times per hour.';

bool isValidAccountLookupQuery(String query) {
  final q = query.trim();
  if (q.length < 3 || q.length > 80) return false;
  return !RegExp(r'[,();%]').hasMatch(q);
}

String? parseAccountHint(dynamic rpc) {
  if (rpc is! Map) return null;
  final hint = rpc['hint'];
  if (hint is! String) return null;
  final trimmed = hint.trim();
  if (trimmed.isEmpty || !trimmed.contains('@')) return null;
  return trimmed;
}

String accountHintMessage(String? hint) {
  if (hint == null || hint.isEmpty) return accountHintGenericMessage;
  return 'If this matches an account, the registered email looks like $hint';
}
