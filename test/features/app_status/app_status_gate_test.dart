import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/app_status/presentation/app_status_gate.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';

HmAppConfig _config({
  HmMaintenance maintenance = const HmMaintenance(),
  String? minVersion,
  String? message,
}) => HmAppConfig(
  storeCode: 'en',
  maintenance: maintenance,
  versions: [
    HmVersionPolicy(
      platform: HmPlatform.android,
      minVersion: minVersion,
      storeUrl: 'https://play.google.com/store/apps/details?id=hub.market',
      message: message,
    ),
  ],
);

Widget _harness(
  HubAppState state, {
  String locale = 'en',
  String? appVersion = '1.0.0',
  GlobalKey? boundary,
}) {
  return ProviderScope(
    overrides: [
      hubAppOverride(state),
      appSemverProvider.overrideWith((ref) async => appVersion),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(
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
        builder: (context, child) => AppStatusGate(child: child!),
        home: const Scaffold(body: Center(child: Text('Home'))),
      ),
    ),
  );
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('open while the settings are unknown or allow it', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const HubAppState.unavailable()));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);

    await tester.pumpWidget(
      _harness(HubAppState.available(_config(minVersion: '1.0.0'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Time to update'), findsNothing);
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('maintenance holds every route ($locale)', (tester) async {
      await _phone(tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _harness(
          HubAppState.available(
            _config(
              maintenance: HmMaintenance(
                enabled: true,
                message: locale == 'ar'
                    ? 'نجري جردًا للمخزون، نعود خلال نصف ساعة.'
                    : 'We’re doing a stock count — back within half an hour.',
                retryAfterMinutes: 30,
              ),
            ),
          ),
          locale: locale,
          boundary: boundary,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsNothing);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MaintenanceScreen)),
      );
      expect(find.text(l10n.maintenanceTitle), findsOneWidget);
      expect(find.text(l10n.maintenanceRetryAfter(30)), findsOneWidget);
      await captureScreen(tester, boundary, 'app_status_maintenance_$locale');

      await tester.tap(find.text(l10n.offlineTryAgain));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaintenanceScreen)),
      );
      expect(
        (container.read(hubAppProvider.notifier) as FakeHubAppController)
            .refreshes,
        1,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a build below min_version must update ($locale)', (
      tester,
    ) async {
      await _phone(tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _harness(
          HubAppState.available(_config(minVersion: '1.2.0')),
          locale: locale,
          appVersion: '1.0.0',
          boundary: boundary,
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(UpdateRequiredScreen)),
      );
      expect(find.text('Home'), findsNothing);
      expect(find.text(l10n.updateRequiredTitle), findsOneWidget);
      expect(find.text(l10n.updateRequiredBody), findsOneWidget);
      expect(find.text(l10n.updateRequiredAction), findsOneWidget);
      await captureScreen(tester, boundary, 'app_status_update_$locale');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the admin message replaces the default copy', (tester) async {
    await tester.pumpWidget(
      _harness(
        HubAppState.available(
          _config(minVersion: '2.0.0', message: 'Update for the new checkout.'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Update for the new checkout.'), findsOneWidget);
  });

  testWidgets('an unreadable app version never locks the app', (tester) async {
    await tester.pumpWidget(
      _harness(
        HubAppState.available(_config(minVersion: '9.0.0')),
        appVersion: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}
