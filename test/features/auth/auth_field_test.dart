import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_field.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

/// Figma "Input" (03 / 04 / 06 / S6): the content sits 17 px in from the field's
/// outer edge (1 px outline + 16 px of padding), the icon is 20 px with the text
/// 10 px after it, the eye is a 20 px icon 17 px from the far edge, and the field
/// is 52 px high. Material 3's decorator adds 4 px of its own beside the text,
/// which the field's paddings take off.
Widget _app(Widget child, {String locale = 'en'}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(locale),
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  for (final locale in ['en', 'ar']) {
    final rtl = locale == 'ar';

    testWidgets('a field with an icon and the eye ($locale)', (tester) async {
      _phone(tester);
      final controller = TextEditingController(text: 'Sara@2026x');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          AuthField(
            controller: controller,
            label: 'Password',
            icon: HubIcons.lock,
            obscureText: true,
            trailing: PasswordVisibilityToggle(
              obscured: true,
              onPressed: () {},
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(TextField));
      expect(field.height, 52);
      expect(field.width, 358);
      final lock = tester.getRect(find.byIcon(HubIcons.lock));
      final eye = tester.getRect(find.byIcon(HubIcons.eye));
      final text = tester.getRect(find.byType(EditableText));
      expect(lock.size, const Size(20, 20));
      expect(eye.size, const Size(20, 20));
      if (rtl) {
        expect(field.right - lock.right, 17);
        expect(eye.left - field.left, 17);
        expect(lock.left - text.right, 10);
      } else {
        expect(lock.left - field.left, 17);
        expect(field.right - eye.right, 17);
        expect(text.left - lock.right, 10);
      }
      // The eye's target is 40 px; its icon is centred in it.
      final toggle = tester.getRect(find.byType(PasswordVisibilityToggle));
      expect(toggle.size, const Size(40, 40));
    });

    testWidgets('a field without an icon ($locale)', (tester) async {
      _phone(tester);
      final controller = TextEditingController(text: 'Sara');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          AuthField(controller: controller, label: 'First name'),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(TextField));
      final text = tester.getRect(find.byType(EditableText));
      expect(field.height, 52);
      if (rtl) {
        expect(field.right - text.right, 17);
        expect(text.left - field.left, 17);
      } else {
        expect(text.left - field.left, 17);
        expect(field.right - text.right, 17);
      }
    });
  }

  testWidgets('the label sits 6 px above the field and the error 6 px below', (
    tester,
  ) async {
    _phone(tester);
    final controller = TextEditingController(text: 'sara@');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        AuthField(
          controller: controller,
          label: 'Email address',
          icon: HubIcons.mail,
          errorText: 'Enter a valid email address',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.getRect(find.text('Email address'));
    final field = tester.getRect(find.byType(TextField));
    final error = tester.getRect(find.text('Enter a valid email address'));
    // Caption Strong is 16 px high; 6 px between the label and the field.
    expect(field.top - label.bottom, closeTo(6, 0.5));
    // The helper line is 16 px high, 6 px under the field.
    expect(error.top - field.bottom, closeTo(6, 1.5));
    expect(find.byIcon(HubIcons.triangleAlert), findsOneWidget);
  });
}
