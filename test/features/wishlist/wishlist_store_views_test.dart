import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_queries.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/features/wishlist/presentation/wishlist_controller.dart';

import '../../support/fakes.dart';
import '../../support/marketplace_fakes.dart';

// QA TC105 (CL036-TC105-QA01): products added to the wishlist in Arabic were
// not listed after switching to English, and the other way round, while the
// Wishlist tab's counter kept the right number.
//
// Magento stamps every wishlist item with the store view of the request that
// added it, and core 2.4.8-p5 (the live version) reads the list two ways:
//
//   Wishlist.items_v2  resolver WishlistItems          addStoreFilter(the store
//                      view of the request, i.e. the `Store` header)
//   Wishlist.items     resolver WishlistItemsResolver  addStoreFilter(every
//                      store view)            (deprecated, no paging)
//   Wishlist.items_count  Wishlist::getItemsCount()    the website's store views
//
// The app read `items_v2`. This file holds a Magento that answers that way, and
// the app against it.

/// A product's name in English and in Arabic: a product is read in the store
/// view of the request, so it comes back named in that store's language.
const _names = <String, (String, String)>{
  'SHIRT': ('Linen shirt', 'قميص كتان'),
  'VASE': ('Blue vase', 'مزهرية زرقاء'),
  'OUD': ('Oud perfume', 'عطر عود'),
  'LAMP': ('Table lamp', 'مصباح طاولة'),
};

class _Item {
  _Item(this.id, this.sku, this.addedIn);

  final int id;
  final String sku;

  /// The store view of the request that added it (`wishlist_item.store_id`).
  final String addedIn;
}

/// Magento's wishlist, as far as these tests need it.
///
/// Besides the three reads above: a product is found, to be removed, whichever
/// store view it was added in (`Wishlist::getItem` looks over the website), and
/// adding a product the wishlist already holds raises its quantity instead of
/// making a second item.
class _Magento {
  _Magento(List<_Item> saved) : _saved = [...saved];

  final List<_Item> _saved;
  int _nextId = 100;

  /// The server as the app reaches it with `Store: [store]`.
  Object Function(Request, String) answerAs(String store) =>
      (request, document) => switch (rootFieldOf(request)) {
        'customer' => {
          'customer': {
            'wishlists': [_wishlist(document, store)],
          },
        },
        'addProductsToWishlist' => _add(request, document, store),
        'removeProductsFromWishlist' => _remove(request, document, store),
        final other => throw StateError('unexpected $other'),
      };

  Map<String, dynamic> _wishlist(String document, String store) {
    final scoped = document.contains('items_v2');
    final listed = [
      for (final item in _saved)
        if (!scoped || item.addedIn == store) _json(item, store),
    ];
    return {
      '__typename': 'Wishlist',
      'id': '7',
      'items_count': _saved.length,
      if (scoped) 'items_v2': {'items': listed} else 'items': listed,
    };
  }

  Map<String, dynamic> _json(_Item item, String store) {
    final (en, ar) = _names[item.sku]!;
    return {
      '__typename': 'WishlistItem',
      'id': item.id,
      'product': {
        '__typename': 'SimpleProduct',
        'sku': item.sku,
        'name': store == 'ar' ? ar : en,
        'url_key': item.sku.toLowerCase(),
        'stock_status': 'IN_STOCK',
        'new_from_date': null,
        'new_to_date': null,
        'rating_summary': 0,
        'review_count': 0,
        'image': null,
        'price_range': {
          'minimum_price': {
            'regular_price': {'value': 10, 'currency': 'AED'},
            'final_price': {'value': 10, 'currency': 'AED'},
          },
        },
      },
    };
  }

  Map<String, dynamic> _add(Request request, String document, String store) {
    for (final line in request.variables['items'] as List) {
      final sku = (line as Map)['sku'] as String;
      if (_saved.every((item) => item.sku != sku)) {
        _saved.add(_Item(_nextId++, sku, store));
      }
    }
    return {
      'addProductsToWishlist': {
        'wishlist': _wishlist(document, store),
        'user_errors': <Object>[],
      },
    };
  }

  Map<String, dynamic> _remove(Request request, String document, String store) {
    final ids = [
      for (final id in request.variables['itemIds'] as List) int.parse('$id'),
    ];
    _saved.removeWhere((item) => ids.contains(item.id));
    return {
      'removeProductsFromWishlist': {
        'wishlist': _wishlist(document, store),
        'user_errors': <Object>[],
      },
    };
  }
}

/// One saved in English, two in Arabic.
_Magento _wishlistOfBothLanguages() => _Magento([
  _Item(1, 'SHIRT', 'en'),
  _Item(2, 'VASE', 'ar'),
  _Item(3, 'OUD', 'ar'),
]);

List<String> _skus(WishlistData data) => [
  for (final entry in data.entries) entry.product.sku,
];

List<String> _namesOf(WishlistData data) => [
  for (final entry in data.entries) entry.product.name,
];

