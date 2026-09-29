import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/font_licenses.dart';
import 'core/notifications/notification_service.dart';
import 'core/storage/local_cache.dart';
import 'core/storage/locale_prefs.dart';
import 'core/store/store_controller.dart';
import 'features/notifications/data/device_token_repository.dart';
import 'features/notifications/data/notification_inbox.dart';
import 'features/notifications/presentation/notification_settings_controller.dart';

/// Shared startup for every flavor entrypoint: init storage, build the provider
/// container with concrete storage overrides, kick off store resolution, and run
/// the app. The flavor itself comes from `--dart-define-from-file`.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The OFL texts of the bundled fonts (DM Sans, Tajawal, Playfair Display).
  registerFontLicenses();

  // Locale date symbols (so Arabic order dates render Arabic month names).
  await initializeDateFormatting();

  await Hive.initFlutter();
  final cache = await LocalCache.open();
  final prefs = await SharedPreferences.getInstance();

  // Local notification inbox — loads persisted items and starts capturing
  // incoming pushes immediately (independent of the feed screen).
  await NotificationInbox.instance.init(cache);

  final container = ProviderContainer(
    overrides: <Override>[
      localCacheProvider.overrideWithValue(cache),
      localePrefsProvider.overrideWithValue(LocalePrefs(prefs)),
    ],
  );

  // Resolve store views in the background; UI paints with provisional/cached
  // mapping first and updates when this completes.
  unawaited(container.read(storeControllerProvider.notifier).loadStores());

  // Push plumbing. Local notifications always; FCM only when a Firebase config
  // is bundled — none is yet, so it stays off and never blocks startup. Apply
  // the saved topic subscriptions once FCM is up.
  unawaited(
    NotificationService.instance.init().then((_) {
      applyNotificationTopics(cache);
      // Register this device's FCM token with the backend (launch heartbeat)
      // and on every token rotation. No-op until FCM is configured and the
      // backend has a device-token endpoint (BackendCapabilities).
      container.read(deviceTokenSyncProvider).register();
      NotificationService.instance.onTokenRefresh.listen(
        (_) => container.read(deviceTokenSyncProvider).register(),
      );
    }),
  );

  // Re-register the token when the store/language changes, so future pushes
  // localise to the new view. (Wired here, not in the core store controller,
  // to keep core free of feature dependencies.)
  container.listen<String>(
    storeControllerProvider.select((s) => s.activeLocale),
    (previous, next) {
      if (previous != null && previous != next) {
        container.read(deviceTokenSyncProvider).register();
      }
    },
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const HubApp()),
  );
}
