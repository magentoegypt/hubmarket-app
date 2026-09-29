import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import 'phone.dart';

/// Localized form-field validators.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(BuildContext context, String? value) =>
      (value == null || value.trim().isEmpty)
      ? AppLocalizations.of(context).validationRequired
      : null;

  static String? email(BuildContext context, String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.validationRequired;
    return _email.hasMatch(value.trim()) ? null : l10n.validationEmail;
  }

  static String? password(BuildContext context, String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) return l10n.validationRequired;
    return value.length >= 8 ? null : l10n.validationPassword;
  }

  /// UAE mobile number (E.164 or local) for the WhatsApp-OTP flows.
  static String? uaePhone(BuildContext context, String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.validationRequired;
    return Phone.isValidUae(value) ? null : l10n.validationPhoneUae;
  }

  /// Confirms two password fields match (used by the phone-reset flow).
  static String? confirmPassword(
    BuildContext context,
    String? value,
    String other,
  ) {
    final l10n = AppLocalizations.of(context);
    final base = password(context, value);
    if (base != null) return base;
    return value == other ? null : l10n.validationPasswordMatch;
  }
}
