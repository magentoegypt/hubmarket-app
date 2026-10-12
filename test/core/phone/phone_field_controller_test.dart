import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/phone/phone_country.dart';
import 'package:hubmarket_app/core/phone/phone_field_controller.dart';

PhoneFieldController _controller({String? number, String? country}) {
  final controller = PhoneFieldController(
    number: number,
    country: country == null ? null : phoneCountryByCode(country),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('a new field', () {
    test('starts on the UAE with nothing in it', () {
      final c = _controller();
      expect(c.country.code, 'AE');
      expect(c.text.text, '');
      expect(c.isEmpty, isTrue);
      expect(c.e164, '');
      expect(c.isValid(), isFalse);
    });

    test('takes the country it is given', () {
      expect(_controller(country: 'EG').country.code, 'EG');
    });
  });

  group('the number typed', () {
    test('is that of the country on the chip, with or without the trunk 0', () {
      final c = _controller()..text.text = '50 123 4567';
      expect(c.e164, '+971501234567');
      expect(c.isValid(), isTrue);
      c.text.text = '050 123 4567';
      expect(c.e164, '+971501234567');
      expect(c.isValid(mobileOnly: true), isTrue);
    });

    test('changes with the country picked: the same digits, another country', () {
      final c = _controller()..text.text = '1001234567';
      expect(c.isValid(), isFalse); // not a UAE number
      c.country = phoneCountryByCode('EG')!;
      expect(c.e164, '+201001234567');
      expect(c.isValid(), isTrue);
    });

    test('reads Arabic digits', () {
      final c = _controller()..text.text = '٠٥٠١٢٣٤٥٦٧';
      expect(c.e164, '+971501234567');
      expect(c.isValid(), isTrue);
      expect(c.isEmpty, isFalse);
    });

    test('is empty with no digit, however much else is typed', () {
      final c = _controller()..text.text = ' - ( ) ';
      expect(c.isEmpty, isTrue);
      expect(c.e164, '');
    });

    test('mobileOnly turns a landline down; any valid number is otherwise '
        'fine', () {
      final c = _controller(country: 'EG')..text.text = '02 21234567';
      expect(c.isValid(), isTrue);
      expect(c.isValid(mobileOnly: true), isFalse);
    });

    test('is invalid when too short, too long or of the wrong shape', () {
      for (final typed in ['5012345', '05012345678', '0571234567', '12']) {
        final c = _controller()..text.text = typed;
        expect(c.isValid(), isFalse, reason: typed);
      }
    });

    test('keeps its best-effort E.164 even when invalid, for the message that '
        'names it', () {
      final c = _controller()..text.text = '5012345';
      expect(c.e164, startsWith('+971'));
    });
  });

  group('a number written with its country code', () {
    test('sets the country and leaves the rest in the field', () {
      final c = _controller()..text.text = '+971501234567';
      expect(c.country.code, 'AE');
      expect(c.text.text, '501234567');
      expect(c.e164, '+971501234567');
    });

    test('works from another country, and the 00 exit code, and grouping', () {
      final c = _controller()..text.text = '+20 100 123 4567';
      expect(c.country.code, 'EG');
      expect(c.text.text, '1001234567');
      expect(c.isValid(), isTrue);

      final d = _controller(country: 'EG')..text.text = '00971 50 123 4567';
      expect(d.country.code, 'AE');
      expect(d.text.text, '501234567');
    });

    test('picks, among the regions that share +1, the one the number is of', () {
      final us = _controller()..text.text = '+14155552671';
      expect(us.country.code, 'US');
      final jamaica = _controller()..text.text = '+18765550123';
      expect(jamaica.country.code, 'JM');
      expect(jamaica.text.text, '8765550123');
    });

    test('waits for the code to be whole: nothing changes at +9 or +97', () {
      final c = _controller()..text.text = '+9';
      expect(c.country.code, 'AE');
      expect(c.text.text, '+9');
      c.text.text = '+97';
      expect(c.text.text, '+97');
      c.text.text = '+971';
      expect(c.country.code, 'AE');
      expect(c.text.text, '');
    });

    test('is also taken typed in Arabic digits', () {
      final c = _controller(country: 'EG')..text.text = '+٩٧١٥٠١٢٣٤٥٦٧';
      expect(c.country.code, 'AE');
      expect(c.text.text, '501234567');
    });

    test('tells its listeners that the country changed', () {
      final c = _controller();
      var told = 0;
      c.addListener(() => told++);
      c.text.text = '+201001234567';
      expect(told, 1);
      c.country = phoneCountryByCode('SA')!;
      expect(told, 2);
      c.country = phoneCountryByCode('SA')!; // already there
      expect(told, 2);
    });
  });

  group('a stored number', () {
    test('fills the field with its country and its own grouping', () {
      final c = _controller(number: '+971501234567');
      expect(c.country.code, 'AE');
      expect(c.text.text, '50 123 4567');
      expect(c.e164, '+971501234567');
    });

    test('is of any country', () {
      final c = _controller(number: '+201001234567');
      expect(c.country.code, 'EG');
      expect(c.e164, '+201001234567');
      expect(c.isValid(mobileOnly: true), isTrue);
    });

    test('may be an older spelling of a UAE number, which is the UAE\'s', () {
      for (final stored in ['0501234567', '971501234567', '00971501234567']) {
        final c = _controller(number: stored);
        expect(c.country.code, 'AE', reason: stored);
        expect(c.e164, '+971501234567', reason: stored);
      }
    });

    test('that is no valid number is shown as it is, to be corrected', () {
      final c = _controller(number: '+97150123');
      expect(c.isEmpty, isFalse);
      expect(c.isValid(), isFalse);
    });

    test('is set again later: the country and the text follow', () {
      final c = _controller(number: '+971501234567')..setNumber('+966501234567');
      expect(c.country.code, 'SA');
      expect(c.e164, '+966501234567');
    });

    test('clear empties the number and keeps the country', () {
      final c = _controller(number: '+201001234567')..clear();
      expect(c.text.text, '');
      expect(c.country.code, 'EG');
      expect(c.e164, '');
    });
  });
}
