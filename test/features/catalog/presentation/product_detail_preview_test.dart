import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/product_preview.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_skeletons.dart';
import 'package:hubmarket_app/features/checkout/payments/tabby_promo.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

/// A repository whose PDP query never resolves, so the screen is pinned in its
/// loading state — the frame the client's recording was complaining about.
class _StuckCatalogRepository extends FakeCatalogRepository {
  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) =>
      Completer<ProductDetail?>().future;
}

const _preview = ProductPreview(
  urlKey: 'coco-mademoiselle',
  imageUrl: 'https://hub-market.magento2.click/media/catalog/product/cache/abc/c/o/coco.jpg',
  name: 'Coco Mademoiselle EDP',
  brand: 'Chanel',
  finalPrice: Money(amount: 420, currency: 'AED'),
);

Widget _harness({ProductPreview? preview, String locale = 'en'}) {
  final router = GoRouter(
    initialLocation: '/product/coco-mademoiselle',
    routes: [
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) => ProductDetailScreen(
          urlKey: state.pathParameters['urlKey']!,
          preview: preview,
        ),
      ),
      for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(_StuckCatalogRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      tabbyConfigProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

void main() {
  testWidgets('while loading, a listing tap paints what the listing knew', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(preview: _preview));
    await tester.pump();

    // The real name, brand and price — in the loading state, not after it.
    expect(find.text('Coco Mademoiselle EDP'), findsOneWidget);
    expect(find.text('Chanel'), findsOneWidget);
    expect(find.textContaining('420'), findsOneWidget);
    // And never the bare spinner this replaced.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a deep link has no preview and still renders a skeleton', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.byType(ProductDetailSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Nothing invented: no product name is shown when none is known.
    expect(find.text('Coco Mademoiselle EDP'), findsNothing);
  });

  testWidgets('the preview skeleton lays out in Arabic / RTL', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(preview: _preview, locale: 'ar'));
    await tester.pump();

    expect(find.byType(ProductDetailSkeleton), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(ProductDetailSkeleton))),
      TextDirection.rtl,
    );
  });
}
