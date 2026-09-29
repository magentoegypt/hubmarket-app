import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/util/media.dart';
import '../domain/home_config.dart';
import '../domain/promo_split_banner.dart';

// Dedicated home-content queries (MagentoEgypt_Beauty). Each is store-scoped
// (the client injects the `Store` header) and degrades to an empty list on any
// error or absence — an empty feed is normal (section toggled off / no content),
// so the section simply hides rather than erroring.

/// The home "Shop by Category" tiles (`shopByCategories`) — the merchant-curated
/// grid the website renders, ordered by the backend `position`.
///
/// This is intentionally NOT `categoryList`: the menu tree's top level misses
/// the curated sub-category tiles (Lipsticks / Eyes / Face) and carries
/// menu-only entries the site doesn't tile (New Arrivals / Bestsellers / Hair
/// Care), so the two feeds disagree. `shopByCategories` is the site's source.
const String _shopByCategoriesQuery = r'''
query ShopByCategories {
  shopByCategories {
    label
    category_uid
    url
    image
    position
  }
}
''';

final shopByCategoriesProvider =
    FutureProvider.autoDispose<List<ShopByCategoryTile>>((ref) async {
      final store = ref.watch(storeControllerProvider);
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final client = ref.watch(graphqlClientProvider);
      final base = storeMediaBase(store);
      try {
        final result = await client.query(
          QueryOptions(
            document: gql(_shopByCategoriesQuery),
            fetchPolicy: FetchPolicy.networkOnly,
          ),
        );
        if (result.hasException) return const <ShopByCategoryTile>[];
        final list = result.data?['shopByCategories'] as List<dynamic>?;
        if (list == null) return const <ShopByCategoryTile>[];
        final sorted = list.whereType<Map<String, dynamic>>().toList()
          ..sort(
            (a, b) =>
                _position(a['position']).compareTo(_position(b['position'])),
          );
        return sorted
            .map(
              (j) => ShopByCategoryTile(
                label: _s(j['label']),
                categoryUid: _s(j['category_uid']),
                url: _s(j['url']),
                imageUrl: resolveMediaUrl(_s(j['image']), base),
              ),
            )
            .where((t) => !t.isEmpty)
            .toList(growable: false);
      } catch (_) {
        return const <ShopByCategoryTile>[];
      }
    });

/// "Skincare / Makeup" editorial banners (`promoSplitBanners`, the 2-banner
/// block). Image-first, with an eyebrow + tagline + CTA.
const String _promoSplitQuery = r'''
query PromoSplitBanners {
  promoSplitBanners {
    eyebrow
    title
    cta_label
    cta_url
    image_url
  }
}
''';

final promoSplitBannersProvider =
    FutureProvider.autoDispose<List<PromoSplitBanner>>((ref) async {
      final store = ref.watch(storeControllerProvider);
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final client = ref.watch(graphqlClientProvider);
      final base = storeMediaBase(store);
      try {
        final result = await client.query(
          QueryOptions(
            document: gql(_promoSplitQuery),
            fetchPolicy: FetchPolicy.networkOnly,
          ),
        );
        if (result.hasException) return const <PromoSplitBanner>[];
        final list = result.data?['promoSplitBanners'] as List<dynamic>?;
        if (list == null) return const <PromoSplitBanner>[];
        return list
            .whereType<Map<String, dynamic>>()
            .map(
              (j) => PromoSplitBanner(
                eyebrow: _s(j['eyebrow']),
                title: _s(j['title']),
                ctaLabel: _s(j['cta_label']),
                ctaUrl: _s(j['cta_url']),
                imageUrl: resolveMediaUrl(_s(j['image_url']), base),
              ),
            )
            .where((b) => !b.isEmpty)
            .toList(growable: false);
      } catch (_) {
        return const <PromoSplitBanner>[];
      }
    });

