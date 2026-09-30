import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../catalog/data/brands_repository.dart';
import '../../catalog/data/product_mapper.dart';
import '../../deals/data/deals_repository.dart';
import '../domain/hm_home.dart';

/// Reads the admin-laid-out Home (`hmAppHome`) over the public GET client —
/// one request, cached by the full-page cache per store view and audience.
class HmHomeRepository {
  HmHomeRepository(this._client);

  final GraphQLClient _client;

  /// The guest document. The audience goes inline (see [documentFor]): a
  /// `$audience: HmAudience` variable would make a server without the module
  /// answer HTTP 500 instead of "Cannot query field". Kept compact — it
  /// travels in the URL.
  static const String document = r'''
query HmAppHome {
  hmAppHome(audience: GUEST) {
    store_code
    generated_at
    sections {
      id type title subtitle limit ends_at countdown_ends_at personalizable
      more_link { ...HmLinkFields }
      banners { id slot title kicker subtitle cta_label image_url tone accent link { ...HmLinkFields } }
      categories { id uid name url_key product_count icon tint link { ...HmLinkFields } }
      cms_block { identifier title content }
      brands { ...HmBrandFields }
      bundles { ...HmBundleCard }
      stores { ...HmStoreCardFields }
      products { ...HmCardProduct }
    }
  }
}
''';

  /// The full request: [document] for [audience] and every fragment it uses.
  static String documentFor(HmAudience audience) =>
      document.replaceFirst('(audience: GUEST)', '(audience: ${audience.wire})') +
      HmFragments.link +
      HmFragments.storeCard +
      BrandsRepository.brandFields +
      DealsFragments.bundleCard +
      DealsFragments.cardProduct;

  /// The Home for [audience] in the active store view. Throws [HubAppMissing]
  /// without the module, a [Failure] otherwise.
  Future<HmHome> fetchHome(HmAudience audience) async {
    final data = await runHubAppQuery(_client, documentFor(audience));
    final json = data['hmAppHome'];
    if (json is! Map<String, dynamic>) {
      throw const Failure(FailureKind.server, detail: 'hmAppHome is empty');
    }
    return hmHomeFromJson(json);
  }
}

final hmHomeRepositoryProvider = Provider<HmHomeRepository>(
  (ref) => HmHomeRepository(ref.watch(publicGraphqlClientProvider)),
);

/// `hmAppHome` → [HmHome]. Unknown section types and unreadable items are
/// dropped, never thrown on.
HmHome hmHomeFromJson(Map<String, dynamic> json) => HmHome(
  storeCode: hmString(json['store_code']) ?? '',
  generatedAt: hmDateTime(json['generated_at']),
  sections: [
    for (final item in json['sections'] is List ? json['sections'] as List : const [])
      if (hmHomeSectionFromJson(item) case final section?) section,
  ],
);

List<Object?> _list(Object? value) => value is List ? value : const [];

/// One `HmHomeSection`; null for anything that isn't one.
HmHomeSection? hmHomeSectionFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final title = hmString(json['title']);
  final block = json['cms_block'];
  return HmHomeSection(
    id: hmInt(json['id']) ?? 0,
    type: HmSectionType.parse(json['type']),
    // "-" hides the header; the backend already sends null for it, the app
    // doesn't rely on that.
    title: title == '-' ? null : title,
    subtitle: hmString(json['subtitle']) == '-' ? null : hmString(json['subtitle']),
    limit: hmInt(json['limit']) ?? 0,
    endsAt: hmDateTime(json['ends_at']),
    countdownEndsAt: hmDateTime(json['countdown_ends_at']),
    personalizable: json['personalizable'] == true,
    moreLink: HmLink.fromJson(json['more_link']),
    banners: [
      for (final item in _list(json['banners']))
        if (heroBannerFromJson(item) case final banner?) banner,
    ],
    categories: [
      for (final item in _list(json['categories']))
        if (categoryChipFromJson(item) case final chip?) chip,
    ],
    cmsBlock: block is Map<String, dynamic> && hmString(block['identifier']) != null
        ? HmCmsBlock(
            identifier: hmString(block['identifier'])!,
            title: hmString(block['title']),
            content: (block['content'] as String?) ?? '',
          )
        : null,
    brands: [
      for (final (i, item) in _list(json['brands']).indexed)
        if (brandFromHmJson(item, position: i) case final brand?) brand,
    ],
    bundles: [
      for (final item in _list(json['bundles']))
        if (bundleDealFromJson(item) case final deal?) deal,
    ],
    stores: [
      for (final item in _list(json['stores']))
        if (HmStoreCard.fromJson(item) case final card?) card,
    ],
    products: [
      for (final item in _list(json['products']))
        if (item is Map<String, dynamic>) productFromJson(item),
    ].where((p) => p.urlKey.isNotEmpty).toList(growable: false),
  );
}

/// One `HmHeroBanner`; null without a title or a link.
HmHeroBanner? heroBannerFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final title = hmString(json['title']);
  final link = HmLink.fromJson(json['link']);
  if (title == null || link == null) return null;
  return HmHeroBanner(
    id: hmInt(json['id']) ?? 0,
    slot: json['slot'] == 'TILE' ? HmBannerSlot.tile : HmBannerSlot.slide,
    title: title,
    link: link,
    kicker: hmString(json['kicker']),
    subtitle: hmString(json['subtitle']),
    ctaLabel: hmString(json['cta_label']),
    imageUrl: hmImageUrl(json['image_url']),
    tone: hexColor(json['tone']),
    accent: hexColor(json['accent']),
  );
}

/// One `HmCategoryChip`; null without a uid, a name or a link.
HmCategoryChip? categoryChipFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final uid = hmString(json['uid']);
  final name = hmString(json['name']);
  final link = HmLink.fromJson(json['link']);
  if (uid == null || name == null || link == null) return null;
  return HmCategoryChip(
    id: hmInt(json['id']) ?? 0,
    uid: uid,
    name: name,
    urlKey: hmString(json['url_key']) ?? '',
    link: link,
    productCount: hmInt(json['product_count']) ?? 0,
    icon: hmString(json['icon']),
    tint: hmInt(json['tint']),
  );
}

/// `#RRGGBB`, `RRGGBB`, `#RGB` or `#AARRGGBB` → an opaque-by-default
/// [Color]; null for anything else.
Color? hexColor(Object? value) {
  var hex = hmString(value)?.replaceFirst('#', '');
  if (hex == null) return null;
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final argb = int.tryParse(hex, radix: 16);
  return argb == null ? null : Color(argb);
}
