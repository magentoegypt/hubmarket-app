import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hubmarket_app/app/app.dart';
import 'package:hubmarket_app/app/router.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';

/// Captures App Store product-page screenshots against the LIVE backend.
///
/// This mirrors bootstrap() with two deliberate differences:
///   * NotificationService.init() is NOT called, so iOS never raises the
///     "would like to send you notifications" system alert over the shots.
///   * Navigation is driven through routerProvider rather than deep links.
///     hubmarket:// links do not route on iOS (no FlutterDeepLinkingEnabled, no
///     openURL handler), which is why the earlier simctl-based driver produced
///     eight identical screenshots of the welcome screen.
///
/// Run via tool/ios_screenshots.sh, not `flutter test`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Set by tool/ios_screenshots.sh so the EN and AR sets don't collide.
  const locale = String.fromEnvironment('SHOT_LOCALE', defaultValue: 'en');

  testWidgets('capture App Store screenshots', (tester) async {
    await initializeDateFormatting();
    await Hive.initFlutter();
    final cache = await LocalCache.open();
    final prefs = await SharedPreferences.getInstance();
    await NotificationInbox.instance.init(cache);
    final appVersion = await readAppSemver();

    final container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(AppConfig.forVersion(appVersion)),
        localCacheProvider.overrideWithValue(cache),
        localePrefsProvider.overrideWithValue(LocalePrefs(prefs)),
      ],
    );
    unawaited(container.read(storeControllerProvider.notifier).loadStores());

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const HubApp()),
    );

    // pumpAndSettle() would time out: the loading skeletons shimmer and the
    // home hero auto-advances, so the tree never goes quiet. Pump on a clock
    // instead and give the live backend room to answer.
    Future<void> settle(int seconds) async {
      for (var i = 0; i < seconds * 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    final router = container.read(routerProvider);

    Future<void> shot(String name, String route, {int wait = 8}) async {
      router.go(route);
      await settle(wait);
      await binding.takeScreenshot('$locale-$name');
    }

    // Let splash finish its own bootstrap navigation before we take over,
    // otherwise it lands on /welcome after our first go().
    await settle(25);

    // Ordered as they should appear on the product page — Apple shows the
    // first three on the install sheet.
    await shot('01-home', '/home', wait: 10);
    // Live Hub Market data (checked 30 Sep 2026): the Fashion category (uid
    // MTQw, "أزياء" in Arabic) and one of its in-stock simple products,
    // "Square-Neck Dress with Lapel", which has three gallery images.
    await shot('02-category', '/category/MTQw', wait: 12);
    await shot('03-product', '/product/dress-code-2156', wait: 12);
    await shot('04-categories', '/categories', wait: 8);
    await shot('05-brands', '/brands', wait: 10);
    await shot('06-wishlist', '/wishlist', wait: 6);
    await shot('07-cart', '/cart', wait: 6);
    await shot('08-account', '/account', wait: 6);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
