import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/marketplace/domain/seller_groups.dart';

const _loly = HmSellerSummary(code: 'loly', name: 'loly store');
const _mia = HmSellerSummary(code: 'mia', name: 'MIA CO');
const _hub = HmSellerSummary(name: 'Hub Market', isMarketplace: true);

/// A line: its name and its seller.
typedef _Line = ({String name, HmSellerSummary? seller});

List<String> _names(SellerGroup<_Line> group) => [
  for (final line in group.items) line.name,
];

void main() {
  group('groupBySeller', () {
    test('groups by seller code, in first-seen order, keeping line order', () {
      final groups = groupBySeller<_Line>([
        (name: 'sofa', seller: _mia),
        (name: 'dress', seller: _loly),
        (name: 'chair', seller: _mia),
      ], (line) => line.seller)!;

      expect(groups.map((g) => g.seller?.code), ['mia', 'loly']);
      expect(_names(groups[0]), ['sofa', 'chair']);
      expect(_names(groups[1]), ['dress']);
    });

    test('is null when no line names a seller (HubApp not deployed)', () {
      expect(
        groupBySeller<_Line>([
          (name: 'sofa', seller: null),
          (name: 'dress', seller: null),
        ], (line) => line.seller),
        isNull,
      );
      expect(groupBySeller<_Line>(const [], (line) => line.seller), isNull);
    });

    test('puts every Hub Market line in one group', () {
      // A deleted seller's items come back as Hub Market too.
      const deletedSeller = HmSellerSummary(
        name: 'Hub Market',
        isMarketplace: true,
      );
      final groups = groupBySeller<_Line>([
        (name: 'kettle', seller: _hub),
        (name: 'dress', seller: _loly),
        (name: 'mug', seller: deletedSeller),
      ], (line) => line.seller)!;

      expect(groups, hasLength(2));
      expect(groups.first.seller!.isMarketplace, isTrue);
      expect(_names(groups.first), ['kettle', 'mug']);
    });

    test('lines without a seller go last, in a group of their own', () {
      final groups = groupBySeller<_Line>([
        (name: 'mystery', seller: null),
        (name: 'dress', seller: _loly),
      ], (line) => line.seller)!;

      expect(groups.map((g) => g.seller?.name), ['loly store', null]);
      expect(_names(groups.last), ['mystery']);
    });

    test('a seller known only by its link code still groups', () {
      const byLink = HmSellerSummary(
        name: 'moo store',
        link: HmLink(
          type: HmLinkType.store,
          url: 'https://hub-market.magento2.click/en/shop/moo',
          code: 'moo',
        ),
      );
      final groups = groupBySeller<_Line>([
        (name: 'a', seller: byLink),
        (name: 'b', seller: byLink),
      ], (line) => line.seller)!;

      expect(groups.single.items, hasLength(2));
      expect(byLink.storeCode, 'moo');
    });
  });

  group('storeCode', () {
    test('is the seller code, and null for Hub Market', () {
      expect(_loly.storeCode, 'loly');
      expect(_hub.storeCode, isNull);
    });
  });
}
