import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/widgets/phone_number_field.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';

/// The mobile number the frames draw (Figma "Input" with the `phone` glyph and
/// `+971 50 123 4567`): captured at Register's mobile field position (16, 345)
/// so it can be laid over frame 04.
Widget _app(
  Widget field, {
  String locale = 'en',
  GlobalKey? boundary,
}) {
  final app = MaterialApp(
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
        padding: const EdgeInsets.fromLTRB(16, 345, 16, 0),
        child: Align(alignment: Alignment.topCenter, child: field),
      ),
    ),
  );
  return boundary == null ? app : RepaintBoundary(key: boundary, child: app);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('the field as the frames draw it ($locale)', (tester) async {
      _phone(tester);
      final key = GlobalKey();
      final controller = TextEditingController(text: '50 123 4567');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          PhoneNumberField(controller: controller, hint: '50 123 4567'),
          locale: locale,
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'phone_field_$locale');

      // A 52 px field, the 20 px phone glyph and the dial code in Body.
      expect(tester.getSize(find.byType(TextFormField)).height, 52);
      expect(tester.getSize(find.byIcon(HubIcons.phone)), const Size(20, 20));
      expect(find.text('+971'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the dial code and the glyph are on the leading edge', (
    tester,
  ) async {
    for (final locale in ['en', 'ar']) {
      _phone(tester);
      final controller = TextEditingController(text: '501234567');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          PhoneNumberField(controller: controller, hint: ''),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(TextFormField));
      final glyph = tester.getRect(find.byIcon(HubIcons.phone));
      if (locale == 'en') {
        // 1 px outline and 16 px of padding.
        expect(glyph.left - field.left, 17);
      } else {
        expect(field.right - glyph.right, 17);
      }
    }
  });

  testWidgets('an error is a red line with an alert, 6 px under the field', (
    tester,
  ) async {
    _phone(tester);
    final controller = TextEditingController(text: '123');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        PhoneNumberField(
          controller: controller,
          hint: '',
          errorText: 'That number is already in use',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextFormField));
    final line = tester.getRect(find.text('That number is already in use'));
    expect(find.byIcon(HubIcons.triangleAlert), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('That number is already in use'))
          .style!
          .color,
      AppColors.danger,
    );
    // The line sits under the field's own 52 px.
    expect(line.top, greaterThan(field.top + 52));
  });

  testWidgets('typing reports the digits as they are entered', (tester) async {
    _phone(tester);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final seen = <String>[];
    await tester.pumpWidget(
      _app(
        PhoneNumberField(
          controller: controller,
          hint: '50 123 4567',
          onChanged: seen.add,
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '501234567');
    expect(seen, ['501234567']);
    expect(controller.text, '501234567');
  });
}
