import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import 'password_policy.dart';
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

  /// An existing password (sign in, confirming a change). Its message names
  /// no length: the store's minimum is an admin setting.
  static String? password(BuildContext context, String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) return l10n.validationRequired;
    return value.length >= 8 ? null : l10n.validationPassword;
  }

  /// Whether [value] meets the rule for a new password: the store's own
  /// [policy] (core `storeConfig`) when it has been read; otherwise the app's
  /// fallback — 8+ characters with a letter, a number and a symbol, which
  /// satisfies Magento's default policy (8 characters, 3 of the 4 character
  /// classes), so a password passing it is never refused for strength.
  static bool meetsPasswordRule(String value, [PasswordPolicy? policy]) =>
      policy?.accepts(value) ??
      (value.length >= 8 &&
          RegExp('[0-9]').hasMatch(value) &&
          RegExp('[^a-zA-Z0-9]').hasMatch(value) &&
          RegExp('[a-zA-Z]').hasMatch(value));

  /// The rule line under a new-password field: the store's [policy] in
  /// words, or — until it is read — a generic line that names no setting.
  static String passwordRuleText(
    AppLocalizations l10n,
    PasswordPolicy? policy,
  ) {
    if (policy == null) return l10n.validationPasswordRule;
    return policy.requiredClasses > 1
        ? l10n.validationPasswordPolicy(
            policy.minLength,
            policy.requiredClasses,
          )
        : l10n.validationPasswordMinLength(policy.minLength);
  }

  /// [meetsPasswordRule] as a validator. A miss returns `''`: the field turns
  /// red and the rule line under it (not a second message) says why.
  static String? newPassword(
    BuildContext context,
    String? value, {
    PasswordPolicy? policy,
  }) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context).validationRequired;
    }
    return meetsPasswordRule(value, policy) ? null : '';
  }

  /// UAE mobile number (E.164 or local) for the WhatsApp-OTP flows.
  static String? uaePhone(BuildContext context, String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.validationRequired;
    return Phone.isValidUae(value) ? null : l10n.validationPhoneUae;
  }

  /// Confirms two password fields match (used by the phone-reset flow). The
  /// strength is the new-password field's job ([newPassword]), against the
  /// store's policy.
  static String? confirmPassword(
    BuildContext context,
    String? value,
    String other,
  ) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) return l10n.validationRequired;
    return value == other ? null : l10n.validationPasswordMatch;
  }
}
