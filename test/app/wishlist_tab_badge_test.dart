import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/shell/hub_bottom_nav.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/wishlist/domain/wishlist_entry.dart';
import 'package:hubmarket_app/features/wishlist/presentation/wishlist_controller.dart';

import '../support/audit_pump.dart';
import '../support/fakes.dart';
import '../support/fonts.dart';

// QA TC101: "when add product to wishlist no counter show on icon". The Wishlist
// tab shows how many products are saved, as the Cart tab shows its items and as
// the website's header heart now does (orange disc, hidden at zero, "99+" past
// 99). The count is read from the wishlist the app already holds.

WishlistEntry _saved(int n) => WishlistEntry(
  id: 'item-$n',
  product: Product(sku: 'sku$n', name: 'Product $n', urlKey: 'p$n'),
);

List<WishlistEntry> _entries(int count) => [
  for (var i = 1; i <= count; i++) _saved(i),
];

/// The badge text(s) sitting on a tab of the bar: the digits drawn inside it.
Finder _badgeOn(String tabLabel) => find.descendant(
  of: find.ancestor(of: find.text(tabLabel), matching: find.byType(InkWell)),
  matching: find.byWidgetPredicate(
    (w) => w is Text && RegExp(r'^\d+\+?$').hasMatch(w.data ?? ''),
  ),
);

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  FakeWishlistRepository? wishlist,
  bool signedIn = true,
  String locale = 'en',
  GlobalKey? boundary,
}) => pumpAudit(
  tester,
  locale: locale,
  signedIn: signedIn,
  wishlist: wishlist,
  pushed: false,
  boundary: boundary,
  screen: const Scaffold(
    body: SizedBox.expand(),
    bottomNavigationBar: HubBottomNav(current: AppTab.home),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a signed-in shopper sees how many products are saved, on the '
      'Wishlist tab only', (tester) async {
    await _mount(tester, wishlist: FakeWishlistRepository(entries: _entries(3)));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(_badgeOn('Wishlist')).data, '3');
    // The cart is empty: its tab has no badge.
    expect(_badgeOn('Cart'), findsNothing);
    expect(_badgeOn('Home'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the badge is the cart\'s: an orange disc with white text', (
    tester,
  ) async {
    await _mount(tester, wishlist: FakeWishlistRepository(entries: _entries(2)));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(_badgeOn('Wishlist'));
    expect(text.style!.color, Colors.white);
    final pill = tester.widget<Container>(
      find.ancestor(of: _badgeOn('Wishlist'), matching: find.byType(Container)).first,
    );
    expect((pill.decoration! as BoxDecoration).color, AppColors.accent);
  });

  testWidgets('nothing saved, no badge: it is hidden at zero', (tester) async {
    await _mount(tester);
    await tester.pumpAndSettle();
    expect(_badgeOn('Wishlist'), findsNothing);
  });

  testWidgets('a guest has no wishlist and no badge', (tester) async {
    await _mount(
      tester,
      signedIn: false,
      wishlist: FakeWishlistRepository(entries: _entries(3)),
    );
    await tester.pumpAndSettle();
    expect(_badgeOn('Wishlist'), findsNothing);
  });

  testWidgets('adding a product raises it, removing one lowers it, and the '
      'last one takes the badge away', (tester) async {
    final container = await _mount(
      tester,
      wishlist: FakeWishlistRepository(entries: _entries(1)),
    );
    await tester.pumpAndSettle();
    final notifier = container.read(wishlistControllerProvider.notifier);
    expect(tester.widget<Text>(_badgeOn('Wishlist')).data, '1');

    await notifier.toggle('NEW');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_badgeOn('Wishlist')).data, '2');

    await notifier.toggle('NEW');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_badgeOn('Wishlist')).data, '1');

    await notifier.toggle('sku1');
    await tester.pumpAndSettle();
    expect(_badgeOn('Wishlist'), findsNothing);
  });

  testWidgets('past 99 it reads 99+, and the store\'s count wins when the '
      'first page holds fewer', (tester) async {
    await _mount(
      tester,
      wishlist: FakeWishlistRepository(entries: _entries(2), itemsCount: 120),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_badgeOn('Wishlist')).data, '99+');

    await _mount(
      tester,
      wishlist: FakeWishlistRepository(entries: _entries(2), itemsCount: 25),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_badgeOn('Wishlist')).data, '25');
  });

  testWidgets('signing out takes the badge away', (tester) async {
    final container = await _mount(
      tester,
      wishlist: FakeWishlistRepository(entries: _entries(4)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_badgeOn('Wishlist')).data, '4');

    await container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(_badgeOn('Wishlist'), findsNothing);
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('draws on a phone in $locale: the badge on the heart\'s '
        'leading corner, the digits Latin and left to right', (tester) async {
      final key = GlobalKey();
      await _mount(
        tester,
        locale: locale,
        boundary: key,
        wishlist: FakeWishlistRepository(entries: _entries(5)),
      );
      tester.view.physicalSize = const Size(390, 300);
      await tester.pumpAndSettle();
      await withRealShadows(() => captureScreen(tester, key, 'wishlist_badge_$locale'));

      final label = locale == 'ar' ? 'المفضلة' : 'Wishlist';
      final badge = tester.widget<Text>(_badgeOn(label));
      expect(badge.data, '5');
      expect(badge.textDirection, TextDirection.ltr);
      // The badge sits on the tab's icon, not off to the side.
      final tab = tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
      );
      expect(tab.contains(tester.getCenter(_badgeOn(label))), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
