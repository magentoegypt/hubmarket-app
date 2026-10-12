import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../phone/phone_country.dart';

/// Phone-number helpers for the WhatsApp-OTP flows and the address forms.
///
/// We always send the **explicit E.164** form (`+971501234567`,
/// `+201001234567`), however the customer typed it. That is the format the
/// website's phone field stores in the customer's `mobilenumber`, and the
/// Vnecoms SMS GraphQL mutations (registration, password reset, change mobile)
/// match that attribute exactly — a bare `0501234567` would miss the account.
/// The backend takes a number written `+<country code>…` as dialled, whatever
/// the country (`MobileNumber::canonical`), so the same form carries any
/// country's number.
///
/// Numbers are read with libphonenumber's rules (`phone_numbers_parser`): the
/// trunk prefix, the exit code, grouping and Arabic digits are all understood,
/// and a number is valid when its country's own patterns say so.
abstract final class Phone {
  /// The store's own calling code: a stored number with no `+` is taken to be
  /// a number of this country (the UAE).
  static const String uaeDial = '971';

  static final RegExp _hasDigit = RegExp(r'\p{Nd}', unicode: true);

  /// [text] with its Arabic-Indic and Persian digits written as 0-9 (a phone's
  /// Arabic keyboard types the first), everything else as it was.
  static String latinDigits(String text) {
    const arabicIndic = 0x0660;
    const persian = 0x06F0;
    return String.fromCharCodes([
      for (final unit in text.codeUnits)
        if (unit >= arabicIndic && unit <= arabicIndic + 9)
          0x30 + unit - arabicIndic
        else if (unit >= persian && unit <= persian + 9)
          0x30 + unit - persian
        else
          unit,
    ]);
  }

  /// [raw] read as a number. Written with a `+` or the `00` exit code it names
  /// its own country; otherwise it is a number of [country] — the store's own
  /// (the UAE) when none is given — in any spelling the app has accepted: with
  /// or without the trunk 0, with its country code and no `+`. Null when there
  /// is no digit to read or no region fits.
  static PhoneNumber? parse(String raw, {PhoneCountry? country}) {
    final text = raw.trim();
    if (!_hasDigit.hasMatch(text)) return null;
    final international = text.startsWith('+') || text.startsWith('00');
    try {
      return PhoneNumber.parse(
        text,
        destinationCountry: international
            ? null
            : (country ?? kDefaultPhoneCountry).iso,
      );
    } on Object {
      return null;
    }
  }

  /// [raw] in E.164 (`+971501234567`): the number as it is dialled, whatever
  /// the customer typed. Best effort — a number that is not valid still comes
  /// back in this form; callers check [isValid] before sending. Empty for no
  /// digits.
  static String normalize(String raw, {PhoneCountry? country}) {
    final parsed = parse(raw, country: country);
    if (parsed != null) return parsed.international;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? '' : '+$digits';
  }

  /// Whether [raw] is a valid number of [country] (or of its own, written with
  /// a `+`). [mobileOnly]: it must be a mobile — a WhatsApp or SMS code does
  /// not reach a landline.
  static bool isValid(
    String raw, {
    PhoneCountry? country,
    bool mobileOnly = false,
  }) =>
      parse(raw, country: country)?.isValid(
        type: mobileOnly ? PhoneNumberType.mobile : null,
      ) ??
      false;

  /// A number as the frames print it: `+971501234567` → `+971 50 123 4567`
  /// (`+201001234567` → `+20 10 01234567`). A shape that is not a valid number
  /// comes back as it was stored.
  static String display(String raw) {
    final parsed = parse(raw);
    if (parsed == null || !parsed.isValid()) return raw;
    return '+${parsed.countryCode} '
        '${parsed.formatNsn(format: NsnFormat.international)}';
  }

  /// Masks a number for the "Code sent to …" caption, e.g.
  /// `+971501234567` → `+971 50 ••• 4567`: the start and the end of the number
  /// show, the middle does not (a short number shows less). Falls back to the
  /// normalized form when it is not a valid number.
  static String mask(String raw) {
    final parsed = parse(raw);
    if (parsed == null || !parsed.isValid()) {
      final normalized = normalize(raw);
      return normalized.isEmpty ? raw : normalized;
    }
    final nsn = parsed.nsn;
    final head = nsn.length >= 8 ? 2 : 0;
    final tail = nsn.length >= 9 ? 4 : (nsn.length >= 7 ? 3 : 2);
    final start = head == 0 ? '' : '${nsn.substring(0, head)} ';
    return '+${parsed.countryCode} $start•••'
        ' ${nsn.substring(nsn.length - tail)}';
  }

  /// [mask], wrapped in a Unicode LTR isolate (U+2066 … U+2069) so it renders
  /// as a self-contained left-to-right run when interpolated into an Arabic
  /// (RTL) caption — otherwise the leading `+` and the digit groups reorder
  /// under the bidi algorithm. Use this in "Code sent to {phone}" strings.
  static String maskBidi(String raw) => '\u{2066}${mask(raw)}\u{2069}';
}
