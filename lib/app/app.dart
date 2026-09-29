import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_service.dart';
import '../core/store/store_controller.dart';
import '../core/widgets/offline_state.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/cart/presentation/cart_controller.dart';
import '../features/wishlist/presentation/wishlist_controller.dart';
import '../l10n/l10n.dart';
import 'notification_routes.dart';
import 'shell/back_swipe.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_controller.dart';

/// Root widget. Locale, theme (incl. font), and text direction are all driven by
/// the active store view, so a language switch rebuilds the whole tree. Also
/// listens for tapped notifications and deep-links to the matching route.
class HubApp extends ConsumerStatefulWidget {
  const HubApp({super.key});

  @override
  ConsumerState<HubApp> createState() => _HubAppState();
}

class _HubAppState extends ConsumerState<HubApp>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _openedSub;

  /// Lets the session-expiry notice reach the customer from wherever they are —
  /// an expired token surfaces on whatever screen happens to be querying.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openedSub = NotificationService.instance.onNotificationOpened.listen(
      _handleNotification,
    );
    // Replay a cold-start tap once the router is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = NotificationService.instance.takeInitialMessage();
      if (initial != null) _handleNotification(initial);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Real-time sync: on returning to the app, pull the server cart (and, when
    // signed in, the wishlist) so changes made on the website appear.
    if (state == AppLifecycleState.resumed) {
      ref.read(cartControllerProvider.notifier).refresh();
      if (ref.read(authControllerProvider).isAuthenticated) {
        ref.read(wishlistControllerProvider.notifier).refresh();
      }
    }
  }

  void _showSessionExpired() {
    // Read the string off the messenger's own context: it sits below
    // MaterialApp's Localizations, while this widget sits above it.
    final messengerContext = _messengerKey.currentContext;
    final messenger = _messengerKey.currentState;
    if (messengerContext == null || messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(messengerContext).sessionExpiredMessage,
          ),
        ),
      );
  }

  void _handleNotification(Map<String, dynamic> data) {
    final route = notificationRoute(data);
    if (route != null) ref.read(routerProvider).go(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(sessionExpiredSignalProvider, (previous, next) {
      if (previous == null || next <= previous) return;
      // Deferred to the next frame for two reasons: a launch-time expiry can
      // land before MaterialApp has mounted its ScaffoldMessenger, and showing
      // a SnackBar mid-build would throw.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showSessionExpired(),
      );
    });

    final store = ref.watch(storeControllerProvider);
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: store.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(store.activeLocale),
      darkTheme: AppTheme.dark(store.activeLocale),
      // Defaults to light (white) — the app no longer follows the OS dark mode
      // unless the user picks Black/System in Settings.
      themeMode: themeMode,
      // The back swipe is installed once, here, above the router's Navigator so
      // it reaches every route — including the screens that build a bare
      // Scaffold and so never had one (CL042-DEV11). The offline strip (Figma
      // S3) is app-wide for the same reason.
      builder: (context, child) => Directionality(
        textDirection: store.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: OfflineBannerHost(
          child: AppBackSwipe(
            router: router,
            navigatorKey: rootNavigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
