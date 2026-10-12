import 'package:phone_numbers_parser/metadata.dart'
    show countryCodeToIsoCode, metadataExamplesByIsoCode;
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import 'country_names.dart';

/// A region the phone field can pick: its flag, its name in the shopper's
/// language and its dial code. The website's phone fields (intl-tel-input, with
/// the dropdown on and every country allowed) offer them all, and so does the
/// app.
class PhoneCountry {
  const PhoneCountry._({
    required this.iso,
    required this.dialCode,
    required this.nameEn,
    required this.nameAr,
  });

  /// The region, as the phone-number metadata knows it.
  final IsoCode iso;

  /// The country calling code, digits only: `971`.
  final String dialCode;

  final String nameEn;
  final String nameAr;

  /// ISO 3166 region code: `AE`.
  String get code => iso.name;

  /// The calling code as it is written: `+971`.
  String get dial => '+$dialCode';

  /// The regional-indicator pair that every phone and browser draws as the
  /// flag (`AE` is the two symbols for A and E).
  String get flag => String.fromCharCodes([
    for (final unit in code.codeUnits) 0x1F1E6 + unit - 0x41,
  ]);

  /// The name in [languageCode] (`ar`, otherwise English).
  String name(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;

  /// A number of this region that a shopper might type, as it is written after
  /// the calling code (`50 123 4567`): the hint of the field. Empty when the
  /// metadata has none.
  String get exampleNumber {
    final examples = metadataExamplesByIsoCode[iso];
    final nsn = (examples?.mobile.isNotEmpty ?? false)
        ? examples!.mobile
        : (examples?.fixedLine ?? '');
    if (nsn.isEmpty) return '';
    return PhoneNumber(
      isoCode: iso,
      nsn: nsn,
    ).formatNsn(format: NsnFormat.international);
  }

  @override
  bool operator ==(Object other) => other is PhoneCountry && other.iso == iso;

  @override
  int get hashCode => iso.hashCode;

  @override
  String toString() => 'PhoneCountry($code $dial)';
}

/// Every region with a name in both languages, in the metadata's order (by
/// region code). The picker sorts them by the name in the shopper's language.
final List<PhoneCountry> kPhoneCountries = List<PhoneCountry>.unmodifiable([
  for (final iso in IsoCode.values)
    if (kCountryNamesEn[iso.name] != null && kCountryNamesAr[iso.name] != null)
      PhoneCountry._(
        iso: iso,
        dialCode: PhoneNumber(isoCode: iso, nsn: '').countryCode,
        nameEn: kCountryNamesEn[iso.name]!,
        nameAr: kCountryNamesAr[iso.name]!,
      ),
]);

final Map<IsoCode, PhoneCountry> _byIso = {
  for (final country in kPhoneCountries) country.iso: country,
};

/// The region of [iso].
PhoneCountry phoneCountry(IsoCode iso) => _byIso[iso] ?? kDefaultPhoneCountry;

/// The region named by a code such as `AE` or `ae`; null for any other text.
PhoneCountry? phoneCountryByCode(String code) {
  final upper = code.trim().toUpperCase();
  for (final country in kPhoneCountries) {
    if (country.code == upper) return country;
  }
  return null;
}

/// The store's own country: where a number typed without a country code is
/// taken to be, and what the field starts on. The marketplace sells in the UAE
/// (AED). The website's own field starts on Egypt and puts Egypt and the US
/// first, a setting of its SMS module that predates the Hub Market store.
final PhoneCountry kDefaultPhoneCountry = _byIso[IsoCode.AE]!;

/// The regions listed above the alphabet, in this order: the store's own, then
/// the two the website's phone field puts first.
final List<PhoneCountry> kPreferredPhoneCountries = List.unmodifiable([
  _byIso[IsoCode.AE]!,
  _byIso[IsoCode.EG]!,
  _byIso[IsoCode.US]!,
]);

/// The region a country calling code (`971`, `20`, `1`) names. Several share
/// `1` and `7`: the first is the main one (`US`, `RU`). Null for a code nobody
/// has.
PhoneCountry? phoneCountryForDialCode(String dialCode) {
  final isos = countryCodeToIsoCode[dialCode];
  if (isos == null || isos.isEmpty) return null;
  return _byIso[isos.first];
}

/// The regions that could be [digits] typed after a `+`: the calling code at
/// its start and what follows it. Null while the digits are not yet a calling
/// code. Calling codes are prefix-free, so the first of 1, 2 or 3 digits that
/// is one is the only one.
({PhoneCountry country, String rest})? matchDialCodePrefix(String digits) {
  for (var length = 1; length <= 3 && length <= digits.length; length++) {
    final country = phoneCountryForDialCode(digits.substring(0, length));
    if (country != null) {
      return (country: country, rest: digits.substring(length));
    }
  }
  return null;
}
