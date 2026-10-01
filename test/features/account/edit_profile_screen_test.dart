import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/validation/password_policy.dart';
import 'package:hubmarket_app/core/widgets/hub_switch.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/profile_extras.dart';
import 'package:hubmarket_app/features/account/presentation/profile_extras_provider.dart';
import 'package:hubmarket_app/features/account/presentation/screens/edit_profile_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_field.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import 'audit_harness.dart';

/// Profile details (Figma 20c): two name fields, the e-mail with "Verified"
/// when the store confirmed it, the mobile number, the date of birth and the
/// Change password card, saved with one button.

final en = lookupAppLocalizations(const Locale('en'));

/// Records what Save changes sends.
class _RecordingAccount extends FakeAccountRepository {
  final List<Map<String, String?>> profiles = [];
  final List<String> passwords = [];

  @override
  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    String? dateOfBirth,
  }) async {
    profiles.add({
      'first': firstName,
      'last': lastName,
      'dob': dateOfBirth,
    });
  }

  @override
  Future<void> changePassword(String current, String next) async {
    passwords.add('$current>$next');
  }
}

Future<_RecordingAccount> _pump(
  WidgetTester tester, {
  ProfileExtras? extras = const ProfileExtras(),
}) async {
  final account = _RecordingAccount();
  await pumpAuditScreen(
    tester,
    screen: const EditProfileScreen(),
    height: 1400,
    overrides: [
      accountRepositoryProvider.overrideWithValue(account),
      profileExtrasProvider.overrideWith((ref) async => extras),
    ],
  );
  return account;
}

Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AuthField)),
  matching: find.byType(TextField),
);

Finder get _save => find.widgetWithText(FilledButton, en.profileSaveChanges);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the name is two fields; the page keeps no preferences', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(en.profileTitle), findsOneWidget);
    expect(
      tester.widget<TextField>(_field(en.fieldFirstName)).controller?.text,
      'Sara',
    );
    expect(
      tester.widget<TextField>(_field(en.fieldLastName)).controller?.text,
      'Ahmed',
    );
    expect(find.text('sara.ahmed@gmail.com'), findsOneWidget);
    expect(find.text('+971 50 123 4567'), findsOneWidget);
    // Language, push and e-mail offers live on Account now.
    expect(find.text(en.profilePreferences), findsNothing);
    expect(find.text(en.languageToggleLabel), findsNothing);
    // The backend has no customer photo.
    expect(find.textContaining('photo'), findsNothing);
  });

  group('Verified', () {
    testWidgets('shown once the store confirmed the address', (tester) async {
      await _pump(
        tester,
        extras: const ProfileExtras(emailConfirmed: true),
      );
      // Under the e-mail only: nothing says the mobile number was verified.
      expect(find.text(en.profileVerified), findsOneWidget);
    });

    testWidgets('left out when the store never asked for confirmation', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text(en.profileVerified), findsNothing);
    });
  });

  testWidgets('the date of birth is the account\'s', (tester) async {
    await _pump(tester, extras: const ProfileExtras(dateOfBirth: '1994-03-12'));
    expect(find.text('12 Mar 1994'), findsOneWidget);
  });

  testWidgets('no date of birth asks to select one', (tester) async {
    await _pump(tester);
    expect(find.text(en.profileBirthDatePick), findsOneWidget);
  });

  testWidgets('Save changes sends the names and the date of birth', (
    tester,
  ) async {
    final account = await _pump(
      tester,
      extras: const ProfileExtras(dateOfBirth: '1994-03-12'),
    );
    await tester.enterText(_field(en.fieldFirstName), 'Sarah');
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(account.profiles, [
      {'first': 'Sarah', 'last': 'Ahmed', 'dob': '1994-03-12'},
    ]);
    expect(account.passwords, isEmpty);
    expect(find.text(en.profileSaved), findsOneWidget);
  });

  testWidgets('a name left empty is not sent', (tester) async {
    final account = await _pump(tester);
    await tester.enterText(_field(en.fieldLastName), '');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(account.profiles, isEmpty);
    expect(find.text(en.validationRequired), findsOneWidget);
  });

  group('Change password', () {
    testWidgets('closed, it asks for nothing', (tester) async {
      await _pump(tester);
      expect(find.text(en.fieldCurrentPassword), findsNothing);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(find.text(en.validationRequired), findsNothing);
    });

    testWidgets('open, the three fields go to the store with Save changes', (
      tester,
    ) async {
      final account = await _pump(tester);
      await tester.tap(find.byType(HubSwitch));
      await tester.pumpAndSettle();
      await tester.enterText(_field(en.fieldCurrentPassword), 'old-secret');
      await tester.enterText(_field(en.fieldNewPassword), 'New@2026x');
      await tester.enterText(
        _field(en.profileConfirmNewPassword),
        'New@2026x',
      );
      await tester.ensureVisible(_save);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(account.profiles, hasLength(1));
      expect(account.passwords, ['old-secret>New@2026x']);
      expect(find.text(en.passwordChanged), findsOneWidget);
      // The card closes and forgets what was typed.
      expect(find.text(en.fieldCurrentPassword), findsNothing);
    });

    testWidgets('a confirmation that differs stops the save', (tester) async {
      final account = await _pump(tester);
      await tester.tap(find.byType(HubSwitch));
      await tester.pumpAndSettle();
      await tester.enterText(_field(en.fieldCurrentPassword), 'old-secret');
      await tester.enterText(_field(en.fieldNewPassword), 'New@2026x');
      await tester.enterText(_field(en.profileConfirmNewPassword), 'New@2026y');
      await tester.ensureVisible(_save);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text(en.validationPasswordMatch), findsOneWidget);
      expect(account.profiles, isEmpty);
      expect(account.passwords, isEmpty);
    });
  });

  group('the strength bar fills with what the password has', () {
    test('nothing typed, nothing lit', () {
      expect(profilePasswordStrength(''), 0);
    });

    test('length, a letter, a digit and a symbol each add one', () {
      expect(profilePasswordStrength('abc'), 1);
      expect(profilePasswordStrength('abc123'), 2);
      expect(profilePasswordStrength('abcdefgh12'), 3);
      expect(profilePasswordStrength('abcdefg1!'), 4);
    });

    test('the store\'s own minimum length counts', () {
      const policy = PasswordPolicy(minLength: 12, requiredClasses: 3);
      expect(profilePasswordStrength('abcdefgh12', policy), 2);
      expect(profilePasswordStrength('abcdefghij12!', policy), 4);
    });
  });
}
