import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/phone/phone_country.dart';
import 'package:hubmarket_app/core/phone/phone_field_controller.dart';
import 'package:hubmarket_app/core/widgets/country_picker_sheet.dart';
import 'package:hubmarket_app/core/widgets/phone_number_field.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';

/// The mobile number the frames draw (Figma "Input", `+971 50 123 4567`) with the
/// country chip the website's field has: captured at Register's mobile field
/// position (16, 345) so it can be laid over frame 04.
Widget _app(
  Widget field, {
  String locale = 'en',
  GlobalKey? boundary,
  GlobalKey<FormState>? form,
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
        child: Align(
          alignment: Alignment.topCenter,
          child: form == null ? field : Form(key: form, child: field),
        ),
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

PhoneFieldController _controller({String? number}) {
  final controller = PhoneFieldController(number: number);
  addTearDown(controller.dispose);
  return controller;
}

final _chip = find.byKey(const ValueKey('phone-country-chip'));

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('the field as the frames draw it, with a country chip '
        '($locale)', (tester) async {
      _phone(tester);
      final key = GlobalKey();
      final controller = _controller(number: '+971501234567');
      await tester.pumpWidget(
        _app(
          PhoneNumberField(controller: controller),
          locale: locale,
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'phone_field_$locale');

      // A 52 px field, the calling code in Body, the chevron, the number.
      expect(tester.getSize(find.byType(TextField)).height, 52);
      expect(find.text('+971'), findsOneWidget);
      expect(find.byIcon(HubIcons.chevronDown), findsOneWidget);
      expect(controller.text.text, '50 123 4567');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the chip sits on the leading edge, 17 px in, in both '
      'directions', (tester) async {
    for (final locale in ['en', 'ar']) {
      _phone(tester);
      final controller = _controller(number: '+971501234567');
      await tester.pumpWidget(
        _app(PhoneNumberField(controller: controller), locale: locale),
      );
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(TextField));
      final flag = tester.getRect(find.text(controller.country.flag));
      if (locale == 'en') {
        // 1 px outline and 16 px of padding.
        expect(flag.left - field.left, 17);
      } else {
        expect(field.right - flag.right, 17);
      }
    }
  });

  testWidgets('the empty field hints at a number of the country on the chip',
      (tester) async {
    _phone(tester);
    final controller = _controller();
    await tester.pumpWidget(_app(PhoneNumberField(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('50 123 4567'), findsOneWidget);

    controller.country = phoneCountryByCode('EG')!;
    await tester.pumpAndSettle();
    expect(find.text('50 123 4567'), findsNothing);
    expect(find.text(phoneCountryByCode('EG')!.exampleNumber), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
  });

  testWidgets('an error is a red line with an alert, 6 px under the field', (
    tester,
  ) async {
    _phone(tester);
    final controller = _controller();
    controller.text.text = '123';
    await tester.pumpWidget(
      _app(
        PhoneNumberField(
          controller: controller,
          errorText: 'That number is already in use',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextField));
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

  testWidgets('typing reports what is typed, and the controller has the '
      'number', (tester) async {
    _phone(tester);
    final controller = _controller();
    final seen = <String>[];
    await tester.pumpWidget(
      _app(PhoneNumberField(controller: controller, onChanged: seen.add)),
    );
    await tester.enterText(find.byType(TextField), '501234567');
    expect(seen, ['501234567']);
    expect(controller.text.text, '501234567');
    expect(controller.e164, '+971501234567');
  });

  testWidgets('keeps to what a number is made of, and writes Arabic digits as '
      '0-9', (tester) async {
    _phone(tester);
    final controller = _controller();
    await tester.pumpWidget(_app(PhoneNumberField(controller: controller)));

    await tester.enterText(find.byType(TextField), '05a0 123-4_567x');
    expect(controller.text.text, '050 123-4567');

    await tester.enterText(find.byType(TextField), '٠٥٠١٢٣٤٥٦٧');
    expect(controller.text.text, '050123456 7'.replaceAll(' ', ''));
    expect(controller.e164, '+971501234567');
  });

  testWidgets('a number pasted with its country code sets the chip and keeps '
      'the rest', (tester) async {
    _phone(tester);
    final controller = _controller();
    await tester.pumpWidget(_app(PhoneNumberField(controller: controller)));

    await tester.enterText(find.byType(TextField), '+20 100 123 4567');
    await tester.pumpAndSettle();

    expect(controller.country.code, 'EG');
    expect(find.text('+20'), findsOneWidget);
    expect(controller.text.text, '1001234567');
    expect(controller.isValid(mobileOnly: true), isTrue);
  });

  testWidgets('tapping the chip lists the countries; picking one changes the '
      'chip, tells the screen and returns to the number', (tester) async {
    _phone(tester);
    final controller = _controller();
    final seen = <String>[];
    await tester.pumpWidget(
      _app(PhoneNumberField(controller: controller, onChanged: seen.add)),
    );

    await tester.tap(_chip);
    await tester.pumpAndSettle();
    expect(find.byType(CountryPickerSheet), findsOneWidget);

    await tester.tap(find.text('Egypt').first);
    await tester.pumpAndSettle();

    expect(find.byType(CountryPickerSheet), findsNothing);
    expect(controller.country.code, 'EG');
    expect(find.text('+20'), findsOneWidget);
    expect(seen, hasLength(1));
    // The number field has the focus, ready for the digits.
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('closing the list without a pick changes nothing', (tester) async {
    _phone(tester);
    final controller = _controller();
    await tester.pumpWidget(_app(PhoneNumberField(controller: controller)));

    await tester.tap(_chip);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(CountryPickerSheet), findsNothing);
    expect(controller.country.code, 'AE');
  });

  testWidgets('a field that is switched off does not open the list', (
    tester,
  ) async {
    _phone(tester);
    final controller = _controller();
    await tester.pumpWidget(
      _app(PhoneNumberField(controller: controller, enabled: false)),
    );
    await tester.tap(_chip, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(CountryPickerSheet), findsNothing);
  });

  group('the message under the field', () {
    Future<String?> validate(
      WidgetTester tester, {
      required String typed,
      String locale = 'en',
      bool mobileOnly = false,
      String country = 'AE',
    }) async {
      _phone(tester);
      final form = GlobalKey<FormState>();
      final controller = _controller();
      controller.country = phoneCountryByCode(country)!;
      controller.text.text = typed;
      await tester.pumpWidget(
        _app(
          PhoneNumberField(controller: controller, mobileOnly: mobileOnly),
          locale: locale,
          form: form,
        ),
      );
      final valid = form.currentState!.validate();
      await tester.pumpAndSettle();
      if (valid) return null;
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.contains(' ') || t == 'Required' || t == 'مطلوب')
          .toList();
      return texts.firstWhere(
        (t) => t.startsWith('Enter') || t == 'Required' || t.startsWith('أدخل') || t == 'مطلوب',
        orElse: () => '',
      );
    }

    testWidgets('is silent for a valid number', (tester) async {
      expect(await validate(tester, typed: '050 123 4567'), isNull);
      expect(
        await validate(tester, typed: '01001234567', country: 'EG', mobileOnly: true),
        isNull,
      );
    });

    testWidgets('asks for a number when there is none', (tester) async {
      expect(await validate(tester, typed: ''), 'Required');
      expect(await validate(tester, typed: '', locale: 'ar'), 'مطلوب');
    });

    testWidgets('names the country the number is checked against', (tester) async {
      expect(
        await validate(tester, typed: '12345'),
        'Enter a valid phone number for United Arab Emirates',
      );
      expect(
        await validate(tester, typed: '12345', mobileOnly: true, country: 'EG'),
        'Enter a valid mobile number for Egypt',
      );
    });

    testWidgets('speaks Arabic in Arabic, with the country\'s Arabic name', (
      tester,
    ) async {
      expect(
        await validate(tester, typed: '12345', locale: 'ar', mobileOnly: true),
        'أدخل رقم جوال صحيحًا لدولة الإمارات العربية المتحدة',
      );
      expect(
        await validate(tester, typed: '12345', locale: 'ar', country: 'EG'),
        'أدخل رقم هاتف صحيحًا لدولة مصر',
      );
    });

    testWidgets('turns a landline down only where a mobile is needed', (
      tester,
    ) async {
      expect(
        await validate(tester, typed: '02 21234567', country: 'EG'),
        isNull,
      );
      expect(
        await validate(tester, typed: '02 21234567', country: 'EG', mobileOnly: true),
        'Enter a valid mobile number for Egypt',
      );
    });
  });

  testWidgets('a label sits over the field, 6 px above it', (tester) async {
    _phone(tester);
    final controller = _controller();
    await tester.pumpWidget(
      _app(PhoneNumberField(controller: controller, label: 'Mobile (WhatsApp)')),
    );
    await tester.pumpAndSettle();
    final label = tester.getRect(find.text('Mobile (WhatsApp)'));
    final field = tester.getRect(find.byType(TextField));
    expect(field.top - label.bottom, closeTo(6, 1));
  });

  testWidgets('the chip says what it is to a screen reader', (tester) async {
    _phone(tester);
    final controller = _controller();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(PhoneNumberField(controller: controller)));
    expect(
      find.bySemanticsLabel('Country code: United Arab Emirates +971'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
