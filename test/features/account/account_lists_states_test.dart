import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/offline_state.dart';
import 'package:hubmarket_app/core/widgets/shimmer.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/my_reviews_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/orders_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/review_pages.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';

/// Orders that can't be fetched: the request never reached the store.
class _OfflineOrders extends FakeAccountRepository {
  int loads = 0;

  @override
  Future<OrderPage> fetchOrders({int pageSize = 10, int currentPage = 1}) async {
    loads++;
    throw const Failure(FailureKind.network);
  }
}

/// Orders whose first page hasn't answered yet.
class _SlowOrders extends FakeAccountRepository {
  final pending = Completer<OrderPage>();

  @override
  Future<OrderPage> fetchOrders({int pageSize = 10, int currentPage = 1}) =>
      pending.future;
}

/// My reviews while offline.
class _OfflineReviews extends FakeReviewsRepository {
  @override
  Future<CustomerReviewsPage> fetchCustomerReviews({
    int pageSize = 20,
    int currentPage = 1,
  }) async => throw const Failure(FailureKind.network);
}

Widget _app({
  required String locale,
  required Widget screen,
  FakeAccountRepository? account,
  ReviewsRepository? reviews,
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final p in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.signIn,
        AppRoutes.orderDetail,
        AppRoutes.orderTracking,
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  final app = MaterialApp.router(
    routerConfig: router,
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
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore('persisted'),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      accountRepositoryProvider.overrideWithValue(
        account ?? FakeAccountRepository(),
      ),
      reviewsRepositoryProvider.overrideWithValue(
        reviews ?? FakeReviewsRepository(),
      ),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
      hubAppOverride(const HubAppState.unavailable()),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('My orders offline: the S3 page ($locale)', (tester) async {
      _phone(tester);
      final account = _OfflineOrders();
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          locale: locale,
          screen: const OrdersScreen(),
          account: account,
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'orders_offline_$locale');

      expect(find.byType(OfflineState), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsNothing);
      final before = account.loads;
      await tester.tap(find.text(l10n.offlineTryAgain));
      await tester.pumpAndSettle();
      expect(account.loads, before + 1);
    });

    testWidgets('My orders first load: order-card skeletons ($locale)', (
      tester,
    ) async {
      _phone(tester);
      final account = _SlowOrders();
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          locale: locale,
          screen: const OrdersScreen(),
          account: account,
          boundary: key,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await captureScreen(tester, key, 'orders_loading_$locale');

      expect(find.byType(Shimmer), findsNWidgets(3));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      account.pending.complete(OrderPage.empty);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Shimmer), findsNothing);
      expect(find.text(l10n.ordersEmpty), findsOneWidget);
    });

    testWidgets('My reviews offline: the S3 page ($locale)', (tester) async {
      _phone(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          locale: locale,
          screen: const MyReviewsScreen(),
          reviews: _OfflineReviews(),
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'my_reviews_offline_$locale');

      expect(find.byType(OfflineState), findsOneWidget);
      expect(find.text(l10n.offlineTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
