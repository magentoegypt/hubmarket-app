import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/widgets/offline_state.dart';
import 'package:hubmarket_app/core/widgets/shimmer.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import 'cart_screen_harness.dart';

/// A cart that can't be reached: the request never got to the store.
class _OfflineCart extends FakeCartRepository {
  int loads = 0;

  @override
  Future<Cart> getCart(String cartId) async {
    loads++;
    throw const Failure(FailureKind.network);
  }
}

/// The store answering 503.
class _StoreDownCart extends FakeCartRepository {
  @override
  Future<Cart> getCart(String cartId) async =>
      throw const Failure(FailureKind.service, detail: 'HTTP 503');
}

/// A cart whose first load hasn't answered yet.
class _SlowCart extends FakeCartRepository {
  final pending = Completer<Cart>();

  @override
  Future<Cart> getCart(String cartId) => pending.future;
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('offline: the S3 page instead of an error line ($locale)', (
      tester,
    ) async {
      phoneView(tester);
      final cart = _OfflineCart();
      final key = GlobalKey();
      await tester.pumpWidget(
        cartScreenApp(locale: locale, cart: cart, boundary: key),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'cart_offline_$locale');

      expect(find.byType(OfflineState), findsOneWidget);
      expect(find.text(l10n.offlineTitle), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsNothing);

      final before = cart.loads;
      await tester.tap(find.text(l10n.offlineTryAgain));
      await tester.pumpAndSettle();
      expect(cart.loads, before + 1);
    });

    testWidgets('first load: a skeleton, not a spinner ($locale)', (
      tester,
    ) async {
      phoneView(tester);
      final cart = _SlowCart();
      final key = GlobalKey();
      await tester.pumpWidget(
        cartScreenApp(locale: locale, cart: cart, boundary: key),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await captureScreen(tester, key, 'cart_loading_$locale');

      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      cart.pending.complete(const Cart(id: 'guest-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Shimmer), findsNothing);
      expect(find.text(l10n.cartEmptyTitle), findsOneWidget);
    });
  }

  testWidgets('a store outage keeps the message and Retry', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(cartScreenApp(locale: 'en', cart: _StoreDownCart()));
    await tester.pumpAndSettle();

    expect(find.byType(OfflineState), findsNothing);
    expect(
      find.text('The store is temporarily unavailable. Please try again shortly.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });
}
