import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/validation/password_policy.dart';
import 'package:hubmarket_app/core/validation/validators.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  group('PasswordPolicy from storeConfig', () {
    test('reads the live answer (Strings on the wire)', () {
      final features = StoreFeatures.fromJson(const {
        'minimum_password_length': '8',
        'required_character_classes_number': '3',
        'newsletter_enabled': true,
        'contact_enabled': true,
      });
      expect(
        features.passwordPolicy,
        const PasswordPolicy(minLength: 8, requiredClasses: 3),
      );
    });

    test('no usable minimum → no policy; classes default to 1, capped at 4', () {
      expect(PasswordPolicy.fromStoreConfig(const {}), isNull);
      expect(
        PasswordPolicy.fromStoreConfig(const {'minimum_password_length': ''}),
        isNull,
      );
      expect(
        PasswordPolicy.fromStoreConfig(const {'minimum_password_length': '6'}),
        const PasswordPolicy(minLength: 6, requiredClasses: 1),
      );
      expect(
        PasswordPolicy.fromStoreConfig(const {
          'minimum_password_length': 10,
          'required_character_classes_number': '9',
        }),
        const PasswordPolicy(minLength: 10, requiredClasses: 4),
      );
    });

    test('accepts what Magento accepts: length and character classes', () {
      const policy = PasswordPolicy(minLength: 8, requiredClasses: 3);
      // Lower + upper + digit: three classes, no symbol needed.
      expect(policy.accepts('Abcdefg1'), isTrue);
      expect(policy.accepts('sara@2026'), isTrue);
      expect(policy.accepts('sarapassword'), isFalse); // one class
      expect(policy.accepts('Sara2026'), isTrue);
      expect(policy.accepts('Sa@20'), isFalse); // too short
    });
  });

  group('the rule line names the store policy, never a hard-coded one', () {
    test('with the policy', () {
      const policy = PasswordPolicy(minLength: 8, requiredClasses: 3);
      expect(
        Validators.passwordRuleText(en, policy),
        'At least 8 characters, with 3 of: a–z, A–Z, 0–9, symbols',
      );
      expect(
        Validators.passwordRuleText(ar, policy),
        '8 أحرف على الأقل، مع 3 مما يلي: a–z، A–Z، 0–9، رموز',
      );
      expect(
        Validators.passwordRuleText(
          en,
          const PasswordPolicy(minLength: 12, requiredClasses: 1),
        ),
        'At least 12 characters',
      );
      expect(
        Validators.passwordRuleText(
          ar,
          const PasswordPolicy(minLength: 12, requiredClasses: 1),
        ),
        '12 حرفًا على الأقل',
      );
    });

    test('without it: generic wording and the app’s own safe rule', () {
      final text = Validators.passwordRuleText(en, null);
      expect(text, isNot(contains(RegExp(r'\d'))));
      expect(Validators.meetsPasswordRule('Sara@2026x'), isTrue);
      expect(Validators.meetsPasswordRule('Abcdefg1'), isFalse);
      // The store's policy decides once read.
      expect(
        Validators.meetsPasswordRule(
          'Abcdefg1',
          const PasswordPolicy(minLength: 8, requiredClasses: 3),
        ),
        isTrue,
      );
    });

    test('the copy names no store setting', () {
      for (final l10n in [en, ar]) {
        for (final text in [
          l10n.validationPassword,
          l10n.validationPasswordRule,
          l10n.authForgotLinkNote,
          l10n.authErrorWrongCredentialsHint,
        ]) {
          expect(text, isNot(contains(RegExp(r'\d'))), reason: text);
        }
      }
    });
  });
}
