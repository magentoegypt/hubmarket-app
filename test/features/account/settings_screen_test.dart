import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/features/account/presentation/screens/settings_screen.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

Future<void> _pump(
  WidgetTester tester, {
  String locale = 'en',
  bool push = false,
  bool developerTools = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        pushNotificationsAvailableProvider.overrideWithValue(push),
        developerToolsProvider.overrideWithValue(developerTools),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the language toggle (EN)', (tester) async {
    await _pump(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
  });

  testWidgets('the customer build has no theme switch or connection test', (
    tester,
  ) async {
    await _pump(tester);
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.byType(SegmentedButton<ThemeMode>), findsNothing);
    expect(find.text(en.settingsConnectionTest), findsNothing);
    // Customers keep the language switch.
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
  });

  testWidgets('dev and staging builds add both developer tools', (
    tester,
  ) async {
    await _pump(tester, developerTools: true);
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    expect(find.text(en.settingsConnectionTest), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
  });

  testWidgets('no push switch while push is unavailable', (tester) async {
    await _pump(tester);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('the push switch appears once FCM is available', (tester) async {
    await _pump(tester, push: true);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('renders translated + RTL in Arabic', (tester) async {
    await _pump(tester, locale: 'ar');
    expect(find.text('الإعدادات'), findsOneWidget); // settingsTitle
    expect(
      Directionality.of(tester.element(find.text('الإعدادات'))),
      TextDirection.rtl,
    );
  });
}
