import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// A promo card from the CMS block `hm_home_promos` (Content › Blocks) — the
/// same block the website renders, so marketing edits it once for both.
class PromoTile {
  const PromoTile({
    required this.icon,
    required this.kicker,
    required this.title,
    required this.text,
    required this.url,
  });

  final String icon;
  final String kicker;
  final String title;
  final String text;
  final String url;
}

/// One item of the trust row from the CMS block `hm_home_trust`.
class TrustItem {
  const TrustItem({required this.title, required this.text});

  final String title;
  final String text;
}

/// Parses the storefront's CMS markup into typed content. The blocks use
/// stable BEM class names (`hm-promo__title`, `hm-trust__text`, …), so the app
/// renders them natively instead of in a web view — and anything it cannot
/// read is dropped rather than shown half-parsed.
abstract final class HomeContentParser {
  static String plainText(String html) {
    final text = html_parser.parseFragment(html).text ?? '';
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The first clause of a promise line: the text before its first `·` or `•`
  /// ("Free delivery on qualifying orders · Fast nationwide shipping" becomes
  /// "Free delivery on qualifying orders"). A line with no separator, or with
  /// nothing but separators, comes back as it is.
  static String firstClause(String text) {
    for (final clause in text.split(RegExp('[·•]'))) {
      final trimmed = clause.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return text;
  }

  static List<PromoTile> promos(String html) {
    final doc = html_parser.parseFragment(html);
    return doc
        .querySelectorAll('.hm-promo')
        .map(
          (el) => PromoTile(
            icon: _text(el, '.hm-promo__icon'),
            kicker: _text(el, '.hm-promo__kicker'),
            title: _text(el, '.hm-promo__title'),
            text: _text(el, '.hm-promo__text'),
            url: (el.attributes['href'] ?? '').trim(),
          ),
        )
        .where((p) => p.title.isNotEmpty)
        .toList(growable: false);
  }

  static List<TrustItem> trust(String html) {
    final doc = html_parser.parseFragment(html);
    return doc
        .querySelectorAll('.hm-trust__item')
        .map(
          (el) => TrustItem(
            title: _text(el, '.hm-trust__title'),
            text: _text(el, '.hm-trust__text'),
          ),
        )
        .where((t) => t.title.isNotEmpty)
        .toList(growable: false);
  }

  static String _text(dom.Element root, String selector) =>
      (root.querySelector(selector)?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
}
