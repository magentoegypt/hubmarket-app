import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/search_facets.dart';
import 'package:hubmarket_app/features/stores/domain/store.dart';
import 'package:hubmarket_app/features/stores/presentation/search_vendors.dart';
import 'package:hubmarket_app/features/stores/presentation/stores_providers.dart';

import '../../../support/search_fixtures.dart';
import '../../../support/store_fixtures.dart';

HmStoreCard _card(Map<String, dynamic> json) => HmStoreCard.fromJson(json)!;

void main() {
  final cards = [for (final json in sampleStoreCards()) _card(json)];
  final mia = cards[0];
  final loly = cards[1];
  final enara = cards[2];

  group('sellerFacetCounts', () {
    test('reads the seller facet by display name, zero counts dropped', () {
      expect(
        sellerFacetCounts(const [
          Aggregation(attributeCode: 'color', label: 'Color', options: []),
          Aggregation(
            attributeCode: 'seller',
            label: 'Seller',
            options: [
              AggregationOption(label: 'MIA CO', value: 'MIA CO', count: 8),
              AggregationOption(label: 'ENARA', value: 'ENARA', count: 0),
            ],
          ),
        ]),
        {'MIA CO': 8},
      );
      expect(sellerFacetCounts(const []), isEmpty);
    });
  });

  group('searchVendorsFrom', () {
    test('name matches first, then the sellers of the matches by count', () {
      final vendors = searchVendorsFrom(
        nameMatches: [enara],
        directory: cards,
        sellerCounts: {'loly store': 2, 'MIA CO': 8, 'ENARA': 1},
      );
      expect(vendors.map((v) => v.store.code), ['ENARA', 'MIA', 'loly']);
      expect(vendors.map((v) => v.matchCount), [1, 8, 2]);
      expect(vendors.map((v) => v.nameMatch), [true, false, false]);
    });

    test('facet names match the directory whatever their case or spacing', () {
      final vendors = searchVendorsFrom(
        nameMatches: const [],
        directory: cards,
        sellerCounts: {' mia co ': 3},
      );
      expect(vendors.single.store, same(mia));
      expect(vendors.single.matchCount, 3);
    });

    test('a seller the directory does not know is dropped', () {
      final vendors = searchVendorsFrom(
        nameMatches: const [],
        directory: [loly],
        sellerCounts: {'Closed Shop': 5, 'loly store': 1},
      );
      expect(vendors.map((v) => v.store.code), ['loly']);
    });

    test('without the facet (GraphQL fallback) only name matches are found', () {
      final vendors = searchVendorsFrom(nameMatches: [mia]);
      expect(vendors.single.store.code, 'MIA');
      expect(vendors.single.matchCount, isNull);
    });
  });

  group('mostSpecificCategories', () {
    SearchCategory category(String uid, String name) =>
        SearchCategory(uid: uid, name: name, count: 1);

    test('drops a category when one below it is listed', () {
      final result = mostSpecificCategories([
        category(kFurnitureUid, 'Furniture'),
        category(kHomeFurnitureUid, 'Home Furniture'),
        category('MTQw', 'Fashion'),
        category(kLivingRoomUid, 'Living Room Sets'),
      ], kSearchTree);
      expect(result.map((c) => c.name), [
        'Home Furniture',
        'Fashion',
        'Living Room Sets',
      ]);
    });

    test('keeps a parent listed alone', () {
      final result = mostSpecificCategories([
        category(kFurnitureUid, 'Furniture'),
      ], kSearchTree);
      expect(result.map((c) => c.name), ['Furniture']);
    });
  });

  group('StoreListQuery', () {
    test('equal when they ask the same, the name trimmed', () {
      expect(
        const StoreListQuery(categoryId: 74, name: ' mia ', sort: StoreSort.name),
        const StoreListQuery(categoryId: 74, name: 'mia', sort: StoreSort.name),
      );
      expect(
        const StoreListQuery(name: ''),
        const StoreListQuery(),
      );
      expect(
        const StoreListQuery(sort: StoreSort.topRated),
        isNot(const StoreListQuery()),
      );
    });

    test('an empty name is no filter', () {
      expect(const StoreListQuery(name: '  ').toVariables(), {
        'featured': null,
        'categoryId': null,
        'name': null,
      });
    });
  });

  group('StoreCardX', () {
    test('the logo placeholder shows the first letter', () {
      expect(mia.initial, 'M');
      expect(_card(storeCardJson(code: 'x', id: 1, name: 'متجر لولي')).initial, 'م');
    });
  });
}
