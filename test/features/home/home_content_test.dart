import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/home/domain/home_content.dart';

// Markup copied from the live CMS blocks (hub-market.magento2.click, store `en`,
// 29 Sep 2026) so the parser is tested against what admins actually edit.
const _promos = '''
<div class="hm-promos">
  <a class="hm-promo hm-promo--a" href="https://hub-market.magento2.click/en/electronics.html/">
    <span class="hm-promo__icon" aria-hidden="true">⚡</span>
    <span class="hm-promo__kicker hm-promo__kicker--flash">Flash Sale</span>
    <span class="hm-promo__title">Up to 50% Off</span>
    <span class="hm-promo__text">Electronics &amp; Tech &middot; Today only</span>
  </a>
  <a class="hm-promo hm-promo--b" href="https://hub-market.magento2.click/en/super-market.html/">
    <span class="hm-promo__kicker">Seasonal Offers</span>
    <span class="hm-promo__title">Fresh Grocery Deals</span>
  </a>
  <a class="hm-promo" href="#"><span class="hm-promo__kicker">No title</span></a>
</div>
''';

const _trust = '''
<div class="hm-trust">
  <div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers</span><span class="hm-trust__text">Verified &amp; approved</span></div>
  <div class="hm-trust__item"><span class="hm-trust__title">Easy Returns</span></div>
</div>
''';

void main() {
  test('promos: reads every field, decodes entities, drops untitled tiles', () {
    final promos = HomeContentParser.promos(_promos);
    expect(promos, hasLength(2));
    expect(promos.first.icon, '⚡');
    expect(promos.first.kicker, 'Flash Sale');
    expect(promos.first.title, 'Up to 50% Off');
    expect(promos.first.text, 'Electronics & Tech · Today only');
    expect(promos.first.url, 'https://hub-market.magento2.click/en/electronics.html/');
    expect(promos[1].icon, isEmpty);
    expect(promos[1].text, isEmpty);
  });

  test('trust: title required, text optional', () {
    final items = HomeContentParser.trust(_trust);
    expect(items.map((t) => t.title), ['Trusted Sellers', 'Easy Returns']);
    expect(items.first.text, 'Verified & approved');
    expect(items.last.text, isEmpty);
  });

  test('plain text: strips tags and collapses whitespace', () {
    expect(
      HomeContentParser.plainText(
        '<p>Free delivery on qualifying orders &middot;\n  Fast nationwide shipping</p>',
      ),
      'Free delivery on qualifying orders · Fast nationwide shipping',
    );
  });

  test('first clause: the text before the first middle dot or bullet', () {
    expect(
      HomeContentParser.firstClause('Free delivery on qualifying orders · Fast nationwide shipping'),
      'Free delivery on qualifying orders',
    );
    expect(HomeContentParser.firstClause('Free delivery • Fast • Cheap'), 'Free delivery');
    expect(
      HomeContentParser.firstClause('توصيل مجاني على الطلبات المؤهلة · شحن سريع'),
      'توصيل مجاني على الطلبات المؤهلة',
    );
    // The separator needs no spaces around it.
    expect(HomeContentParser.firstClause('Free delivery·Fast shipping'), 'Free delivery');
  });

  test('first clause: no separator, or nothing before it, keeps the text', () {
    expect(
      HomeContentParser.firstClause('Free delivery on qualifying orders'),
      'Free delivery on qualifying orders',
    );
    // A leading separator skips to the first clause that has text.
    expect(HomeContentParser.firstClause('· Fast shipping'), 'Fast shipping');
    // Nothing but separators: unchanged, never an empty strip line.
    expect(HomeContentParser.firstClause('·'), '·');
    expect(HomeContentParser.firstClause(''), '');
  });

  test('empty or foreign markup yields nothing rather than half-parsed tiles', () {
    expect(HomeContentParser.promos(''), isEmpty);
    expect(HomeContentParser.trust('<p>Not a trust block</p>'), isEmpty);
  });
}
