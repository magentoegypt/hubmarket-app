import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';
import '../../catalog/domain/brand.dart';
import '../../catalog/domain/product.dart';
import '../../deals/domain/deals.dart';

/// `HmSectionType` — which widget a Home section is, and which content field
/// it fills.
enum HmSectionType {
  deliveryStrip('DELIVERY_STRIP'),
  heroBanners('HERO_BANNERS'),
  categoryChips('CATEGORY_CHIPS'),
  todaysDeals('TODAYS_DEALS'),
  pickedForYou('PICKED_FOR_YOU'),
  featuredStores('FEATURED_STORES'),
  categoryRail('CATEGORY_RAIL'),
  bundleDeals('BUNDLE_DEALS'),
  cmsPromos('CMS_PROMOS'),
  bestSellers('BEST_SELLERS'),
  popularProducts('POPULAR_PRODUCTS'),
  topBrands('TOP_BRANDS'),
  topVendors('TOP_VENDORS'),
  newStores('NEW_STORES'),
  trustRow('TRUST_ROW'),
  cmsBlock('CMS_BLOCK'),
  productList('PRODUCT_LIST'),

  /// Where the admin wants the signed-in customer's active-order card (Figma
  /// 07). Placement only: the section carries no content, the card reads the
  /// customer's own orders.
  activeOrder('ACTIVE_ORDER'),

  /// A type newer than this build: skipped.
  unknown('');

  const HmSectionType(this.wire);
  final String wire;

  /// Says where the app draws something of the viewer's own, with no content
  /// from the server.
  bool get isPlacement => this == activeOrder;

  static HmSectionType parse(Object? value) {
    for (final t in values) {
      if (t != unknown && t.wire == value) return t;
    }
    return unknown;
  }
}

/// `hmAppHome` — the Home the admin laid out (Content › App Home Sections).
@immutable
class HmHome {
  const HmHome({
    required this.storeCode,
    required this.sections,
    this.generatedAt,
  });

  final String storeCode;
  final DateTime? generatedAt;

  /// In admin order, as served (use [visibleSections] to draw).
  final List<HmHomeSection> sections;

  /// The sections to draw at [now]: known types with content, not past their
  /// `ends_at` (a cached copy can outlive a scheduled section). Placements
  /// ([HmSectionType.isPlacement]) are kept: they have no content by design.
  List<HmHomeSection> visibleSections(DateTime now) => [
    for (final section in sections)
      if (section.type != HmSectionType.unknown &&
          section.isLiveAt(now) &&
          section.hasContent)
        section,
  ];
}

/// Whether [sections] hold anything besides placements — a layout of nothing
/// but the active-order card is no Home, and the built-in one is drawn instead.
bool hmHomeHasContent(List<HmHomeSection> sections) =>
    sections.any((section) => !section.type.isPlacement);

/// One Home section; only the content field of its [type] is filled.
@immutable
class HmHomeSection {
  const HmHomeSection({
    required this.id,
    required this.type,
    this.title,
    this.subtitle,
    this.badge,
    this.limit = 0,
    this.endsAt,
    this.countdownEndsAt,
    this.personalizable = false,
    this.moreLink,
    this.banners = const <HmHeroBanner>[],
    this.categories = const <HmCategoryChip>[],
    this.cmsBlock,
    this.brands = const <Brand>[],
    this.bundles = const <BundleDeal>[],
    this.stores = const <HmStoreCard>[],
    this.products = const <Product>[],
  });

  final int id;
  final HmSectionType type;

  /// In the store view's language; null — or `-`, which the backend turns
  /// into null — hides the header.
  final String? title;
  final String? subtitle;

  /// The small pill above the title (admin Badge field, store view's language);
  /// null or blank: no pill.
  final String? badge;
  final int limit;

  /// Scheduled end (UTC); the section hides after it.
  final DateTime? endsAt;

  /// TODAYS_DEALS: end of the day of the soonest-ending offer shown.
  final DateTime? countdownEndsAt;

  /// The app may put the customer's own picks in place of [products].
  final bool personalizable;

  /// "View all".
  final HmLink? moreLink;

  final List<HmHeroBanner> banners;
  final List<HmCategoryChip> categories;
  final HmCmsBlock? cmsBlock;
  final List<Brand> brands;
  final List<BundleDeal> bundles;
  final List<HmStoreCard> stores;
  final List<Product> products;

  bool get hasHeader => title != null && title!.trim().isNotEmpty;

  bool isLiveAt(DateTime now) => endsAt == null || now.isBefore(endsAt!);

  List<HmHeroBanner> get slides =>
      [for (final b in banners) if (b.slot == HmBannerSlot.slide) b];

  List<HmHeroBanner> get tiles =>
      [for (final b in banners) if (b.slot == HmBannerSlot.tile) b];

  /// Whether the field this [type] draws has anything in it.
  bool get hasContent => switch (type) {
    HmSectionType.heroBanners => banners.isNotEmpty,
    HmSectionType.categoryChips => categories.isNotEmpty,
    HmSectionType.deliveryStrip ||
    HmSectionType.cmsPromos ||
    HmSectionType.trustRow ||
    HmSectionType.cmsBlock => (cmsBlock?.content.trim() ?? '').isNotEmpty,
    HmSectionType.topBrands => brands.isNotEmpty,
    HmSectionType.bundleDeals => bundles.isNotEmpty,
    HmSectionType.featuredStores ||
    HmSectionType.topVendors ||
    HmSectionType.newStores => stores.isNotEmpty,
    HmSectionType.todaysDeals ||
    HmSectionType.pickedForYou ||
    HmSectionType.categoryRail ||
    HmSectionType.bestSellers ||
    HmSectionType.popularProducts ||
    HmSectionType.productList => products.isNotEmpty,
    // The card decides for itself: nothing for a guest or without an order.
    HmSectionType.activeOrder => true,
    HmSectionType.unknown => false,
  };
}

/// `HmBannerSlot`.
enum HmBannerSlot { slide, tile }

/// A Hero Banner item (Content › Elements › Hero Banner): a carousel slide or
/// a side tile.
@immutable
class HmHeroBanner {
  const HmHeroBanner({
    required this.id,
    required this.slot,
    required this.title,
    required this.link,
    this.kicker,
    this.subtitle,
    this.ctaLabel,
    this.imageUrl,
    this.tone,
    this.accent,
  });

  final int id;
  final HmBannerSlot slot;
  final String title;

  /// The pill above the headline.
  final String? kicker;
  final String? subtitle;
  final String? ctaLabel;
  final String? imageUrl;

  /// The scrim colour over the image.
  final Color? tone;

  /// The pill / button colour (their label is white).
  final Color? accent;
  final HmLink link;
}

/// A category chip.
@immutable
class HmCategoryChip {
  const HmCategoryChip({
    required this.id,
    required this.uid,
    required this.name,
    required this.urlKey,
    required this.link,
    this.productCount = 0,
    this.icon,
    this.tint,
  });

  final int id;
  final String uid;
  final String name;
  final String urlKey;
  final int productCount;

  /// The configured glyph — an emoji on this store.
  final String? icon;

  /// Pastel slot 0–7.
  final int? tint;
  final HmLink link;
}

/// A CMS block (`HmCmsBlock`): rendered HTML of the store view.
@immutable
class HmCmsBlock {
  const HmCmsBlock({
    required this.identifier,
    required this.content,
    this.title,
  });

  final String identifier;
  final String? title;
  final String content;
}
