import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/phone/country_names.dart';
import 'package:hubmarket_app/core/phone/phone_country.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

void main() {
  group('the list of countries', () {
    test('has every region of the phone metadata, each named in both '
        'languages', () {
      expect(kPhoneCountries, hasLength(IsoCode.values.length));
      expect(kCountryNamesEn.keys.toSet(), kCountryNamesAr.keys.toSet());
      for (final country in kPhoneCountries) {
        expect(country.nameEn.trim(), isNotEmpty, reason: country.code);
        expect(country.nameAr.trim(), isNotEmpty, reason: country.code);
        expect(country.dialCode, matches(RegExp(r'^\d{1,3}$')));
        expect(country.dial, '+${country.dialCode}');
      }
    });

    test('names the regions another package\'s Arabic table swapped '
        '(CLDR\'s, from Node\'s ICU)', () {
      String ar(String code) => phoneCountryByCode(code)!.nameAr;
      expect(ar('AT'), 'النمسا'); // Austria
      expect(ar('AU'), 'أستراليا'); // Australia
      expect(ar('KH'), 'كمبوديا'); // Cambodia
      expect(ar('CM'), 'الكاميرون'); // Cameroon
      expect(ar('CA'), 'كندا'); // Canada
      expect(ar('AE'), 'الإمارات العربية المتحدة');
      expect(ar('EG'), 'مصر');
      expect(ar('SA'), 'المملكة العربية السعودية');
      expect(phoneCountryByCode('AT')!.nameEn, 'Austria');
      expect(phoneCountryByCode('KH')!.nameEn, 'Cambodia');
    });

    test('has the calling code of each region', () {
      String dial(String code) => phoneCountryByCode(code)!.dial;
      expect(dial('AE'), '+971');
      expect(dial('EG'), '+20');
      expect(dial('SA'), '+966');
      expect(dial('US'), '+1');
      expect(dial('CA'), '+1');
      expect(dial('GB'), '+44');
      expect(dial('IN'), '+91');
      expect(dial('RU'), '+7');
      expect(dial('KZ'), '+7');
    });

    test('draws a flag from the region code', () {
      expect(phoneCountryByCode('AE')!.flag.runes.toList(), [0x1F1E6, 0x1F1EA]);
      expect(phoneCountryByCode('EG')!.flag.runes.toList(), [0x1F1EA, 0x1F1EC]);
      expect(phoneCountryByCode('US')!.flag.runes.length, 2);
    });

    test('is read by region code, in any case', () {
      expect(phoneCountryByCode('ae'), same(phoneCountryByCode('AE')));
      expect(phoneCountryByCode(' Eg '), phoneCountryByCode('EG'));
      expect(phoneCountryByCode('ZZ'), isNull);
      expect(phoneCountryByCode(''), isNull);
    });

    test('names a country in the language asked for', () {
      final uae = phoneCountryByCode('AE')!;
      expect(uae.name('en'), 'United Arab Emirates');
      expect(uae.name('ar'), 'الإمارات العربية المتحدة');
      expect(uae.name('fr'), 'United Arab Emirates');
    });
  });

  group('the defaults', () {
    test('start on the UAE, the store\'s country, and suggest it first, then '
        'the two the website\'s field puts first', () {
      expect(kDefaultPhoneCountry.code, 'AE');
      expect(kPreferredPhoneCountries.map((c) => c.code), ['AE', 'EG', 'US']);
    });
  });

  group('example numbers (the hints)', () {
    test('are a number of the region as it is typed after its code', () {
      expect(phoneCountryByCode('AE')!.exampleNumber, '50 123 4567');
      expect(phoneCountryByCode('EG')!.exampleNumber, isNotEmpty);
    });

    test('are valid numbers of their own region', () {
      var checked = 0;
      for (final country in kPhoneCountries) {
        final example = country.exampleNumber;
        if (example.isEmpty) continue;
        checked++;
        final phone = PhoneNumber.parse(example, destinationCountry: country.iso);
        expect(phone.isValid(), isTrue, reason: '${country.code} $example');
      }
      expect(checked, greaterThan(200));
    });
  });

  group('calling codes', () {
    test('name their main region; a shared code names its first', () {
      expect(phoneCountryForDialCode('971')!.code, 'AE');
      expect(phoneCountryForDialCode('20')!.code, 'EG');
      expect(phoneCountryForDialCode('1')!.code, 'US');
      expect(phoneCountryForDialCode('7')!.code, 'RU');
      expect(phoneCountryForDialCode('44')!.code, 'GB');
      expect(phoneCountryForDialCode('999'), isNull);
      expect(phoneCountryForDialCode(''), isNull);
    });

    test('are found at the start of digits, shortest first (no code starts '
        'another)', () {
      expect(matchDialCodePrefix('971501234567')!.country.code, 'AE');
      expect(matchDialCodePrefix('971501234567')!.rest, '501234567');
      expect(matchDialCodePrefix('201001234567')!.country.code, 'EG');
      expect(matchDialCodePrefix('201001234567')!.rest, '1001234567');
      expect(matchDialCodePrefix('14155552671')!.country.code, 'US');
      expect(matchDialCodePrefix('14155552671')!.rest, '4155552671');
      expect(matchDialCodePrefix('212600000000')!.country.code, 'MA');
      // The code alone leaves nothing after it.
      expect(matchDialCodePrefix('971')!.rest, '');
    });

    test('are not found in what is not yet a code', () {
      expect(matchDialCodePrefix(''), isNull);
      expect(matchDialCodePrefix('9'), isNull);
      expect(matchDialCodePrefix('97'), isNull);
      expect(matchDialCodePrefix('0'), isNull);
    });
  });
}
