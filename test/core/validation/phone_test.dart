import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/validation/phone.dart';

void main() {
  group('Phone.normalizeUae', () {
    test('keeps an already-E.164 number', () {
      expect(Phone.normalizeUae('+971501234567'), '+971501234567');
    });

    test('prepends the dial code to a local 05x number (drops the zero)', () {
      expect(Phone.normalizeUae('0501234567'), '+971501234567');
    });

    test('prepends the dial code to a bare subscriber number', () {
      expect(Phone.normalizeUae('501234567'), '+971501234567');
    });

    test('adds + to a 971-prefixed number', () {
      expect(Phone.normalizeUae('971501234567'), '+971501234567');
    });

    test('collapses a 00 international prefix to +', () {
      expect(Phone.normalizeUae('00971501234567'), '+971501234567');
    });

    test('tolerates spaces and dashes', () {
      expect(Phone.normalizeUae('+971 50 123 4567'), '+971501234567');
      expect(Phone.normalizeUae('050-123-4567'), '+971501234567');
    });

    test('returns empty for empty input', () {
      expect(Phone.normalizeUae('   '), '');
    });
  });

  group('Phone.isValidUae', () {
    test('accepts valid UAE mobile prefixes', () {
      for (final n in ['0501234567', '0521234567', '0561234567', '+971581234567']) {
        expect(Phone.isValidUae(n), isTrue, reason: n);
      }
    });

    test('rejects an invalid mobile prefix (07x is not a UAE mobile)', () {
      expect(Phone.isValidUae('0571234567'), isFalse);
    });

    test('rejects too-short and too-long numbers', () {
      expect(Phone.isValidUae('05012345'), isFalse);
      expect(Phone.isValidUae('05012345678'), isFalse);
    });

    test('rejects a non-UAE country code', () {
      expect(Phone.isValidUae('+201001234567'), isFalse);
    });
  });

  group('Phone.localPart', () {
    test('strips +971 so a saved E.164 number prefills the local field', () {
      expect(Phone.localPart('+971501234567'), '501234567');
    });

    test('strips a 971 prefix and a local trunk zero', () {
      expect(Phone.localPart('971501234567'), '501234567');
      expect(Phone.localPart('0501234567'), '501234567');
    });

    test('returns empty for empty input', () {
      expect(Phone.localPart('  '), '');
    });

    test('round-trips: localPart then normalizeUae restores the E.164 value', () {
      const e164 = '+971501234567';
      expect(Phone.normalizeUae(Phone.localPart(e164)), e164);
    });
  });

  group('Phone.mask', () {
    test('masks the middle of a UAE number', () {
      expect(Phone.mask('+971501234567'), '+971 50 ••• 4567');
      expect(Phone.mask('0501234567'), '+971 50 ••• 4567');
    });

    test('falls back to the normalized form for an unexpected shape', () {
      expect(Phone.mask('+201001234567'), '+201001234567');
    });
  });

  group('Phone.maskBidi', () {
    test('wraps the masked number in a Unicode LTR isolate', () {
      final out = Phone.maskBidi('0501234567');
      // U+2066 LRI … U+2069 PDI around the plain mask.
      expect(out, '\u{2066}+971 50 ••• 4567\u{2069}');
      expect(out.startsWith('\u{2066}'), isTrue);
      expect(out.endsWith('\u{2069}'), isTrue);
    });
  });
}
