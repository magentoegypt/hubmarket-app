import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/store/store_urls.dart';
import '../../../core/util/launch.dart';
import '../../../core/widgets/web_view_screen.dart';
import '../../../l10n/l10n.dart';
import '../../cms/domain/cms_links.dart';
import '../data/brands_provider.dart';
import '../data/catalog_repository.dart';
import '../domain/brand.dart';
import '../domain/category.dart';

/// Storefront-URL -> in-app-route plumbing, shared by the home CTAs and by the
/// deep-link resolver (`DeepLinkResolverScreen`). Kept in one place so an
/// incoming app link and a hero banner resolve identically.

/// Routes a storefront CTA URL inside the app: a Magento `category/view/id/N`
/// URL maps straight to the PLP; a `shopbrand` URL opens the app's own brand
/// listing; a store-relative or same-domain friendly URL (`clearance.html`,
/// `fragrance/for-her.html`) is resolved via `urlResolver` so a CATEGORY opens
/// the PLP, a PRODUCT the PDP and a CMS_PAGE the native content page; anything
/// else of ours (marketplace pages, the blog) opens in the in-app
/// [WebViewScreen]. Only a genuinely foreign host or a non-web scheme leaves
/// the app.
///
/// **Our own domain never goes to the platform browser.** The Android manifest
/// claims `hub-market.magento2.click`, so launching one of our links externally either bounces
/// straight back into the app (a flicker plus a redundant `urlResolver` round
/// trip) or — while `assetlinks.json` is unpublished — dumps the user in Chrome.
/// On iOS, with no associated-domains entitlement, it always ejected to Safari.
/// That was CL042-DEV19: every banner whose CTA wasn't a catalogue entity.
/// See `docs/zoonze-reference/decisions/deep-links.md`.
///
/// Shared by the hero carousel, Shop by Category, the Limited-Time Offer, the
/// editorial banners and the Exclusive Offers rail so every home CTA behaves
/// identically.
Future<void> openStorefrontUrl(
  BuildContext context,
  WidgetRef ref,
  String url, {
  String? title,
}) async {
  final uri = Uri.tryParse(url.trim());
  if (url.trim().isEmpty || uri == null) return;

  // `mailto:`, `tel:`, `whatsapp:` — the platform owns these.
  final scheme = uri.scheme.toLowerCase();
  if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') {
    launchExternalUri(uri);
    return;
  }

  // An explicit category-id URL needs no round trip: the PLP wants the UID,
  // which is base64 of the numeric id.
  final uid = categoryUidFromUrl(url);
  if (uid != null) {
    context.push(AppRoutes.category(uid), extra: title);
    return;
  }

  if (uri.host.isNotEmpty && !isInternalStoreUrl(ref, url)) {
    launchExternalUri(uri);
    return;
  }

  // Ours, or store-relative, from here on.

  // A `shopbrand` page is a brand landing, not a catalogue entity — it has no
  // `url_rewrite`, so `urlResolver` returns null for it and the old code fell
  // through to the WebView. Route it to the app's own brand listing instead,
  // the same screen the Brands directory and the home Brands rail open.
  // CL042-DEV19/QA01: every editorial and Exclusive-Offers banner is one of
  // these, and the embedded page is what QA saw fail.
  final brandKey = shopbrandKey(url);
  if (brandKey != null) {
    if (brandKey.isEmpty) {
      context.push(AppRoutes.brands);
      return;
    }
    final brand = await lookUpBrand(ref, url);
    if (!context.mounted) return;
    if (brand != null) {
      context.push(AppRoutes.brand, extra: brand);
      return;
    }
    // Brand feed unavailable or the key is unknown: show the page itself.
  }

  final resolved = await ref.read(catalogRepositoryProvider).resolveUrl(url);
  if (!context.mounted) return;
  if (resolved != null) {
    if (resolved.type == 'CATEGORY' && resolved.uid.isNotEmpty) {
      context.push(AppRoutes.category(resolved.uid), extra: title);
      return;
    }
    if (resolved.type == 'PRODUCT' && resolved.urlKey != null) {
      context.push(AppRoutes.product(resolved.urlKey!));
      return;
    }
    // A CMS page (About, policies, customer service) renders natively.
    final path = storePathOf(url);
    if (resolved.type == 'CMS_PAGE' && path.isNotEmpty) {
      context.push(AppRoutes.cmsPageByUrl(path, title: title));
      return;
    }
  }

  // Not a catalogue entity. Show the real page in the in-app browser rather
  // than dead-ending — a relative path we can't absolutise is ignored, never
  // launched as a bare relative URI.
  final web = inAppStorefrontUrl(ref.read(storeControllerProvider), url);
  if (web == null) return;
  context.push(
    AppRoutes.webview,
    extra: WebViewArgs(
      url: web,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : AppLocalizations.of(context).appTitle,
    ),
  );
}

/// The brand [url] points at, taken from the already-loaded feed when the home
/// Brands rail has warmed it and fetched otherwise.
///
/// Never throws and never blocks indefinitely: `brandsProvider` is autoDispose
/// and this is a bare `read` with no listener, so the feed being unavailable
/// simply means the caller falls back to opening the storefront page itself.
Future<Brand?> lookUpBrand(WidgetRef ref, String url) async {
  final cached = ref.read(brandsProvider).valueOrNull;
  if (cached != null) return brandFromStorefrontUrl(cached, url);
  try {
    final brands = await ref
        .read(brandsProvider.future)
        .timeout(const Duration(seconds: 8));
    return brandFromStorefrontUrl(brands, url);
  } on Object {
    return null;
  }
}

