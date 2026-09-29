import 'package:html/parser.dart' as html_parser;

/// Storefront content the app reads by a fixed identifier. Found on the live
/// store (29 Sep 2026, both store views) through the website's footer CMS
/// blocks, which link to these pages:
///
/// * `hm_footer_platform` "About Us" → CMS page `about-us`;
/// * `hm_footer_legal` "Privacy" → `privacy-policy-cookie-restriction-mode`,
///   "Terms" → `customer-service` (there is no separate terms page yet) and
///   "Cookies" → `enable-cookies`.
///
/// The legal links are read from `hm_footer_legal` itself rather than copied
/// here, so an admin who adds a terms page and relinks the footer changes the
/// website and the app at once.
abstract final class StorePages {
  /// About Hub Market.
  static const String about = 'about-us';

  /// The footer block holding the legal links (Privacy / Terms / Cookies).
  static const String legalLinksBlock = 'hm_footer_legal';

  /// The optional FAQ block the Help centre reads (see `FaqDocument`).
  static const String faqBlock = 'hm_app_faq';
}

/// A link inside a storefront CMS block, e.g. the footer's "Privacy".
class CmsLink {
  const CmsLink({required this.label, required this.url});

  final String label;
  final String url;
}

/// Every `<a href>` in [html] that has visible text, in document order.
List<CmsLink> linksFromHtml(String html) {
  if (html.trim().isEmpty) return const <CmsLink>[];
  final doc = html_parser.parseFragment(html);
  return [
    for (final a in doc.querySelectorAll('a'))
      if ((a.attributes['href'] ?? '').trim().isNotEmpty &&
          a.text.trim().isNotEmpty)
        CmsLink(
          label: a.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          url: a.attributes['href']!.trim(),
        ),
  ];
}

/// The store-relative path of a storefront [url] — what `route(url:)`
/// resolves: scheme, host, query, fragment, the store-view segment (`en/`,
/// `ar/`, `uae-en/`) and slashes around it stripped.
///
/// `https://hub-market.magento2.click/en/privacy-policy-cookie-restriction-mode/`
/// → `privacy-policy-cookie-restriction-mode`. Empty for the store root.
String storePathOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return '';
  var segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length > 1 &&
      RegExp(r'^(?:[a-z]{2}|[a-z]{2,4}[-_][a-z]{2})$').hasMatch(segments[0])) {
    segments = segments.sublist(1);
  } else if (segments.length == 1 &&
      RegExp(r'^(?:[a-z]{2}|[a-z]{2,4}[-_][a-z]{2})$').hasMatch(segments[0]) &&
      uri.host.isNotEmpty) {
    // `https://…/en/` is the store's home page, not a page called "en".
    return '';
  }
  return segments.join('/');
}
