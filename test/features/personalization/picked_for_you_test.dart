import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/personalization/data/personalization_identity.dart';
import 'package:hubmarket_app/features/personalization/data/picked_for_you_repository.dart';
import 'package:hubmarket_app/features/personalization/domain/personal_picks.dart';
import 'package:hubmarket_app/features/personalization/presentation/personal_picks_provider.dart';

import '../../support/audit_pump.dart';
import '../../support/hubapp_fakes.dart';

Product _p(int n) => Product(sku: 'sku$n', name: 'Product $n', urlKey: 'p$n');

Map<String, dynamic> _item(String sku, String name) => {
  '__typename': 'ProductInterface',
  'sku': sku,
  'name': name,
  'url_key': sku.toLowerCase(),
  'stock_status': 'IN_STOCK',
  'new_from_date': null,
  'new_to_date': null,
  'rating_summary': 90,
  'review_count': 3,
  'image': {'__typename': 'ProductImage', 'url': 'https://hub-market.magento2.click/media/$sku.jpg'},
  'price_range': {
    '__typename': 'PriceRange',
    'minimum_price': {
      '__typename': 'ProductPrice',
      'regular_price': {'__typename': 'Money', 'value': 120, 'currency': 'AED'},
      'final_price': {'__typename': 'Money', 'value': 99, 'currency': 'AED'},
    },
  },
};

Map<String, dynamic> _answer({required bool personalized}) => {
  'hmPickedForYou': {
    '__typename': 'HmProductPage',
    'total_count': 2,
    'personalized': personalized,
    'items': [_item('BAG1', 'Canvas Handbag'), _item('BAG2', 'Leather Pouch')],
  },
};


/// A [PickedForYouRepository] that answers with [answer] (or throws it) and
/// remembers the tokens it was asked with.
class _FakePicksRepository extends PickedForYouRepository {
  _FakePicksRepository(this.answer) : super(FakeHubAppClient(const {}));

  final Object answer;
  final tokens = <String>[];

  @override
  Future<PersonalPicks> fetch(String userToken, {int pageSize = PickedForYouRepository.poolSize}) async {
    tokens.add(userToken);
    final value = answer;
    if (value is PersonalPicks) return value;
    throw value;
  }
}

