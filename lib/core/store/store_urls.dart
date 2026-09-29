import 'store_controller.dart';
import 'store_view.dart';

/// Canonical **public** storefront URLs for the active store view.
///
/// Only `base_link_url` carries the store view's language path
/// (`https://hub-market.magento2.click/uae-en/`); `secure_base_url` is the bare Magento base
/// (`https://hub-market.magento2.click/`) and is identical for both views, so a URL built from
/// it silently resolves against the default (English) store. Anything the app
/// hands to a user — a share link, a "view on web" link — must therefore come
/// from here, not from an ad-hoc concatenation.
///
/// See `docs/zoonze-reference/decisions/deep-links.md`.

/// The active store view's public base, always `https://`, always with a
/// trailing slash. Empty when store config hasn't loaded yet.
String storeBaseUrl(StoreState state) {
  final base = _activeBase(state);
  if (base.isEmpty) return '';
  return _https(base.endsWith('/') ? base : '$base/');
}

/// Public URL for a store-relative [path], e.g. `shopbrand/` ->
/// `https://hub-market.magento2.click/uae-en/shopbrand/`. Null when the base is unknown or
/// [path] is empty.
String? storeUrl(StoreState state, String path) {
  final base = storeBaseUrl(state);
  final rel = path.startsWith('/') ? path.substring(1) : path;
  if (base.isEmpty || rel.isEmpty) return null;
  return '$base$rel';
}

/// Canonical PDP URL for a product `url_key`, e.g.
/// `https://hub-market.magento2.click/uae-en/6085010044712.html`.
///
/// The `.html` suffix is required: Magento's `urlResolver` returns null for a
/// bare `url_key`, so a suffix-less link 404s on the web and can't be resolved
/// back into the app.
String? productUrl(StoreState state, String urlKey) {
  final key = urlKey.trim();
  if (key.isEmpty) return null;
  return storeUrl(state, key.toLowerCase().endsWith('.html') ? key : '$key.html');
}

/// The app language a storefront URL's leading path segment belongs to, e.g.
/// `https://hub-market.magento2.click/uae-ar/foo.html` -> `ar`.
///
/// The segment is **not** the store code (`uae-ar` vs `eg_ar`), so it is matched
/// against each view's [StoreView.baseLinkUrl] path rather than guessed. Null
/// when the URL carries no recognised store segment.
String? localeForStoreUrl(StoreState state, String url) {
  final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty);
  if (segs == null || segs.isEmpty) return null;
  final first = segs.first.toLowerCase();
  for (final s in state.stores) {
    final linkSegs = Uri.tryParse(s.baseLinkUrl)?.pathSegments
        .where((p) => p.isNotEmpty)
        .toList();
    if (linkSegs == null || linkSegs.isEmpty) continue;
    if (linkSegs.first.toLowerCase() == first) return s.languageCode;
  }
  return null;
}

/// Base URL of the view matching [StoreState.activeStoreCode], preferring the
/// language-carrying `base_link_url`.
String _activeBase(StoreState state) {
  for (final s in state.stores) {
    if (s.storeCode != state.activeStoreCode) continue;
    if (s.baseLinkUrl.isNotEmpty) return s.baseLinkUrl;
    if (s.secureBaseUrl.isNotEmpty) return s.secureBaseUrl;
    return s.baseUrl;
  }
  return '';
}

/// Magento returns `base_link_url` as `http://`; force TLS.
String _https(String url) =>
    url.startsWith('http://') ? 'https://${url.substring(7)}' : url;
