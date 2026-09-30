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

/// The store's legal pages, as the footer block `hm_footer_legal` links them.
enum LegalPage { privacy, cookies, terms }

/// Which legal page [link] opens, read from its URL and label (English and
/// Arabic). Privacy is checked first: its page's key,
/// `privacy-policy-cookie-restriction-mode`, also names cookies. Anything
/// else counts as terms — on the live store "Terms" / «الشروط» opens
/// `customer-service`, whose URL says nothing about terms.
LegalPage legalPageOf(CmsLink link) {
  final url = link.url.toLowerCase();
  final label = link.label.toLowerCase();
  bool names(List<String> words) =>
      words.any((w) => url.contains(w) || label.contains(w));
  if (names(const ['privacy', 'خصوصي'])) return LegalPage.privacy;
  if (names(const ['cookie', 'ارتباط', 'كوكي'])) return LegalPage.cookies;
  return LegalPage.terms;
}

/// The link in [links] that opens [page], or null when the block has none.
/// For terms, a link that names terms or conditions wins over one that is
/// terms only by elimination.
CmsLink? legalLinkFor(List<CmsLink> links, LegalPage page) {
  final matches = [
    for (final link in links)
      if (legalPageOf(link) == page) link,
  ];
  if (page != LegalPage.terms) return matches.firstOrNull;
  bool namesTerms(CmsLink link) {
    final text = '${link.url} ${link.label}'.toLowerCase();
    return const ['term', 'condition', 'شروط', 'أحكام'].any(text.contains);
  }

  return matches.where(namesTerms).firstOrNull ?? matches.firstOrNull;
}

/// One run of a sentence with legal links (see `LegalLinksText`): plain
/// words, or words that open [page].
typedef LegalTextPart = ({String text, LegalPage? page});

final RegExp _legalTag = RegExp(
  r'<(terms|privacy|cookies)>(.*?)</\1>',
  dotAll: true,
);

/// Splits interface wording at its `<terms>…</terms>`, `<privacy>…</privacy>`
/// and `<cookies>…</cookies>` pairs, as in
/// `I agree to the <terms>Terms of Service</terms> and …`. Anything else, an
/// unclosed tag included, stays as written.
List<LegalTextPart> legalTextParts(String text) {
  final parts = <LegalTextPart>[];
  var start = 0;
  for (final match in _legalTag.allMatches(text)) {
    if (match.start > start) {
      parts.add((text: text.substring(start, match.start), page: null));
    }
    parts.add((
      text: match.group(2)!,
      page: LegalPage.values.byName(match.group(1)!),
    ));
    start = match.end;
  }
  if (start < text.length) {
    parts.add((text: text.substring(start), page: null));
  }
  return parts;
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
