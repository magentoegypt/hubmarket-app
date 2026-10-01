import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';

import '../../test/support/fakes.dart';

/// Fixtures shared by the onboarding scenes (scenes_onboarding.dart): the
/// pieces the widget tests of the splash, Welcome, the auth screens and the
/// app-wide states build for themselves, copied here so the tests stay as they
/// are.

// ---------------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------------

/// The public (GET) GraphQL client, which the audit harness does not fake: it
/// answers every request with an error at once, so a screen that reads the
/// Home, the stores or the config over it degrades without a request leaving
/// the app (what every widget test of these screens does).
Override offlinePublicClient() =>
    publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient());

// ---------------------------------------------------------------------------
// A01 Splash
// ---------------------------------------------------------------------------

/// A token store whose read never answers, so the splash — which leaves for
/// Welcome (or Home) once its 2.6 s hold is over *and* the saved session has
/// been read — stays on screen for the capture instead of being replaced by
/// the page it routes to (a stub in the audit router).
class HoldingTokenStore implements SecureTokenStore {
  final Completer<String?> _never = Completer<String?>();

  @override
  Future<String?> read() => _never.future;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}

/// Lets a scene stop every animation below it where it is: [freeze] mutes the
/// tickers (a muted ticker stops advancing its controller, so the splash's
/// progress bar keeps the value it had) without remounting the child — the
/// splash's hold timer lives in its state and a remount would start it again.
class FrozenTickers extends StatefulWidget {
  const FrozenTickers({super.key, required this.child});

  final Widget child;

  @override
  State<FrozenTickers> createState() => FrozenTickersState();
}

class FrozenTickersState extends State<FrozenTickers> {
  bool _frozen = false;

  void freeze() => setState(() => _frozen = true);

  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: !_frozen, child: widget.child);
}

/// "Reduce motion" for the subtree: the shimmer skeletons rest instead of
/// sweeping, which is what the Figma S4 frame draws (the platform setting the
/// widget test sets for it, as a [MediaQuery] so nothing global is left set
/// for the next scene).
class ReduceMotion extends StatelessWidget {
  const ReduceMotion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  );
}

// ---------------------------------------------------------------------------
// A02 Welcome
// ---------------------------------------------------------------------------

/// Photo URLs for the Welcome slides, by slide id: none is known offline, so
/// none is given and a slide shows the image placeholder. Put real banner URLs
/// here to see photos *on the phone*: the host sweep never gets them (see
/// [welcomeSlides]).
const Map<int, String> kWelcomeSlidePhotos = <int, String>{};

/// The Hero Banner slides of the guest Home, as the Welcome carousel draws
/// them: a kicker pill on each.
///
/// The host sweep pre-caches every `Image` in the tree before it captures, and
/// a network image never answers in the test renderer (its HTTP is stubbed), so
/// that capture would wait for ever: a slide gets its photo URL only on the
/// phone, and the host draws the placeholder.
List<HmHeroBanner> welcomeSlides(String locale) {
  final ar = locale == 'ar';
  final onPhone = Platform.isAndroid || Platform.isIOS;
  HmHeroBanner slide(int id, String kicker) => HmHeroBanner(
    id: id,
    slot: HmBannerSlot.slide,
    title: 'Slide $id',
    kicker: kicker,
    imageUrl: onPhone ? kWelcomeSlidePhotos[id] : null,
    accent: const Color(0xFF0F7B3F),
    link: const HmLink(
      type: HmLinkType.deals,
      url: 'https://hub-market.magento2.click/en/deals',
    ),
  );
  return [
    slide(1, ar ? 'توصيل في نفس اليوم' : 'SAME-DAY DELIVERY'),
    slide(2, ar ? 'عروض الأسبوع' : 'WEEKLY OFFERS'),
    slide(3, 'NEW'),
  ];
}

/// The `hm_delivery_promise` CMS block the logo panel's pill is read from.
Map<String, String> deliveryPromiseBlock(String locale) => {
  'hm_delivery_promise': locale == 'ar'
      ? '<p>توصيل مجاني على الطلبات المؤهلة &middot; شحن سريع</p>'
      : '<p>Free delivery on qualifying orders &middot; Fast nationwide '
            'shipping</p>',
};

// ---------------------------------------------------------------------------
// App-wide states: S3 offline, S4 loading
// ---------------------------------------------------------------------------

/// Products never arrive: the request did not reach the store (S3).
class OfflineCatalogRepository extends FakeCatalogRepository {
  @override
  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? brandOptionId,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) async => throw const Failure(FailureKind.network, detail: 'offline');
}

/// A Hub Market App probe that is still out: the Home has nothing to draw yet
/// and shows its skeleton (S4).
class PendingHubAppProbe extends HubAppController {
  @override
  Future<HubAppState> build() => Completer<HubAppState>().future;
}

/// A cart whose first load hasn't answered yet (S4).
class SlowCartRepository extends FakeCartRepository {
  final Completer<Cart> pending = Completer<Cart>();

  @override
  Future<Cart> getCart(String cartId) => pending.future;
}

/// Orders whose first page hasn't answered yet (S4).
class SlowOrdersRepository extends FakeAccountRepository {
  final Completer<OrderPage> pending = Completer<OrderPage>();

  @override
  Future<OrderPage> fetchOrders({int pageSize = 10, int currentPage = 1}) =>
      pending.future;
}
