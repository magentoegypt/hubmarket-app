import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/app.dart';
import 'package:hubmarket_app/core/hubapp/hubapp_providers.dart';
import 'package:hubmarket_app/app/router.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/features/diagnostics/data/store_config_repository.dart';
import 'package:hubmarket_app/features/diagnostics/presentation/health_check_screen.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

const _config = StoreConfigData(
  storeCode: 'eg_en',
  storeName: 'UAE English',
  locale: 'en_US',
  currency: 'AED',
  baseUrl: 'https://hub-market.magento2.click/',
  baseMediaUrl: 'https://hub-market.magento2.click/media/',
);

Widget _harness(String locale) => ProviderScope(
  overrides: [
    localCacheProvider.overrideWithValue(FakeLocalCache()),
    localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
    storeConfigProvider.overrideWith((ref) async => _config),
    hubAppOverride(const HubAppState.unavailable()),
    // Boot the app directly on the diagnostics screen (the real router
    // starts at /splash).
    routerProvider.overrideWithValue(
      GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HealthCheckScreen()),
        ],
      ),
    ),
  ],
  child: const HubApp(),
);

void main() {
  testWidgets('renders storeConfig in English / LTR', (tester) async {
    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    expect(find.text('Store code'), findsOneWidget);
    expect(find.text('eg_en'), findsWidgets);

    final direction = Directionality.of(
      tester.element(find.text('Store code')),
    );
    expect(direction, TextDirection.ltr);
  });

  testWidgets('renders storeConfig in Arabic / RTL', (tester) async {
    await tester.pumpWidget(_harness('ar'));
    await tester.pumpAndSettle();

    // fieldStoreCode in Arabic.
    expect(find.text('رمز المتجر'), findsOneWidget);

    final direction = Directionality.of(
      tester.element(find.text('رمز المتجر')),
    );
    expect(direction, TextDirection.rtl);
  });
}