/// "Exclusive Offers" banners (`homeBanners`, the 3-banner block). Mapped to the
/// banner UI: `title` → the big discount badge, `cta_label` → the white pill,
/// `description` → the terms line, over `image_url`.
const String _homeBannersQuery = r'''
query HomeBanners {
  homeBanners {
    title
    cta_label
    description
    image_url
    cta_url
  }
}
''';

final homeBannersProvider = FutureProvider.autoDispose<List<ExclusiveOffer>>((
  ref,
) async {
  final store = ref.watch(storeControllerProvider);
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  final base = storeMediaBase(store);
  try {
    final result = await client.query(
      QueryOptions(
        document: gql(_homeBannersQuery),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) return const <ExclusiveOffer>[];
    final list = result.data?['homeBanners'] as List<dynamic>?;
    if (list == null) return const <ExclusiveOffer>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(
          (j) => ExclusiveOffer(
            badge: _s(j['title']),
            title: _s(j['cta_label']),
            subtitle: _s(j['description']),
            ctaUrl: _s(j['cta_url']),
            imageUrl: resolveMediaUrl(_s(j['image_url']), base),
          ),
        )
        .where((o) => o.badge.isNotEmpty || o.title.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <ExclusiveOffer>[];
  }
});

/// "Why Shoppers Trust Hub Market" testimonials (`homeReviews`). Capped at 3 with a
/// minimum rating of 3 (the feed carries seeded test reviews pre-launch, so we
/// take a small high-rated slice).
const String _homeReviewsQuery = r'''
query HomeReviews($pageSize: Int!, $minRating: Int!) {
  homeReviews(pageSize: $pageSize, minRating: $minRating) {
    author
    quote
    rating
    product_name
  }
}
''';

final homeReviewsProvider = FutureProvider.autoDispose<List<Testimonial>>(
  (ref) => _loadReviews(ref, pageSize: 3, minRating: 3),
);

/// Every review the feed carries (for the full "Customer Reviews" screen behind
/// the home rail's See More). `homeReviews` caps at ~10 regardless of pageSize;
/// `minRating: 1` keeps the 4-star entries the home slice (minRating 3) drops.
final allReviewsProvider = FutureProvider.autoDispose<List<Testimonial>>(
  (ref) => _loadReviews(ref, pageSize: 50, minRating: 1),
);

/// Shared `homeReviews` fetch → parsed [Testimonial]s for the active store view.
/// Degrades to an empty list on any error/absence so the caller hides cleanly.
Future<List<Testimonial>> _loadReviews(
  Ref ref, {
  required int pageSize,
  required int minRating,
}) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(
        document: gql(_homeReviewsQuery),
        variables: {'pageSize': pageSize, 'minRating': minRating},
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) return const <Testimonial>[];
    final list = result.data?['homeReviews'] as List<dynamic>?;
    if (list == null) return const <Testimonial>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(
          (j) => Testimonial(
            quote: _s(j['quote']),
            author: _s(j['author']),
            product: _s(j['product_name']),
            rating: _rating(j['rating']),
          ),
        )
        .where((t) => t.quote.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <Testimonial>[];
  }
}

String _s(Object? v) => (v is String ? v : v?.toString() ?? '').trim();

/// Sort key for the "Shop by Category" tiles. Magento hands some numeric
/// scalars back as Strings, so parse rather than cast; anything unreadable
/// sorts last instead of throwing.
int _position(Object? v) => switch (v) {
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 1 << 30,
  _ => 1 << 30,
};

int _rating(Object? v) => switch (v) {
  final num n => n.round().clamp(0, 5),
  final String s => (int.tryParse(s) ?? 5).clamp(0, 5),
  _ => 5,
};

/// Base media URL of the active store view, for resolving relative banner paths.
/// Shared with `hero_slides_provider.dart` so every banner feed resolves and
/// TLS-upgrades its images the same way.
String storeMediaBase(StoreState store) {
  for (final s in store.stores) {
    if (s.storeCode == store.activeStoreCode) return s.baseMediaUrl;
  }
  return store.stores.isNotEmpty ? store.stores.first.baseMediaUrl : '';
}
