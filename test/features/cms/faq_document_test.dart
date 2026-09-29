import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/cms/domain/cms_document.dart';
import 'package:hubmarket_app/features/cms/domain/faq.dart';

/// `hm_app_faq` written the documented way, inside a Page Builder row.
const _faqBlock = '''
<div data-content-type="row"><div data-element="inner">
  <h2 data-icon="orders">Orders &amp; delivery</h2>
  <p>Everything about your orders.</p>
  <h3>How do I track my order?</h3>
  <p>Open <strong>Account › My orders</strong>.</p>
  <ul><li>Customers: My orders</li><li>Guests: Track order</li></ul>
  <h3>Can I cancel?</h3>
  <p>Until it ships. <a href="https://hub-market.magento2.click/en/customer-service/">Details</a></p>
  <h2 data-icon="payments">Payments</h2>
  <h3>How can I pay?</h3>
  <p>The methods are listed at checkout.</p>
  <h2>Empty topic</h2>
</div></div>
''';

void main() {
  group('FaqDocument.parse', () {
    test('h2 starts a topic, h3 a question, the rest is the answer', () {
      final topics = FaqDocument.parse(_faqBlock);
      expect(topics.map((t) => t.title), ['Orders & delivery', 'Payments']);
      expect(topics.map((t) => t.icon), ['orders', 'payments']);

      final orders = topics.first.items;
      expect(orders.map((i) => i.question), [
        'How do I track my order?',
        'Can I cancel?',
      ]);
      // The topic intro before the first question isn't part of any answer.
      expect(orders.first.answer, hasLength(2));
      expect(orders.first.answer[0], isA<CmsParagraph>());
      expect(orders.first.answer[1], isA<CmsList>());
      // Links survive into the answer.
      final cancel = orders[1].answer.single as CmsParagraph;
      expect(
        cancel.inlines.any(
          (r) =>
              r.href == 'https://hub-market.magento2.click/en/customer-service/',
        ),
        isTrue,
      );
    });

    test('topics without questions are dropped', () {
      expect(
        FaqDocument.parse(_faqBlock).where((t) => t.title == 'Empty topic'),
        isEmpty,
      );
    });

    test('questions before any topic form an untitled group', () {
      final topics = FaqDocument.parse(
        '<h3>Loose question?</h3><p>Loose answer.</p>'
        '<h2>Topic</h2><h3>Q?</h3><p>A.</p>',
      );
      expect(topics, hasLength(2));
      expect(topics.first.title, isNull);
      expect(topics.first.items.single.question, 'Loose question?');
      expect(topics.last.title, 'Topic');
    });

    test('search matches the question and the answer text', () {
      final item = FaqDocument.parse(_faqBlock).first.items.first;
      expect(item.matches('track'), isTrue);
      expect(item.matches('guests: track order'), isTrue);
      expect(item.matches('refund'), isFalse);
    });

    test('markup without questions yields no FAQ', () {
      expect(FaqDocument.parse(''), isEmpty);
      expect(FaqDocument.parse('<p>Coming soon</p><h2>Topic</h2>'), isEmpty);
    });
  });
}