ProviderContainer _container(_FakePicksRepository repository, {List<Override> more = const []}) {
  final container = ProviderContainer(
    overrides: auditOverrides(
      overrides: [pickedForYouRepositoryProvider.overrideWithValue(repository), ...more],
    ),
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('Refresh pages through the pool four at a time', () {
    final pool = [for (var i = 0; i < 16; i++) _p(i)];

    test('the first page is the first four', () {
      expect(pickedPage(pool, 0).map((p) => p.sku), ['sku0', 'sku1', 'sku2', 'sku3']);
    });

    test('each Refresh moves a page on and the last one wraps to the start', () {
      var offset = 0;
      final firsts = <String>[];
      for (var i = 0; i < 5; i++) {
        firsts.add(pickedPage(pool, offset).first.sku);
        offset = nextPickedOffset(offset, pool.length);
      }
      expect(firsts, ['sku0', 'sku4', 'sku8', 'sku12', 'sku0']);
    });

    test('a pool that is not a multiple of four still gives full pages', () {
      final ten = pool.take(10).toList();
      expect(pickedPage(ten, 8).map((p) => p.sku), ['sku8', 'sku9', 'sku0', 'sku1']);
      // every product comes round
      final seen = <String>{};
      var offset = 0;
      for (var i = 0; i < 10; i++) {
        seen.addAll(pickedPage(ten, offset).map((p) => p.sku));
        offset = nextPickedOffset(offset, ten.length);
      }
      expect(seen, hasLength(10));
    });

    test('a pool of four or fewer is shown whole and does not rotate', () {
      final four = pool.take(4).toList();
      expect(pickedPage(four, 0), four);
      expect(pickedPage(four, 7), four);
      expect(nextPickedOffset(0, 4), 0);
      expect(pickedPage(const <Product>[], 3), isEmpty);
    });
  });

  group('the user token', () {
    test('has the shape Algolia and hmPickedForYou accept', () {
      for (final good in ['hm-4f9k2x', 'seed-en-000', 'a', 'A_b=c+d/e.f-g', 'x' * 129]) {
        expect(isValidPersonalizationToken(good), isTrue, reason: good);
      }
      for (final bad in ['', ' ', 'has space', 'zqxq<svg/onload=alert(1)>', 'x' * 130, 'سلام']) {
        expect(isValidPersonalizationToken(bad), isFalse, reason: bad);
      }
    });

    test('a new one is valid, random and says nothing about the shopper', () {
      final a = newPersonalizationToken(Random(1));
      final b = newPersonalizationToken(Random(2));
      expect(isValidPersonalizationToken(a), isTrue);
      expect(a, startsWith('hm-'));
      expect(a, hasLength(35));
      expect(a, isNot(b));
      expect(newPersonalizationToken(), isNot(newPersonalizationToken()));
    });
  });

  group('hmPickedForYou', () {
    test('goes out with the token and the whole pool of 16 in one call', () async {
      final log = <Request>[];
      final repository = PickedForYouRepository(
        FakeHubAppClient({'HmPickedForYou': _answer(personalized: true)}, log: log),
      );

      final picks = await repository.fetch('hm-abc');

      expect(log.single.variables, {'token': 'hm-abc', 'pageSize': 16});
      expect(PickedForYouRepository.document, isNot(contains('HmPlatform')));
      expect(picks.personalized, isTrue);
      expect(picks.items.map((p) => p.sku), ['BAG1', 'BAG2']);
      expect(picks.items.first.name, 'Canvas Handbag');
    });

    test('says when the list is the generic top-rated one', () async {
      final repository = PickedForYouRepository(
        FakeHubAppClient({'HmPickedForYou': _answer(personalized: false)}),
      );
      expect((await repository.fetch('hm-new')).personalized, isFalse);
    });

    test('an answer it cannot read is empty and not personal', () {
      for (final junk in [null, 'x', <String, dynamic>{}, {'items': 5}]) {
        final picks = personalPicksFromJson(junk);
        expect(picks.items, isEmpty);
        expect(picks.personalized, isFalse);
      }
    });

    test('a server without the query says so', () async {
      final repository = PickedForYouRepository(
        FakeHubAppClient({
          'HmPickedForYou': Response(
            errors: const [
              GraphQLError(
                message: 'Cannot query field "hmPickedForYou" on type "Query".',
              ),
            ],
            response: const <String, dynamic>{},
          ),
        }),
      );
      await expectLater(repository.fetch('hm-abc'), throwsA(isA<HubAppMissing>()));
    });
  });

  group('personalPicksProvider', () {
    final personal = PersonalPicks(items: [_p(1), _p(2)], personalized: true);

    test('hands over the picks when the server says they are personal, asked '
        'with the token of this install', () async {
      final repository = _FakePicksRepository(personal);
      final container = _container(repository);

      final picks = await container.read(personalPicksProvider.future);

      expect(picks, same(personal));
      expect(repository.tokens, [container.read(personalizationTokenProvider)]);
      expect(isValidPersonalizationToken(repository.tokens.single), isTrue);
    });

    test('the token is made once and kept: the same one every time', () {
      final container = _container(_FakePicksRepository(personal));
      expect(
        container.read(personalizationTokenProvider),
        container.read(personalizationTokenProvider),
      );
    });

    test('is null for the generic top-rated list: never labelled personal', () async {
      final container = _container(
        _FakePicksRepository(PersonalPicks(items: [_p(1)], personalized: false)),
      );
      expect(await container.read(personalPicksProvider.future), isNull);
    });

    test('is null with nothing in it', () async {
      final container = _container(
        _FakePicksRepository(const PersonalPicks(items: [], personalized: true)),
      );
      expect(await container.read(personalPicksProvider.future), isNull);
    });

    test('is null, and nothing is asked, with personalisation off', () async {
      final repository = _FakePicksRepository(personal);
      final container = _container(repository);
      await container.read(personalizationEnabledProvider.notifier).set(false);

      expect(await container.read(personalPicksProvider.future), isNull);
      expect(repository.tokens, isEmpty);
    });

    test('is null on any failure: the section from the Home stands', () async {
      for (final failure in [Exception('offline'), const HubAppMissing('Cannot query field')]) {
        final container = _container(_FakePicksRepository(failure));
        expect(await container.read(personalPicksProvider.future), isNull);
      }
    });

    test('personalisation is on until the shopper turns it off, and stays off', () async {
      final container = _container(_FakePicksRepository(personal));
      expect(container.read(personalizationEnabledProvider), isTrue);
      await container.read(personalizationEnabledProvider.notifier).set(false);
      expect(container.read(personalizationEnabledProvider), isFalse);
    });
  });
}
