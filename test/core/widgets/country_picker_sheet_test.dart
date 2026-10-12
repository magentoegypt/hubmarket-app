import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/phone/phone_country.dart';
import 'package:hubmarket_app/core/widgets/country_picker_sheet.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';

/// A page with one button that opens the list and writes down the pick.
class _Harness extends StatefulWidget {
  const _Harness({required this.selected, required this.onClosed});

  final PhoneCountry selected;
  final void Function(PhoneCountry? picked) onClosed;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async => widget.onClosed(
          await showCountryPicker(context, selected: widget.selected),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Widget _app({
  required PhoneCountry selected,
  required void Function(PhoneCountry? picked) onClosed,
  String locale = 'en',
}) => MaterialApp(
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
  home: _Harness(selected: selected, onClosed: onClosed),
);

Future<void> _open(
  WidgetTester tester, {
  String locale = 'en',
  String selected = 'AE',
  void Function(PhoneCountry? picked)? onClosed,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      selected: phoneCountryByCode(selected)!,
      onClosed: onClosed ?? (_) {},
      locale: locale,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The names in the list, top to bottom, as the rows draw them.
List<String> _names(WidgetTester tester, String language) {
  final shown = [
    for (final country in kPhoneCountries)
      if (find.text(country.name(language)).evaluate().isNotEmpty)
        country.name(language),
  ];
  double y(String name) => tester.getTopLeft(find.text(name)).dy;
  return shown..sort((a, b) => y(a).compareTo(y(b)));
}

void main() {
  setUpAll(loadAppFonts);

  group('the sheet', () {
    testWidgets('opens with the title, the search box, the suggested countries '
        'and then all of them', (tester) async {
      await _open(tester);

      expect(find.text('Select country'), findsOneWidget);
      expect(find.text('Search country or code'), findsOneWidget);
      expect(find.text('SUGGESTED'), findsOneWidget);
      expect(find.text('ALL COUNTRIES'), findsOneWidget);
      // Suggested: the store's own, then the website's two.
      double y(String name) => tester.getTopLeft(find.text(name).first).dy;
      expect(y('United Arab Emirates'), lessThan(y('Egypt')));
      expect(y('Egypt'), lessThan(y('United States')));
      // Then the alphabet, without the three again.
      expect(find.text('Egypt'), findsOneWidget);
      expect(find.text('Afghanistan'), findsOneWidget);
      expect(y('Egypt'), lessThan(y('Afghanistan')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the calling codes left to right and marks the one '
        'selected', (tester) async {
      await _open(tester, selected: 'EG');
      expect(find.text('+971'), findsOneWidget);
      expect(find.text('+20'), findsOneWidget);
      final code = tester.widget<Text>(find.text('+20'));
      expect(code.textDirection, TextDirection.ltr);
      // A tick on the row of Egypt only.
      expect(find.byIcon(Icons.check), findsNothing);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Egypt'),
            matching: find.byType(InkWell),
          ),
          matching: find.byWidgetPredicate(
            (w) => w is Icon && w.size == 18 && w.color != null,
          ),
        ),
        findsWidgets,
      );
    });

    testWidgets('scrolls to a country far down the alphabet when it is the one '
        'selected', (tester) async {
      await _open(tester, selected: 'ZW');
      expect(find.text('Zimbabwe'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Zimbabwe')).dy, lessThan(844));
    });

    testWidgets('returns the country tapped', (tester) async {
      PhoneCountry? picked;
      var closed = false;
      await _open(
        tester,
        onClosed: (p) {
          picked = p;
          closed = true;
        },
      );
      // Built, but below the screen: only found when offstage rows count.
      await tester.ensureVisible(find.text('Saudi Arabia', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saudi Arabia'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(picked!.code, 'SA');
      expect(find.byType(CountryPickerSheet), findsNothing);
    });

    testWidgets('returns nothing when it is closed', (tester) async {
      PhoneCountry? picked = phoneCountryByCode('SA');
      var closed = false;
      await _open(
        tester,
        onClosed: (p) {
          picked = p;
          closed = true;
        },
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(picked, isNull);
    });
  });

  group('searching', () {
    Future<void> search(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    testWidgets('by name, in the language of the app', (tester) async {
      await _open(tester);
      await search(tester, 'egy');
      expect(find.text('Egypt'), findsOneWidget);
      expect(find.text('Afghanistan'), findsNothing);
      // The suggested block is only for the empty search.
      expect(find.text('SUGGESTED'), findsNothing);
    });

    testWidgets('by the name in the other language too', (tester) async {
      await _open(tester);
      await search(tester, 'مصر');
      expect(find.text('Egypt'), findsOneWidget);
    });

    testWidgets('by region code', (tester) async {
      await _open(tester);
      await search(tester, 'ae');
      // The region code first, then the names that only contain it.
      expect(find.text('United Arab Emirates'), findsOneWidget);
      expect(find.text('Israel'), findsOneWidget);
      expect(find.text('Afghanistan'), findsNothing);
      expect(
        tester.getTopLeft(find.text('United Arab Emirates')).dy,
        lessThan(tester.getTopLeft(find.text('Israel')).dy),
      );
    });

    testWidgets('by calling code, with or without the plus, first those that '
        'start with it', (tester) async {
      await _open(tester);
      await search(tester, '+20');
      expect(find.text('Egypt'), findsOneWidget);
      expect(find.text('United Arab Emirates'), findsNothing);

      await search(tester, '971');
      expect(find.text('United Arab Emirates'), findsOneWidget);
      expect(find.text('Egypt'), findsNothing);
    });

    testWidgets('names, first those that start with the text', (tester) async {
      await _open(tester);
      await search(tester, 'ind');
      // India, Indonesia start with it; others (Burundi? no) only contain it.
      final names = _names(tester, 'en');
      expect(names.first, 'India');
      expect(names, contains('Indonesia'));
    });

    testWidgets('an accent is no obstacle: "cote" finds Côte d\'Ivoire', (
      tester,
    ) async {
      await _open(tester);
      await search(tester, 'cote');
      expect(find.textContaining('Ivoire'), findsOneWidget);
    });

    testWidgets('with nothing matching says so', (tester) async {
      await _open(tester);
      await search(tester, 'zzzz');
      expect(find.text('No country matches your search'), findsOneWidget);
    });

    testWidgets('can be cleared with the cross, which brings the list back', (
      tester,
    ) async {
      await _open(tester);
      await search(tester, 'egy');
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('SUGGESTED'), findsOneWidget);
      expect(find.text('Afghanistan'), findsOneWidget);
    });
  });

  group('in Arabic', () {
    testWidgets('the names are Arabic, the page reads right to left and the '
        'codes stay Latin', (tester) async {
      await _open(tester, locale: 'ar');

      expect(find.text('اختر الدولة'), findsOneWidget);
      expect(find.text('الإمارات العربية المتحدة'), findsOneWidget);
      expect(find.text('مصر'), findsOneWidget);
      expect(find.text('مقترحة'.toUpperCase()), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('اختر الدولة'))),
        TextDirection.rtl,
      );
      expect(tester.widget<Text>(find.text('+971')).textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });

    testWidgets('searching by an Arabic name finds the country', (tester) async {
      await _open(tester, locale: 'ar');
      await tester.enterText(find.byType(TextField), 'السعودية');
      await tester.pumpAndSettle();
      expect(find.text('المملكة العربية السعودية'), findsOneWidget);
      expect(find.text('مصر'), findsNothing);
    });
  });

  group('the order of the alphabet', () {
    test('is by name in English, the accented letters filed as their base', () {
      final names = searchPhoneCountries('', language: 'en')
          .map((c) => c.nameEn)
          .toList();
      expect(names.first, 'Afghanistan');
      expect(names.indexOf('Åland Islands'), lessThan(names.indexOf('Albania')));
      expect(names.indexOf('Åland Islands'), greaterThan(names.indexOf('Afghanistan')));
      expect(names.last, 'Zimbabwe');
      expect(names, hasLength(kPhoneCountries.length));
    });

    test('is by name in Arabic, without the "al" and with the alef forms as '
        'one', () {
      final names = searchPhoneCountries('', language: 'ar')
          .map((c) => c.nameAr)
          .toList();
      // "الأردن" (Jordan) is filed under its alef, not under "ال": اردن comes
      // before افغانستان (ra before fa), and both before بحرين.
      final jordan = names.indexOf('الأردن');
      final afghanistan = names.indexOf('أفغانستان');
      final bahrain = names.indexOf('البحرين');
      expect(jordan, lessThan(afghanistan));
      expect(afghanistan, lessThan(bahrain));
    });

    test('phoneSortKey drops accents, Arabic vowel signs and the leading "al"', () {
      expect(phoneSortKey('Côte d\'Ivoire'), startsWith('cote'));
      expect(phoneSortKey('Curaçao'), 'curacao');
      expect(phoneSortKey('Türkiye'), 'turkiye');
      expect(phoneSortKey('São Tomé & Príncipe'), startsWith('sao tome'));
      expect(phoneSortKey('الإمارات'), phoneSortKey('الامارات'));
      expect(phoneSortKey('الإمارات'), phoneSortKey('امارات'));
      expect(phoneSortKey('عُمان'), phoneSortKey('عمان'));
    });
  });
}
