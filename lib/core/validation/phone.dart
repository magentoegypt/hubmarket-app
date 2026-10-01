/// UAE phone-number helpers for the WhatsApp-OTP flows.
///
/// We always send the **explicit E.164** form (`+971501234567`), however the
/// customer typed it. That is the format the website's phone field stores in
/// the customer's `mobilenumber`, and the Vnecoms SMS GraphQL mutations
/// (registration, password reset, change mobile) match that attribute exactly —
/// a bare `0501234567` would miss the account. (The REST sign-in endpoint also
/// accepts other spellings, but consistency matters for the others.)
abstract final class Phone {
  static const String uaeDial = '971';

  /// UAE mobile shape after normalization: `9715` + one of `0/2/4/5/6/8` + 7
  /// digits. Applied to the E.164 form.
  static final RegExp _uaeE164 = RegExp(r'^\+9715[024568]\d{7}$');

  /// Normalizes user input to E.164 for a +971 store. Accepts `+971501234567`,
  /// `00971501234567`, `971501234567`, `0501234567`, `501234567`, and tolerates
  /// spaces / dashes / parentheses. Returns the best-effort `+…` form; callers
  /// validate with [isValidUae] before sending.
  static String normalizeUae(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    final hadPlus = s.startsWith('+');
    // Keep digits only; a leading '+' is re-applied via the branches below.
    var digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (hadPlus) {
      // Already international (the user typed the country code).
      return '+$digits';
    }
    if (digits.startsWith('00')) {
      // 00-prefixed international dialing → strip to '+'.
      return '+${digits.substring(2)}';
    }
    if (digits.startsWith(uaeDial)) {
      return '+$digits';
    }
    if (digits.startsWith('0')) {
      // Local form (05x…) → drop the trunk zero and prepend the UAE dial code.
      return '+$uaeDial${digits.substring(1)}';
    }
    // Bare subscriber number (5x…) → prepend the UAE dial code.
    return '+$uaeDial$digits';
  }

  /// True when [raw] normalizes to a valid UAE mobile number.
  static bool isValidUae(String raw) => _uaeE164.hasMatch(normalizeUae(raw));

  /// The local subscriber digits (no `+971`) for a `+971`-prefixed input field,
  /// so a stored E.164 value (`+971501234567`) prefills the [PhoneNumberField]
  /// as `501234567` (the chip already shows `+971`). Empty stays empty.
  static String localPart(String raw) {
    final e164 = normalizeUae(raw);
    if (e164.isEmpty) return '';
    return e164.startsWith('+$uaeDial')
        ? e164.substring(1 + uaeDial.length)
        : e164.replaceAll('+', '');
  }

  /// A UAE mobile spaced the way people write it, `+971 50 123 4567`, whatever
  /// form it was saved in; any other number as it is.
  static String display(String raw) {
    final m = RegExp(
      r'^\+971(\d{2})(\d{3})(\d{4})$',
    ).firstMatch(normalizeUae(raw));
    return m == null ? raw.trim() : '+971 ${m[1]} ${m[2]} ${m[3]}';
  }

  /// Masks a number for the "Code sent to …" caption, e.g.
  /// `+971501234567` → `+971 50 ••• 4567`. Falls back to the normalized form
  /// when the shape is unexpected (non-UAE numbers stay readable).
  static String mask(String raw) {
    final e164 = normalizeUae(raw);
    if (!_uaeE164.hasMatch(e164)) return e164.isEmpty ? raw : e164;
    // e164 = '+971' + 9 subscriber digits (e.g. 501234567).
    final sub = e164.substring(4); // drop '+971'
    final head = sub.substring(0, 2); // '50'
    final tail = sub.substring(sub.length - 4); // '4567'
    return '+$uaeDial $head ••• $tail';
  }

  /// [mask], wrapped in a Unicode LTR isolate (U+2066 … U+2069) so it renders
  /// as a self-contained left-to-right run when interpolated into an Arabic
  /// (RTL) caption — otherwise the leading `+` and the digit groups reorder
  /// under the bidi algorithm. Use this in "Code sent to {phone}" strings.
  static String maskBidi(String raw) => '\u{2066}${mask(raw)}\u{2069}';
}
