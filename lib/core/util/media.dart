/// Upgrades a Magento media URL to HTTPS.
///
/// The store's `base_media_url` is `http://hub-market.magento2.click/media/`, but the same
/// media is served over HTTPS (`secure_base_url`). Android blocks cleartext
/// http by default, so image URLs from GraphQL must be upgraded to https before
/// loading. Already-secure or relative/data URLs are returned unchanged.
String? httpsMediaUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}

/// Resolves a possibly-relative media path (e.g. a banner `image_url` from the
/// backend) against the store's [base] media URL, upgrading to HTTPS. Absolute
/// URLs pass through; empty input (or an empty base for a relative path) yields
/// an empty string so callers degrade gracefully.
///
/// The backend mixes two relative shapes, so the leading slash is significant:
///   `default/promo.png`      → relative to the media base  → `<base>/default/promo.png`
///   `/media/catalog/a.webp`  → relative to the store root  → `<origin>/media/catalog/a.webp`
/// Joining a root-relative path onto the media base would duplicate the
/// `/media/` segment and 404 (seen live on the Arabic `shopByCategories` feed).
String resolveMediaUrl(String? raw, String base) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return '';
  if (value.startsWith('http')) return httpsMediaUrl(value) ?? '';
  if (base.isEmpty) return '';
  if (value.startsWith('/')) {
    final origin = _origin(base);
    return origin.isEmpty ? '' : httpsMediaUrl('$origin$value') ?? '';
  }
  final b = base.endsWith('/') ? base : '$base/';
  return httpsMediaUrl('$b$value') ?? '';
}

/// The WebP copy the storefront keeps beside each resized product image: the
/// same URL plus `.webp` (`…/cache/<hash>/a/b/file.jpg` →
/// `…/cache/<hash>/a/b/file.jpg.webp`). It has the same pixel size for about a
/// third (JPEG) to a tenth (PNG) of the bytes — measured on the live catalogue
/// on 1 Oct 2026 — and for images uploaded from that day on it is encoded from
/// the original upload, so it is also the sharper one.
///
/// Null when [url] has no such copy, in which case it is loaded as it is:
///   * another host than the store's own [storeHost] — the public host answers
///     a copy that is not made yet with the JPEG, the uncached `multi.` origin
///     with a 404;
///   * anything but a resized product image — the "no image" placeholder, the
///     original uploads and every other media folder have none (404 even on
///     the public host);
///   * a format other than JPEG or PNG, or a URL with a query or fragment.
String? webpTwinUrl(String? url, {required String storeHost}) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != storeHost ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.path.startsWith(_resizedProductMedia)) {
    return null;
  }
  final path = uri.path.toLowerCase();
  if (!_webpSources.any(path.endsWith)) return null;
  return '$url.webp';
}

/// The formats the storefront re-encodes to WebP.
const List<String> _webpSources = ['.jpg', '.jpeg', '.png'];

/// Where Magento keeps a product image resized for the storefront.
const String _resizedProductMedia = '/media/catalog/product/cache/';

/// Scheme + host (+ explicit port) of [base], or empty when it isn't a usable
/// absolute URL. `Uri.origin` throws on those, so the parts are read directly.
String _origin(String base) {
  final uri = Uri.tryParse(base);
  if (uri == null || uri.host.isEmpty) return '';
  if (uri.scheme != 'http' && uri.scheme != 'https') return '';
  return uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}
