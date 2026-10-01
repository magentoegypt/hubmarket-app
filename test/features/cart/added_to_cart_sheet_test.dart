import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/cart/presentation/widgets/added_to_cart_sheet.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_card.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../checkout/checkout_harness.dart';

/// An add lands the cart of Figma 18b (4 items, AED 543), whatever was added.
class _CartRepository extends CheckoutCartRepository {
  @override
  Future<Cart> addProducts(
    String cartId,
    List<Map<String, dynamic>> items, {
    bool throwOnUserError = true,
  }) async => checkoutCart(cartId);
}

/// The PDP's product: simple, with two linked products.
class _DetailRepository extends FakeCatalogRepository {
  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async =>
      const ProductDetail(
        sku: 'DRESS',
        name: 'Floral Print Corset-Waist Tie Dress',
        urlKey: 'floral-dress',
        regularPrice: Money(amount: 50, currency: 'AED'),
        finalPrice: Money(amount: 50, currency: 'AED'),
        alsoLike: _related,
      );
}

const _related = <Product>[
  Product(
    sku: 'TOP',
    name: 'Short Square-Neck T-Shirt',
    urlKey: 'square-neck-t-shirt',
    finalPrice: Money(amount: 43, currency: 'AED'),
  ),
  Product(
    sku: 'SHORTS',
    name: 'Short Shorts with Flap Pocket',
    urlKey: 'flap-pocket-shorts',
    finalPrice: Money(amount: 13, currency: 'AED'),
  ),
  Product(
    sku: 'POLO',
    name: 'Polo Shirt',
    urlKey: 'polo-shirt',
    finalPrice: Money(amount: 13, currency: 'AED'),
  ),
];

const _item = AddedItem(
  name: 'Floral Print Corset-Waist Tie Dress',
  quantity: 1,
  unitPrice: Money(amount: 50, currency: 'AED'),
  options: ['Size: M', 'Colour: Beige floral'],
);

