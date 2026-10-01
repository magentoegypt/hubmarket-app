import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
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

/// Captures the store-listing screenshots (App Store and Google Play) against
/// the LIVE backend, in the language set by SHOT_LOCALE.
///
/// This mirrors bootstrap() with two deliberate differences:
///   * NotificationService.init() is NOT called, so iOS never raises the
///     "would like to send you notifications" system alert over the shots.
///   * Navigation is driven through routerProvider rather than deep links.
///     hubmarket:// links do not route on iOS (no FlutterDeepLinkingEnabled, no
///     openURL handler), which is why the earlier simctl-based driver produced
///     eight identical screenshots of the welcome screen.
///
/// Run via tool/ios_screenshots.sh (CI, macOS) or tool/android_screenshots.sh
/// (a phone or emulator), not `flutter test`. The shot list and what to
/// replace once the store has its real catalogue: docs/release/screenshots.md.
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
    // On Android the Flutter surface has to be converted to an image before
    // takeScreenshot can read it; iOS captures without it.
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    // pumpAndSettle() would time out: the loading skeletons shimmer and the
    // home hero auto-advances, so the tree never goes quiet. Pump on a clock
    // instead and give the live backend room to answer.
    Future<void> settle(int seconds) async {
      for (var i = 0; i < seconds * 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    final router = container.read(routerProvider);

    // Says which network images have painted when a shot is taken, and which
    // are still loading (with the URL they asked for): a blank photo in a
    // capture is then one line in the log, not a guess.
    void logImages(String name) {
      final images = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .toList();
      final pending = <String>[
        for (final w in images)
          if (find
              .descendant(of: find.byWidget(w), matching: find.byType(RawImage))
              .evaluate()
              .isEmpty)
            w.imageUrl,
      ];
      // ignore: avoid_print
      print(
        'IMAGES $name: ${images.length - pending.length} painted, '
        '${pending.length} pending${pending.isEmpty ? '' : ' ${pending.join(' ')}'}',
      );
    }

    Future<void> shot(
      String name,
      String route, {
      int wait = 8,
      Object? extra,
    }) async {
      router.go(route, extra: extra);
      await settle(wait);
      logImages(name);
      await binding.takeScreenshot('$locale-$name');
    }

    // Let splash finish its own bootstrap navigation before we take over,
    // otherwise it lands on /welcome after our first go().
    await settle(25);

    // Ordered as they should appear on the product page — Apple shows the
    // first three on the install sheet. Wishlist, cart and account are left
    // out on purpose: a fresh install has nothing in them, so they would only
    // show empty states.
    //
    // The data-dependent routes use the live catalogue of 1 Oct 2026, picked
    // for how well it is photographed (the rest of it is test data, see
    // docs/release/screenshots.md): the Men's Clothing category (uid MTQy,
    // "ملابس رجالية" in Arabic), one in-stock product with three gallery
    // images ("Square-Neck Dress with Lapel"), the store "loly" and a search
    // for "samsung". The category must be one of the menu tree's: the listing
    // takes its title and sub-categories from it, so a category outside the
    // menu (Shoes, Bags) is captured with the generic title "Categories". The
    // category, product and search shots wait longer: the live server's own
    // answers are slow there. Point them at other content once the client's
    // catalogue is in.
    const category = '/category/MTQy';
    const product = '/product/dress-code-2156';
    const store = '/store/loly';
    const searchTerm = 'samsung';

    await shot('01-home', '/home', wait: 10);
    await shot('02-brands', '/brands', wait: 14);
    await shot('03-category', category, wait: 20);
    await shot('04-product', product, wait: 22);
    await shot('05-stores', '/stores', wait: 12);
    await shot('06-store', store, wait: 12);
    await shot('07-search', '/search', wait: 24, extra: searchTerm);
    await shot('08-categories', '/categories', wait: 8);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