void main() {
  group('the wishlist documents', () {
    final documents = <String, String>{
      'Wishlist': WishlistQueries.getWishlist,
      'AddToWishlist': WishlistQueries.addToWishlist,
      'RemoveFromWishlist': WishlistQueries.removeFromWishlist,
    };

    documents.forEach((name, document) {
      test('$name asks for every item, not the ones of the request\'s store '
          'view', () {
        expect(document, contains('items {'));
        expect(document, isNot(contains('items_v2')));
        // The counter is still the store's own.
        expect(document, contains('items_count'));
      });
    });
  });

  group('WishlistRepository', () {
    test('lists what was saved under either language, in whichever one is '
        'asked', () async {
      final magento = _wishlistOfBothLanguages();

      for (final store in ['en', 'ar']) {
        final repository = WishlistRepository(
          RecordingGraphQLClient(magento.answerAs(store)).client,
        );
        final data = (await repository.fetchWishlist())!;

        expect(_skus(data), ['SHIRT', 'VASE', 'OUD'], reason: 'under $store');
        expect(data.itemsCount, 3);
        // The names are those of the language asked for.
        expect(
          _namesOf(data),
          store == 'ar'
              ? ['قميص كتان', 'مزهرية زرقاء', 'عطر عود']
              : ['Linen shirt', 'Blue vase', 'Oud perfume'],
          reason: 'under $store',
        );
      }
    });

    test('removes an item that was saved under the other language', () async {
      final magento = _wishlistOfBothLanguages();
      final english = WishlistRepository(
        RecordingGraphQLClient(magento.answerAs('en')).client,
      );

      // VASE (item 2) was saved under `ar`.
      final data = await english.removeItem('7', '2');

      expect(_skus(data), ['SHIRT', 'OUD']);
      expect(data.itemsCount, 2);
    });
  });

  group('WishlistController across a language switch', () {
    late _Magento magento;
    late List<RecordingGraphQLClient> servers;
    late ProviderContainer container;

    /// The app, signed in, with a client per store view as the real
    /// `graphqlClientProvider` makes one: rebuilt, cache and `Store` header
    /// included, when the active store changes.
    Future<void> signedIn() async {
      container = ProviderContainer(
        overrides: [
          secureTokenStoreProvider.overrideWithValue(
            FakeSecureTokenStore(null),
          ),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs(null)),
          wishlistRepositoryProvider.overrideWith((ref) {
            final store = ref.watch(
              storeControllerProvider.select((s) => s.activeStoreCode),
            );
            final server = RecordingGraphQLClient(magento.answerAs(store));
            servers.add(server);
            return WishlistRepository(server.client);
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(wishlistControllerProvider, (_, __) {});
      container.listen(authControllerProvider, (_, __) {});

      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      await pumpEventQueue();
    }

    Future<void> switchTo(String locale) async {
      await container
          .read(storeControllerProvider.notifier)
          .switchLocale(locale);
      await pumpEventQueue();
    }

    WishlistState state() => container.read(wishlistControllerProvider);

    List<String> requests() => [
      for (final server in servers)
        for (final request in server.requests) rootFieldOf(request),
    ];

    setUp(() {
      magento = _wishlistOfBothLanguages();
      servers = [];
    });

    test('lists the same products in English and in Arabic, each named in '
        'its own language, and the counter agrees', () async {
      await signedIn();
      expect(state().entries.map((e) => e.product.sku), [
        'SHIRT',
        'VASE',
        'OUD',
      ]);
      expect(state().entries.map((e) => e.product.name).first, 'Linen shirt');
      expect(state().count, 3);

      await switchTo('ar');
      expect(state().entries.map((e) => e.product.sku), [
        'SHIRT',
        'VASE',
        'OUD',
      ]);
      expect(state().entries.map((e) => e.product.name).first, 'قميص كتان');
      expect(state().count, 3);

      await switchTo('en');
      expect(state().entries, hasLength(3));
      expect(state().entries.map((e) => e.product.name).first, 'Linen shirt');
      expect(state().count, 3);
    });

    test('a product saved in Arabic shows as saved in English', () async {
      await signedIn();
      await switchTo('ar');
      await container.read(wishlistControllerProvider.notifier).toggle('LAMP');
      expect(state().contains('LAMP'), isTrue);
      expect(state().count, 4);

      await switchTo('en');
      expect(state().contains('LAMP'), isTrue);
      expect(state().entries, hasLength(4));
      expect(state().count, 4);
    });

    test('the heart of a product saved in the other language takes it off, '
        'instead of adding it a second time', () async {
      await signedIn();
      expect(state().contains('VASE'), isTrue);

      // VASE was saved under `ar`; the app is in English.
      await container.read(wishlistControllerProvider.notifier).toggle('VASE');

      expect(state().contains('VASE'), isFalse);
      expect(state().entries, hasLength(2));
      expect(state().count, 2);
      expect(requests(), isNot(contains('addProductsToWishlist')));
      expect(requests(), contains('removeProductsFromWishlist'));

      await switchTo('ar');
      expect(state().contains('VASE'), isFalse);
      expect(state().count, 2);
    });
  });
}
