import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/phone/phone_country.dart';
import 'package:hubmarket_app/core/validation/phone.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

void main() {
  group('Phone.normalize', () {
    test('keeps an already-E.164 number', () {
      expect(Phone.normalize('+971501234567'), '+971501234567');
    });

    test('prepends the dial code to a local 05x number (drops the zero)', () {
      expect(Phone.normalize('0501234567'), '+971501234567');
    });

    test('prepends the dial code to a bare subscriber number', () {
      expect(Phone.normalize('501234567'), '+971501234567');
    });

    test('adds + to a 971-prefixed number', () {
      expect(Phone.normalize('971501234567'), '+971501234567');
    });

    test('collapses a 00 international prefix to +', () {
      expect(Phone.normalize('00971501234567'), '+971501234567');
    });

    test('tolerates spaces and dashes', () {
      expect(Phone.normalize('+971 50 123 4567'), '+971501234567');
      expect(Phone.normalize('050-123-4567'), '+971501234567');
    });

    test('reads Arabic digits', () {
      expect(Phone.normalize('٠٥٠١٢٣٤٥٦٧'), '+971501234567');
    });

    test('returns empty for empty input and for no digit at all', () {
      expect(Phone.normalize('   '), '');
      expect(Phone.normalize('+'), '');
      expect(Phone.normalize('abc'), '');
    });

    test('is the number of any country written with its code', () {
      expect(Phone.normalize('+201001234567'), '+201001234567');
      expect(Phone.normalize('00201001234567'), '+201001234567');
      expect(Phone.normalize('+44 20 7183 8750'), '+442071838750');
      expect(Phone.normalize('+1 (415) 555-2671'), '+14155552671');
    });

    test('is a number of the country it is told about, trunk zero and all', () {
      final egypt = phoneCountryByCode('EG')!;
      expect(Phone.normalize('01001234567', country: egypt), '+201001234567');
      expect(Phone.normalize('1001234567', country: egypt), '+201001234567');
      final saudi = phoneCountryByCode('SA')!;
      expect(Phone.normalize('0501234567', country: saudi), '+966501234567');
    });
  });

  group('Phone.isValid', () {
    test('accepts valid UAE mobile prefixes', () {
      for (final n in [
        '0501234567',
        '0521234567',
        '0561234567',
        '+971581234567',
      ]) {
        expect(Phone.isValid(n), isTrue, reason: n);
      }
    });

    test('rejects an invalid mobile prefix (057 is not a UAE mobile)', () {
      expect(Phone.isValid('0571234567'), isFalse);
    });

    test('rejects too-short and too-long numbers', () {
      expect(Phone.isValid('05012345'), isFalse);
      expect(Phone.isValid('05012345678'), isFalse);
    });

    test('accepts another country\'s number written with its code', () {
      expect(Phone.isValid('+201001234567'), isTrue);
      expect(Phone.isValid('+442071838750'), isTrue);
      expect(Phone.isValid('+14155552671'), isTrue);
    });

    test('is checked against the rules of the country it is told about', () {
      final egypt = phoneCountryByCode('EG')!;
      final india = phoneCountryByCode('IN')!;
      final kuwait = phoneCountryByCode('KW')!;
      expect(Phone.isValid('01001234567', country: egypt), isTrue);
      expect(Phone.isValid('9876543210', country: india), isTrue);
      expect(Phone.isValid('51234567', country: kuwait), isTrue);
      // The same digits are no number of another country.
      expect(Phone.isValid('51234567'), isFalse);
      expect(Phone.isValid('0100123456', country: egypt), isFalse);
    });

    test('mobileOnly turns a landline down: a code does not reach it', () {
      final egypt = phoneCountryByCode('EG')!;
      // Cairo landline: a number, not a mobile.
      expect(Phone.isValid('0221234567', country: egypt), isTrue);
      expect(
        Phone.isValid('0221234567', country: egypt, mobileOnly: true),
        isFalse,
      );
      expect(
        Phone.isValid('01001234567', country: egypt, mobileOnly: true),
        isTrue,
      );
      expect(Phone.isValid('+442071838750', mobileOnly: true), isFalse);
    });

    test('empty and garbage are not numbers', () {
      expect(Phone.isValid(''), isFalse);
      expect(Phone.isValid('+'), isFalse);
      expect(Phone.isValid('call me'), isFalse);
    });
  });

  group('Phone.display', () {
    test('groups a UAE number as the frames print it', () {
      expect(Phone.display('+971501234567'), '+971 50 123 4567');
      expect(Phone.display('0501234567'), '+971 50 123 4567');
    });

    test('groups another country\'s number with its own pattern', () {
      expect(Phone.display('+201001234567'), '+20 10 01234567');
      expect(Phone.display('+14155552671'), '+1 415-555-2671');
    });

    test('shows what is stored when it is not a valid number', () {
      expect(Phone.display('12345'), '12345');
      expect(Phone.display(''), '');
    });
  });

  group('Phone.mask', () {
    test('masks the middle of a UAE number', () {
      expect(Phone.mask('+971501234567'), '+971 50 ••• 4567');
      expect(Phone.mask('0501234567'), '+971 50 ••• 4567');
    });

    test('masks the number of another country the same way', () {
      expect(Phone.mask('+201001234567'), '+20 10 ••• 4567');
      expect(Phone.mask('+14155552671'), '+1 41 ••• 2671');
    });

    test('shows less of a short number', () {
      // Kuwait: 8 digits.
      expect(Phone.mask('+96551234567'), '+965 51 ••• 567');
    });

    test('falls back to the normalized form when it is not a valid number', () {
      expect(Phone.mask('+2010012345'), '+2010012345');
      expect(Phone.mask(''), '');
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

  group('Phone.latinDigits', () {
    test('writes Arabic-Indic and Persian digits as 0-9, nothing else', () {
      expect(Phone.latinDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(Phone.latinDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(Phone.latinDigits('+٩٧١ 50-١٢٣'), '+971 50-123');
    });
  });

  group('Phone.parse', () {
    test('a number with no code is of the store\'s country by default', () {
      expect(Phone.parse('0501234567')!.isoCode, IsoCode.AE);
      expect(Phone.parse('+201001234567')!.isoCode, IsoCode.EG);
      expect(Phone.parse('hello'), isNull);
    });
  });
}
