import 'package:flutter/widgets.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../validation/phone.dart';
import 'phone_country.dart';

/// What a phone field holds: the country the number is of and the number as the
/// shopper types it in that country (`050 123 4567`, `0100 123 4567`).
///
/// Everything a screen needs comes from here: [e164] to send, [isValid] to
/// check, [setNumber] to fill the field from a stored number, [text] for the
/// text field. The country follows what is typed: a number written with its
/// country code (`+971 50 123 4567`, `00971…`, as a phone's autofill and a paste
/// give it) switches the country to the one the code names and leaves only the
/// rest in [text], as the website's field does.
class PhoneFieldController extends ChangeNotifier {
  /// A field for [country] (the store's own by default), filled with [number]
  /// when there is one.
  PhoneFieldController({String? number, PhoneCountry? country})
    : _country = country ?? kDefaultPhoneCountry {
    text.addListener(_absorbCountryCode);
    if (number != null && number.trim().isNotEmpty) setNumber(number);
  }

  /// The text field's controller: the national number, as typed.
  final TextEditingController text = TextEditingController();

  PhoneCountry _country;
  bool _absorbing = false;

  /// The country the number is of.
  PhoneCountry get country => _country;

  set country(PhoneCountry value) {
    if (value == _country) return;
    _country = value;
    notifyListeners();
  }

  PhoneNumber? get _phone => Phone.parse(text.text, country: _country);

  /// Nothing, or no digit, is typed.
  bool get isEmpty => Phone.latinDigits(text.text).replaceAll(RegExp(r'\D'), '').isEmpty;

  /// The number in E.164 (`+971501234567`), or empty when nothing is typed.
  /// Best effort: a number that is not valid still has its form; check
  /// [isValid] before sending it.
  String get e164 => _phone?.international ?? '';

  /// Whether the number is a valid one of [country]. [mobileOnly]: it must be
  /// a mobile (a WhatsApp or SMS code does not reach a landline).
  bool isValid({bool mobileOnly = false}) =>
      _phone?.isValid(type: mobileOnly ? PhoneNumberType.mobile : null) ??
      false;

  /// Fills the field from a stored number (`+971501234567`, or an older
  /// spelling of a UAE number): its country, and the number in that country's
  /// grouping. Text that is no number is shown as it is.
  void setNumber(String stored) {
    final parsed = Phone.parse(stored);
    _absorbing = true;
    if (parsed == null) {
      text.text = stored.trim();
    } else {
      _country = phoneCountry(parsed.isoCode);
      text.text = parsed.isValid()
          ? parsed.formatNsn(format: NsnFormat.international)
          : parsed.nsn;
    }
    _absorbing = false;
    notifyListeners();
  }

  /// Empties the number; the country stays.
  void clear() => text.clear();

  /// A number written with its country code: the code picks the country and
  /// leaves the rest of the number in [text].
  void _absorbCountryCode() {
    if (_absorbing) return;
    final raw = Phone.latinDigits(text.text).trim();
    final plus = raw.startsWith('+');
    if (!plus && !raw.startsWith('00')) return;
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (!plus) digits = digits.substring(2);
    final match = matchDialCodePrefix(digits);
    if (match == null) return;

    // Regions share a calling code (+1 is a score of them): the whole number
    // says which, when it is long enough to.
    var country = match.country;
    if (match.rest.length >= 3) {
      try {
        final whole = PhoneNumber.parse('+$digits');
        if (whole.countryCode == match.country.dialCode) {
          country = phoneCountry(whole.isoCode);
        }
      } on Object {
        // The main region of the code stands.
      }
    }
    _absorbing = true;
    _country = country;
    text.value = TextEditingValue(
      text: match.rest,
      selection: TextSelection.collapsed(offset: match.rest.length),
    );
    _absorbing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    text
      ..removeListener(_absorbCountryCode)
      ..dispose();
    super.dispose();
  }
}
