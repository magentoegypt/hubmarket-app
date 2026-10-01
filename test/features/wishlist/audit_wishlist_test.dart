import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/hub_top_bar.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/features/wishlist/domain/wishlist_entry.dart';
import 'package:hubmarket_app/features/wishlist/presentation/screens/wishlist_screen.dart';

import '../../support/audit_pump.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';

/// Renders Figma 25 "Wishlist" (22:1513 / 53:2200) in English and Arabic to
/// build/test_screens/audit_25_wishlist_{en,ar}.png and checks what the header
/// and the summary line offer.
class _Saved extends FakeWishlistRepository {
  _Saved(List<Product> products)
    : _data = WishlistData(
        id: 'wl-1',
        entries: [
          for (final p in products)
            WishlistEntry(id: 'item-${p.sku}', product: p),
        ],
      );

  WishlistData _data;

  @override
  Future<WishlistData?> fetchWishlist() async => _data;

  @override
  Future<WishlistData> removeItems(
    String wishlistId,
    List<String> itemIds,
  ) async => _data = WishlistData(
    id: wishlistId,
    entries: _data.entries.where((e) => !itemIds.contains(e.id)).toList(),
  );
}

Product _product(
  String sku,
  String name,
  String store,
  double rating,
  int reviews,
  double price, {
  double? was,
  bool sellerKnown = true,
}) => Product(
  sku: sku,
  name: name,
  urlKey: sku,
  sellerName: store,
  sellerCode: store.toLowerCase().replaceAll(' ', ''),
  sellerKnown: sellerKnown,
  ratingSummary: rating * 20,
  reviewCount: reviews,
  regularPrice: Money(amount: was ?? price, currency: 'AED'),
  finalPrice: Money(amount: price, currency: 'AED'),
);

List<Product> _products(String locale, {bool sellerKnown = true}) {
  final ar = locale == 'ar';
  return [
    _product('sofa', ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed', 'MIA CO', 4.6, 18, 425, was: 500, sellerKnown: sellerKnown),
    _product('dress', ar ? 'فستان صدر طباعة الأزهار رباط مشد خصر' : 'Floral Print Corset-Waist Tie Dress', 'loly store', 4.3, 27, 50, sellerKnown: sellerKnown),
    _product('chair', ar ? 'كرسي هزاز عنابي' : 'Burgundy Rocking Chair', 'MIA CO', 4.7, 21, 180, sellerKnown: sellerKnown),
    _product('milk', ar ? 'حليب كامل الدسم جهينة 1 لتر' : 'Juhayna Full Cream Milk 1 L', 'walmart', 4.7, 96, 35, sellerKnown: sellerKnown),
    _product('polo', ar ? 'قميص بولو' : 'Polo Shirt', 'loly store', 4.5, 33, 13, sellerKnown: sellerKnown),
    _product('desk', ar ? 'مكتب مدير عصري 160 سم' : 'Modern Executive Desk 160 cm', 'MIA CO', 4.5, 7, 350, sellerKnown: sellerKnown),
  ];
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('25 Wishlist ($locale)', (tester) async {
      final key = GlobalKey();
      await pumpAudit(
        tester,
        locale: locale,
        boundary: key,
        pushed: false,
        screen: const WishlistScreen(),
        wishlist: _Saved(_products(locale)),
      );
      await captureScreen(tester, key, 'audit_25_wishlist_$locale');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('25 Wishlist: the summary and the header', (tester) async {
    await pumpAudit(
      tester,
      pushed: false,
      screen: const WishlistScreen(),
      wishlist: _Saved(_products('en')),
    );
    expect(
      find.descendant(
        of: find.byType(HubTopBar),
        matching: find.text('Wishlist'),
      ),
      findsOneWidget,
    );
    // Three sellers: MIA CO, loly store, walmart.
    expect(find.text('6 saved items · 3 stores'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.text('Add all to bag'), findsOneWidget);
    // Nothing behind these two: no price history, no price alerts.
    expect(find.text('Notify on price drops'), findsNothing);
    expect(find.text('PRICE DROP'), findsNothing);
  });

  testWidgets('25 Wishlist: no store count while sellers are unknown', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      pushed: false,
      screen: const WishlistScreen(),
      wishlist: _Saved(_products('en', sellerKnown: false)),
    );
    expect(find.text('6 saved items'), findsOneWidget);
  });

  testWidgets('25 Wishlist: empty and signed out', (tester) async {
    await pumpAudit(
      tester,
      pushed: false,
      screen: const WishlistScreen(),
      wishlist: _Saved(const []),
    );
    expect(find.text('Your wishlist is empty'), findsOneWidget);
    expect(find.byTooltip('Share'), findsNothing);

    await pumpAudit(
      tester,
      pushed: false,
      signedIn: false,
      screen: const WishlistScreen(),
    );
    expect(find.text('Save your favourites'), findsOneWidget);
  });
}
