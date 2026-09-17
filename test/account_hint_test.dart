import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/account_hint.dart';

void main() {
  group('isValidAccountLookupQuery', () {
    test('accepts a phone or a name', () {
      expect(isValidAccountLookupQuery('9876543210'), isTrue);
      expect(isValidAccountLookupQuery('John Doe'), isTrue);
    });

    test('rejects empty, short, long, and filter-injection chars', () {
      expect(isValidAccountLookupQuery('ab'), isFalse);
      expect(isValidAccountLookupQuery('a' * 81), isFalse);
      expect(isValidAccountLookupQuery('Jane,Doe'), isFalse);
      expect(isValidAccountLookupQuery('Jane; drop'), isFalse);
      expect(isValidAccountLookupQuery('name%'), isFalse);
    });
  });

  group('parseAccountHint', () {
    test('returns a masked hint from the RPC envelope', () {
      expect(
        parseAccountHint({'success': true, 'hint': 'j***@hotpotchef.com'}),
        'j***@hotpotchef.com',
      );
    });

    test('treats miss, rate-limit, and malformed payloads the same', () {
      expect(parseAccountHint({'success': true, 'hint': null}), isNull);
      expect(parseAccountHint({'success': true}), isNull);
      expect(parseAccountHint(null), isNull);
      expect(parseAccountHint('j***@x.com'), isNull);
      expect(parseAccountHint({'hint': 12}), isNull);
      expect(parseAccountHint({'hint': 'not-an-email'}), isNull);
    });
  });

  group('accountHintMessage', () {
    test('never says found or not found', () {
      final withHint = accountHintMessage('j***@hotpotchef.com');
      final withoutHint = accountHintMessage(null);

      expect(withHint.toLowerCase(), isNot(contains('account found')));
      expect(withHint.toLowerCase(), isNot(contains('no account')));
      expect(withoutHint, accountHintGenericMessage);
      expect(withoutHint.toLowerCase(), isNot(contains('no account')));
      expect(withoutHint.toLowerCase(), isNot(contains('rate limit')));
    });
  });
}