/// [home] in a router that also has the places the sheet leads to.
Widget _harness(
  Widget home, {
  String locale = 'en',
  double? freeShippingOver,
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, __) => home),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) =>
            Scaffold(body: Text('product ${state.pathParameters['urlKey']}')),
      ),
      for (final path in [
        '/cart',
        '/checkout',
        '/home',
        '/categories',
        '/wishlist',
        '/account',
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('route $path')),
        ),
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
      localCacheProvider.overrideWithValue(
        FakeLocalCache()..writeString('guest_cart_id', 'guest-1'),
      ),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      cartRepositoryProvider.overrideWithValue(_CartRepository()),
      catalogRepositoryProvider.overrideWithValue(_DetailRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      freeShippingThresholdProvider.overrideWith(
        (ref) async => freeShippingOver,
      ),
      // The product page asks HubApp for its seller; Build 1 here.
      hubAppOverride(const HubAppState.unavailable()),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// A page with a button that opens the sheet, as an add-to-cart would.
Widget _opener({
  List<Product> recommendations = const [],
  AddedItem item = _item,
}) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => AddedToCartSheet.show(
          context,
          item: item,
          recommendations: recommendations,
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows what was added, the cart subtotal and the linked '
      'products', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_harness(_opener(recommendations: _related)));
    await tester.pumpAndSettle();
    await _open(tester);

    expect(find.text('Added to cart'), findsOneWidget);
    expect(find.text('Floral Print Corset-Waist Tie Dress'), findsOneWidget);
    expect(find.text('Size: M · Colour: Beige floral · Qty 1'), findsOneWidget);
    expect(find.text('AED 50'), findsOneWidget);
    expect(find.text('Cart subtotal (4 items)'), findsOneWidget);
    expect(find.text('AED 543'), findsOneWidget);
    expect(find.text('You might also like'), findsOneWidget);
    expect(find.text('Polo Shirt'), findsOneWidget);
    // No threshold published → no free-shipping bar.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('"Only 3 left in size M" shows in red when the store says so', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _harness(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AddedToCartSheet.show(
                context,
                item: const AddedItem(
                  name: 'Floral Print Corset-Waist Tie Dress',
                  quantity: 1,
                  unitPrice: Money(amount: 50, currency: 'AED'),
                  options: ['Size: M'],
                  onlyLeft: 3,
                  onlyLeftOption: 'size M',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _open(tester);

    final line = find.text('Only 3 left in size M');
    expect(line, findsOneWidget);
    expect(tester.widget<Text>(line).style!.color, AppColors.danger);
    // Without the count, no line.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_harness(_opener()));
    await tester.pumpAndSettle();
    await _open(tester);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets('from the product page the sheet carries what is left of the '
      'chosen variant', (tester) async {
    const product = ProductDetail(
      sku: 'DRESS',
      name: 'Dress',
      urlKey: 'dress',
      options: [
        ConfigurableOption(
          attributeCode: 'size',
          label: 'Size',
          values: [SwatchValue(valueIndex: 1, label: 'M')],
        ),
      ],
      variants: [
        ProductVariant(sku: 'DRESS-M', attributes: {'size': 1}, onlyLeft: 3),
      ],
    );
    final item = AddedItem.fromDetail(product, {'size': 1}, 2);
    expect(item.onlyLeft, 3);
    expect(item.onlyLeftOption, 'size M');
    expect(item.options, ['Size: M']);
    // A choice not made yet: nothing is claimed.
    expect(AddedItem.fromDetail(product, {}, 1).onlyLeft, isNull);
  });

  testWidgets('without linked products the row is left out', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_harness(_opener()));
    await tester.pumpAndSettle();
    await _open(tester);

    expect(find.text('Added to cart'), findsOneWidget);
    expect(find.text('You might also like'), findsNothing);
  });

  testWidgets('counts down to the store threshold when it publishes one', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_harness(_opener(), freeShippingOver: 600));
    await tester.pumpAndSettle();
    await _open(tester);

    expect(find.text('Add AED 57 more for free delivery'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('View cart, Checkout and a linked product close the sheet and '
      'go on', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_harness(_opener(recommendations: _related)));
    await tester.pumpAndSettle();

    await _open(tester);
    await tapText(tester, 'View cart');
    expect(find.text('route /cart'), findsOneWidget);
    expect(find.text('Added to cart'), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await _open(tester);
    await tapText(tester, 'Checkout');
    expect(find.text('route /checkout'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await _open(tester);
    await tapText(tester, 'Polo Shirt');
    expect(find.text('product polo-shirt'), findsOneWidget);
  });

  testWidgets('adding from the product page opens the sheet with its linked '
      'products', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(const ProductDetailScreen(urlKey: 'floral-dress')),
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Add to cart · AED 50');

    expect(find.text('Added to cart'), findsOneWidget);
    expect(find.text('Qty 1'), findsOneWidget);
    expect(find.text('You might also like'), findsOneWidget);
    expect(find.text('Short Shorts with Flap Pocket'), findsWidgets);
  });

  testWidgets('adding from a product card opens the sheet', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _harness(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 320,
              child: ProductCard(product: _related.last),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add to Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Added to cart'), findsOneWidget);
    expect(find.text('Qty 1'), findsOneWidget);
    expect(find.text('Cart subtotal (4 items)'), findsOneWidget);
    // A listing has no linked products to offer.
    expect(find.text('You might also like'), findsNothing);
  });

  group('renders (Figma 14c)', () {
    setUpAll(loadCheckoutFonts);

    for (final locale in ['en', 'ar']) {
      testWidgets(locale, (tester) async {
        _phone(tester);
        final key = GlobalKey();
        // The frame's add: size M, three left, the store counting down to its
        // free-shipping line.
        await tester.pumpWidget(
          _harness(
            _opener(
              recommendations: _related,
              item: const AddedItem(
                name: 'Floral Print Corset-Waist Tie Dress',
                quantity: 1,
                unitPrice: Money(amount: 50, currency: 'AED'),
                options: ['Size: M', 'Colour: Beige floral'],
                onlyLeft: 3,
                onlyLeftOption: 'size M',
              ),
            ),
            locale: locale,
            freeShippingOver: 600,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await _open(tester);
        await capture(tester, key, 'added_to_cart_$locale');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
