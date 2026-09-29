/// Admin-configured home merchandising toggles + the Limited-Time Offer, read
/// from the backend `magentoegypt_beauty_config` bag (a `{path, value}` list
/// under `MagentoEgypt_Beauty`). The actual section *content* comes from the
/// dedicated home queries (`heroSlides`, `promoSplitBanners`, `homeBanners`,
/// `homeReviews`, …); this config only carries the on/off switches and the
/// countdown promo, so the app hardcodes nothing.
///
/// Paths seen live (`bash tool/introspect.sh`):
///   general/enable_<section>       section on/off switches
///   deals/countdown_*              the Limited-Time Offer countdown banner
///   deals/category_id              the "Deals of the Day" category
///   offer/*                        the Special Offer card (own provider)
class HomeConfig {
  const HomeConfig({
    this.limitedTimeOffer = LimitedTimeOffer.hidden,
    this.dealsCategoryId = '',
    this.flags = const <String, String>{},
  });

  /// Raw `general/enable_*` switch values ("1"/"0"), keyed without the prefix.
  final Map<String, String> flags;

  final LimitedTimeOffer limitedTimeOffer;

  /// Magento category id for "Deals of the Day" (`deals/category_id`). The live
  /// deals category is flagged out of the menu (`include_in_menu = 0`), so it
  /// can't be found via the menu tree — the section resolves it by this id.
  final String dealsCategoryId;

  /// Whether a section is enabled. The `general/enable_*` flags are an explicit
  /// merchant *opt-out*, so an absent flag (or a failed config load) defaults to
  /// enabled — real content presence is what ultimately gates each section.
  bool sectionEnabled(String key) => switch (flags[key]) {
    '0' || 'false' => false,
    _ => true,
  };

  static const HomeConfig empty = HomeConfig();
}

/// The "Limited-Time Offer" countdown banner (`deals/countdown_*`). A `daily`
/// [mode] counts down to the next midnight in the **store's** timezone; any
/// other value hides the live clock but keeps the promo. Hidden unless enabled
/// with a headline.
class LimitedTimeOffer {
  const LimitedTimeOffer({
    this.enabled = false,
    this.headline = '',
    this.subtext = '',
    this.ctaLabel = '',
    this.ctaUrl = '',
    this.imageUrl = '',
    this.mode = 'daily',
    this.timezone = '',
  });

  final bool enabled;
  final String headline;
  final String subtext;
  final String ctaLabel;
  final String ctaUrl;
  final String imageUrl;
  final String mode;

  /// The store's IANA timezone (`storeConfig { timezone }`, e.g. `Asia/Dubai`),
  /// which the daily countdown resets against — see [isDaily]. Empty falls back
  /// to the device's own zone.
  final String timezone;

  bool get isVisible => enabled && headline.isNotEmpty;

  /// A daily countdown resets at midnight **in the store's [timezone]**, not the
  /// device's. The website does the same (its template bakes the store's UTC
  /// offset into the countdown element), so the two clocks agree for a shopper
  /// anywhere in the world.
  bool get isDaily => mode.toLowerCase() == 'daily';

  static const LimitedTimeOffer hidden = LimitedTimeOffer();
}

/// One home "Shop by Category" tile, populated from the backend
/// `shopByCategories` query — the merchant-curated grid the website renders.
///
/// Deliberately not the navigation menu tree (`categoryList`): the curated grid
/// tiles sub-categories the tree's top level never reaches (Lipsticks / Eyes /
/// Face) and omits menu-only entries the site doesn't tile (New Arrivals /
/// Bestsellers / Hair Care).
class ShopByCategoryTile {
  const ShopByCategoryTile({
    required this.label,
    this.categoryUid = '',
    this.url = '',
    this.imageUrl = '',
  });

  final String label;

  /// Magento category uid — routes straight to the PLP when present.
  final String categoryUid;

  /// Storefront URL; the routing fallback when [categoryUid] is absent.
  final String url;

  /// Tile image, resolved against the store media base in the provider — the
  /// Arabic view returns some paths relative while the rest are absolute.
  final String imageUrl;

  /// A tile with no label, or with nowhere to route, can't be rendered.
  bool get isEmpty => label.isEmpty || (categoryUid.isEmpty && url.isEmpty);
}

/// One "Exclusive Offers" banner, populated from the backend `homeBanners`
/// query: [badge] is the big discount ("25% OFF"), [title] the white category
/// pill ("Skincare"), [subtitle] the terms line, over [imageUrl].
class ExclusiveOffer {
  const ExclusiveOffer({
    required this.badge,
    this.title = '',
    this.subtitle = '',
    this.ctaUrl = '',
    this.imageUrl = '',
  });

  /// Short promo tag shown large, e.g. "25% OFF".
  final String badge;
  final String title;
  final String subtitle;
  final String ctaUrl;

  /// Background image (resolved against the store media base in the provider).
  /// Empty → the banner falls back to a blush background.
  final String imageUrl;
}

/// One "Why Shoppers Trust Hub Market" testimonial, populated from the backend
/// `homeReviews` query.
class Testimonial {
  const Testimonial({
    required this.quote,
    this.author = '',
    this.product = '',
    this.rating = 5,
  });

  final String quote;
  final String author;
  final String product;
  final int rating;
}
