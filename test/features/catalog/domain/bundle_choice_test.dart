import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/cart/domain/bundle_cart_request.dart';
import 'package:hubmarket_app/features/catalog/domain/bundle_choice.dart';
import 'package:hubmarket_app/features/catalog/domain/bundle_product.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';

import '../../../support/bundle_fixtures.dart';

Money _aed(double amount) => Money(amount: amount, currency: 'AED');

void main() {
  group('the fitness pack (a kit: one default per option)', () {
    final bundle = bundleOf(fitnessPackJson());
    final choice = BundleChoice.initial(bundle);

    test('starts with every default selection, nothing to fix', () {
      expect(
        [
          for (final option in bundle.options)
            for (final s in choice.chosenIn(option)) s.name,
        ],
        [
          'Voyage Yoga Bag',
          'Dual Handle Cardio Ball',
          'Sprite Foam Yoga Brick',
          'Sprite Stasis Ball 55 cm',
        ],
      );
      expect(choice.issues(bundle), isEmpty);
    });

    test('maps to the mutation input: one selection per chosen one', () {
      expect(
        choice.toRequest('HM-DEMO-BUNDLE-FITNESS', bundle, quantity: 2),
        const BundleCartRequest(
          sku: 'HM-DEMO-BUNDLE-FITNESS',
          quantity: 2,
          selections: [
            BundleSelectionInput(selectionUid: 'YnVuZGxlLzIwLzYzLzE='),
            BundleSelectionInput(selectionUid: 'YnVuZGxlLzIxLzY0LzE='),
            BundleSelectionInput(selectionUid: 'YnVuZGxlLzIyLzY1LzE='),
            BundleSelectionInput(selectionUid: 'YnVuZGxlLzIzLzY2LzE='),
          ],
        ),
      );
    });

    test("is priced with the server's own price (Figma 14b)", () {
      final quote = BundleQuote.of(bundle, choice);

      expect(quote.exact, isTrue);
      expect(quote.total, _aed(60.56));
      expect(quote.regular, _aed(72));
      expect(quote.saving, _aed(11.44));
      expect(quote.savingPercent, 16);
    });
  });

  group('a bundle with choices', () {
    final bundle = bundleOf(kitBuilderJson());
    final top = bundle.options[0];
    final mat = bundle.options[1];
    final extras = bundle.options[2];
    final bottle = bundle.options[3];
    final configurableTop = top.selections[0];
    final tee = top.selections[1];

    test('parses options in order, with their types', () {
      expect(bundle.options.map((o) => o.title), [
        'Top',
        'Mat',
        'Extras',
        'Bottle',
      ]);
      expect(top.type, BundleOptionType.radio);
      expect(extras.type.allowsMany, isTrue);
      expect(extras.required, isFalse);
      expect(configurableTop.child!.isConfigurable, isTrue);
      expect(bottle.selections.single.canChangeQuantity, isTrue);
    });

    test('a required option without a default asks to be chosen', () {
      final issues = BundleChoice.initial(bundle).issues(bundle);

      expect(
        issues.map((i) => (i.kind, i.option.title)),
        contains((BundleIssueKind.needsSelection, 'Mat')),
      );
    });

    test("a configurable child asks for its size", () {
      final choice = BundleChoice.initial(
        bundle,
      ).choose(mat, mat.selections.first);
      final issue = choice.issues(bundle).single;

      expect(issue.kind, BundleIssueKind.needsAttribute);
      expect(issue.selection, same(configurableTop));
      expect(issue.attribute!.label, 'Size');
    });

    test('the chosen size, quantity and extras go into the input', () {
      final choice = BundleChoice.initial(bundle)
          .choose(mat, mat.selections.first)
          .withAttribute(configurableTop, 'size', 168)
          .toggle(extras, extras.selections[1])
          .withQuantity(bottle.selections.single, 3);

      expect(choice.issues(bundle), isEmpty);
      expect(choice.toRequest('KIT-BUILDER', bundle).selections, const [
        BundleSelectionInput(
          selectionUid: 'c2VsL3RvcA==',
          configurableOptionUids: ['Y29uZmlndXJhYmxlLzE0NC8xNjg='],
        ),
        BundleSelectionInput(selectionUid: 'c2VsL21hdA=='),
        BundleSelectionInput(selectionUid: 'c2VsL3Rvd2Vs'),
        BundleSelectionInput(selectionUid: 'c2VsL2JvdA==', quantity: 3),
      ]);
    });

    test(
      'swapping replaces a single choice; toggling a checkbox adds and removes',
      () {
        var choice = BundleChoice.initial(bundle).choose(top, tee);
        expect(choice.chosenIn(top), [tee]);

        choice = choice.toggle(extras, extras.selections[0]);
        choice = choice.toggle(extras, extras.selections[1]);
        expect(choice.chosenIn(extras), extras.selections);

        choice = choice.toggle(extras, extras.selections[0]);
        expect(choice.chosenIn(extras), [extras.selections[1]]);
      },
    );

    test("a sold-out size can't go", () {
      final soldOut = bundleOf(kitBuilderJson(mSoldOut: true));
      final choice = BundleChoice.initial(soldOut)
          .choose(soldOut.options[1], soldOut.options[1].selections.first)
          .withAttribute(soldOut.options[0].selections.first, 'size', 168);

      expect(choice.issues(soldOut).single.kind, BundleIssueKind.outOfStock);
    });

    test("the cheapest package is the server's price", () {
      final cheapest = BundleChoice.initial(
        bundle,
      ).choose(top, tee).choose(mat, mat.selections.first);
      final quote = BundleQuote.of(bundle, cheapest);

      expect(quote.exact, isTrue);
      expect(quote.total, _aed(39.6));
      expect(quote.regular, _aed(44));
    });

    test('another package: its items times the bundle discount, not exact', () {
      final dearer = BundleChoice.initial(bundle)
          .choose(mat, mat.selections[1]) // Pro Mat 40
          .withAttribute(configurableTop, 'size', 168); // M 34
      final quote = BundleQuote.of(bundle, dearer);

      // 34 + 40 + 2 × 3 = 80 at regular prices; 10% off like the cheapest.
      expect(quote.exact, isFalse);
      expect(quote.regular, _aed(80));
      expect(quote.total, _aed(72));
      expect(quote.saving, _aed(8));
      expect(quote.savingPercent, 10);
    });

    test('half a package has no price, only the bundle\'s "from" price', () {
      final quote = BundleQuote.of(bundle, BundleChoice.initial(bundle));

      expect(quote.total, isNull);
      expect(quote.saving, isNull);
      expect(bundle.minFinal, _aed(39.6));
    });

    test('quantities count', () {
      final choice = BundleChoice.initial(bundle)
          .choose(top, tee)
          .choose(mat, mat.selections.first)
          .withQuantity(bottle.selections.single, 4);
      final quote = BundleQuote.of(bundle, choice);

      // 20 + 18 + 4 × 3 = 50, not the cheapest package any more.
      expect(quote.exact, isFalse);
      expect(quote.regular, _aed(50));
      expect(quote.total, _aed(45));
    });
  });
}