/// The brand key in a `shopbrand` storefront URL, or null when [url] isn't a
/// brand page at all. An empty string means the brand *index* (`/shopbrand/`),
/// which is the directory rather than one brand.
///
/// Tolerates the store segment (`/uae-en/`, `/uae-ar/`), a missing `.html`, and
/// the trailing slash the live feed actually emits
/// (`.../shopbrand/Mancera.html/`).
String? shopbrandKey(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final at = segments.indexWhere((s) => s.toLowerCase() == 'shopbrand');
  if (at < 0) return null;
  if (at + 1 >= segments.length) return '';
  var key = segments[at + 1];
  if (key.toLowerCase().endsWith('.html')) {
    key = key.substring(0, key.length - 5);
  }
  return key;
}

/// True when [url] is the brand directory (`/shopbrand/`, no brand key).
bool isBrandIndexUrl(String url) => shopbrandKey(url) == '';

/// The brand a `/shopbrand/<url_key>.html` URL points at, or null when [url]
/// isn't a single-brand page or nothing in [brands] matches.
///
/// Matches `url_key` first (what the storefront builds the URL from), then the
/// display `title`, then both with punctuation and spacing folded away — admin
/// can key a banner by the brand's name (`Bath & Body Works`) where the feed
/// carries `BathBodyWorks`.
Brand? brandFromStorefrontUrl(List<Brand> brands, String url) {
  final key = shopbrandKey(url);
  if (key == null || key.isEmpty) return null;
  final needle = key.toLowerCase();

  for (final b in brands) {
    if (b.urlKey.toLowerCase() == needle) return b;
  }
  for (final b in brands) {
    if (b.title.toLowerCase() == needle) return b;
  }

  final folded = _fold(key);
  if (folded.isEmpty) return null;
  for (final b in brands) {
    if (_fold(b.urlKey) == folded || _fold(b.title) == folded) return b;
  }
  return null;
}

/// Lowercased ASCII letters and digits only — drops spaces, `&`, `'`, `-`.
/// Returns `''` for a purely non-Latin string, which callers must treat as
/// "can't compare this way" rather than as a match.
String _fold(String s) {
  final out = StringBuffer();
  for (final c in s.toLowerCase().codeUnits) {
    final isDigit = c >= 0x30 && c <= 0x39;
    final isLetter = c >= 0x61 && c <= 0x7a;
    if (isDigit || isLetter) out.writeCharCode(c);
  }
  return out.toString();
}

/// Absolute `https://` storefront URL for [url], or null when a relative path
/// can't be absolutised (store config not loaded).
///
/// A relative path is resolved against the active view's `base_link_url`, which
/// is the only base carrying the language segment (`/uae-ar/`); an existing
/// query string and fragment are preserved verbatim.
///
/// Deliberately does **not** append the storefront's `webview=1` chrome-hiding
/// flag. That flag returns HTTP 500 on `shopbrand` pages (CL042-DEV19/QA01),
/// and the app can't know which other page types it breaks, so every in-app
/// storefront link now loads the page exactly as the browser would — matching
/// what `DeepLinkResolverScreen` has always done.
String? inAppStorefrontUrl(StoreState state, String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;

  if (uri.host.isNotEmpty) {
    final https = uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri;
    return https.toString();
  }

  final base = Uri.tryParse(storeBaseUrl(state));
  if (base == null || base.host.isEmpty) return null;
  final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
  var path = uri.path;
  // Don't double the store segment when the path already carries it.
  if (path.startsWith(basePath)) {
    path = path.substring(basePath.length);
  } else if (path.startsWith('/')) {
    path = path.substring(1);
  }
  return Uri(
    scheme: 'https',
    host: base.host,
    port: base.hasPort && base.port != 443 ? base.port : null,
    path: '$basePath$path',
    query: uri.query.isEmpty ? null : uri.query,
    fragment: uri.fragment.isEmpty ? null : uri.fragment,
  ).toString();
}

/// True when [url]'s host is the storefront's own domain (so the link should
/// open inside the app, not the external browser).
bool isInternalStoreUrl(WidgetRef ref, String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  if (host == 'hub-market.magento2.click' || host.endsWith('.hub-market.magento2.click')) return true;
  for (final s in ref.read(storeControllerProvider).stores) {
    for (final base in [s.secureBaseUrl, s.baseUrl, s.baseLinkUrl]) {
      final h = Uri.tryParse(base)?.host.toLowerCase();
      if (h != null && h.isNotEmpty && h == host) return true;
    }
  }
  return false;
}

/// Maps a Magento category URL to the in-app category route's UID, or null if
/// it isn't a category URL. Magento's category UID is base64 of the numeric id,
/// so `.../catalog/category/view/id/5/` → `base64("5")`.
String? categoryUidFromUrl(String url) {
  final match = RegExp(r'/category/view/id/(\d+)').firstMatch(url);
  if (match == null) return null;
  return categoryUidFromId(match.group(1)!);
}