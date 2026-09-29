import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

Future<void> _pump(WidgetTester tester, String locale) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localCacheProvider.overrideWithValue(FakeLocalCache())],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const NotificationSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the promotions toggle in English (LTR)', (tester) async {
    await _pump(tester, 'en');
    expect(find.text('Promotions & offers'), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.value, isTrue); // default on
  });

  testWidgets('renders translated + RTL in Arabic', (tester) async {
    await _pump(tester, 'ar');
    expect(find.text('العروض والتخفيضات'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(SwitchListTile))),
      TextDirection.rtl,
    );
  });

  testWidgets('toggling the switch flips the value', (tester) async {
    await _pump(tester, 'en');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.value, isFalse);
  });
}
