import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/data/guest_order_store.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/guest_orders_controller.dart';

import '../../support/fakes.dart';

/// Resolves guest orders the way `AccountRepository` does, and records which
/// lookup key was used so the token-first preference is observable.
class _FakeGuestRepo implements AccountRepository {
  _FakeGuestRepo({this.failFor = const <String>{}});

  /// Order numbers (or tokens) whose lookup should fail.
  final Set<String> failFor;
  final List<String> tokenLookups = <String>[];
  final List<String> detailLookups = <String>[];

  @override
  Future<CustomerOrder> fetchGuestOrderByToken(String token) async {
    tokenLookups.add(token);
    if (failFor.contains(token)) {
      throw const Failure(FailureKind.server, detail: 'no such entity');
    }
    return CustomerOrder(
      number: 'ORD-$token',
      status: 'Processing',
      date: '2026-01-01',
    );
  }

  @override
  Future<CustomerOrder> fetchGuestOrder({
    required String number,
    required String email,
    required String lastname,
  }) async {
    detailLookups.add(number);
    if (failFor.contains(number)) {
      throw const Failure(FailureKind.server, detail: 'no such entity');
    }
    return CustomerOrder(
      number: number,
      status: 'Complete',
      date: '2026-01-02',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(FakeLocalCache cache, AccountRepository repo) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(cache),
      accountRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<GuestOrdersState> _settled(ProviderContainer c) async {
  var state = c.read(guestOrdersControllerProvider);
  while (state.isLoading) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    state = c.read(guestOrdersControllerProvider);
  }
  return state;
}

void main() {
  group('GuestOrderStore', () {
    test('remembers, persists, and rehydrates', () async {
      final cache = FakeLocalCache();
      final container = _container(cache, _FakeGuestRepo());
      await container
          .read(guestOrderStoreProvider.notifier)
          .remember(const GuestOrderRef(number: '100', token: 'tok-100'));

      expect(container.read(guestOrderStoreProvider), hasLength(1));

      // A fresh container over the same cache sees the persisted entry.
      final reopened = _container(cache, _FakeGuestRepo());
      final refs = reopened.read(guestOrderStoreProvider);
      expect(refs.single.number, '100');
      expect(refs.single.token, 'tok-100');
    });

    test('de-dupes by order number, newest first, and caps the list', () async {
      final container = _container(FakeLocalCache(), _FakeGuestRepo());
      final store = container.read(guestOrderStoreProvider.notifier);
      for (var i = 0; i < 14; i++) {
        await store.remember(GuestOrderRef(number: '$i', token: 't$i'));
      }
      await store.remember(const GuestOrderRef(number: '13', token: 'again'));

      final refs = container.read(guestOrderStoreProvider);
      expect(refs, hasLength(10));
      expect(refs.first.number, '13');
      expect(refs.first.token, 'again');
      expect(refs.where((r) => r.number == '13'), hasLength(1));
    });

    test('ignores a ref with no usable lookup key', () async {
      final container = _container(FakeLocalCache(), _FakeGuestRepo());
      await container
          .read(guestOrderStoreProvider.notifier)
          .remember(const GuestOrderRef(number: '200'));
      expect(container.read(guestOrderStoreProvider), isEmpty);
    });

    test('an email + lastname pair is a usable key on its own', () async {
      final container = _container(FakeLocalCache(), _FakeGuestRepo());
      await container
          .read(guestOrderStoreProvider.notifier)
          .remember(
            const GuestOrderRef(
              number: '201',
              email: 'a@b.com',
              lastname: 'Test',
            ),
          );
      expect(container.read(guestOrderStoreProvider), hasLength(1));
    });

    test('a corrupt payload starts clean instead of throwing', () {
      final cache = FakeLocalCache();
      cache.writeString('guest_orders', 'not json');
      final container = _container(cache, _FakeGuestRepo());
      expect(container.read(guestOrderStoreProvider), isEmpty);
    });

    test('forget drops one entry and rewrites the payload', () async {
      final cache = FakeLocalCache();
      final container = _container(cache, _FakeGuestRepo());
      final store = container.read(guestOrderStoreProvider.notifier);
      await store.remember(const GuestOrderRef(number: '1', token: 'a'));
      await store.remember(const GuestOrderRef(number: '2', token: 'b'));

      await store.forget('1');
      expect(container.read(guestOrderStoreProvider).single.number, '2');
      final raw = jsonDecode(cache.readString('guest_orders')!) as List<dynamic>;
      expect(raw, hasLength(1));
    });
  });

  group('GuestOrdersController', () {
    test('resolves remembered orders, preferring the token', () async {
      final cache = FakeLocalCache();
      final repo = _FakeGuestRepo();
      final container = _container(cache, repo);
      await container
          .read(guestOrderStoreProvider.notifier)
          .remember(const GuestOrderRef(number: '100', token: 'tok'));
      await container
          .read(guestOrderStoreProvider.notifier)
          .remember(
            const GuestOrderRef(
              number: '101',
              email: 'a@b.com',
              lastname: 'Test',
            ),
          );
      container.listen(guestOrdersControllerProvider, (_, __) {});

      final state = await _settled(container);
      expect(state.orders.map((o) => o.number), containsAll(['ORD-tok', '101']));
      expect(state.unresolved, isEmpty);
      expect(repo.tokenLookups, ['tok']);
      expect(repo.detailLookups, ['101']);
    });

    test('keeps a ref that fails to resolve instead of deleting it', () async {
      final cache = FakeLocalCache();
      final repo = _FakeGuestRepo(failFor: {'bad'});
      final container = _container(cache, repo);
      final store = container.read(guestOrderStoreProvider.notifier);
      await store.remember(const GuestOrderRef(number: '1', token: 'ok'));
      await store.remember(const GuestOrderRef(number: '2', token: 'bad'));
      container.listen(guestOrdersControllerProvider, (_, __) {});

      final state = await _settled(container);
      expect(state.orders, hasLength(1));
      expect(state.unresolved.single.number, '2');
      // No screen-level error while something resolved.
      expect(state.error, isNull);
      // The dead ref is still persisted — only the user removes it.
      expect(container.read(guestOrderStoreProvider), hasLength(2));
    });

    test('surfaces a screen-level error when nothing resolves', () async {
      final repo = _FakeGuestRepo(failFor: {'bad'});
      final container = _container(FakeLocalCache(), repo);
      await container
          .read(guestOrderStoreProvider.notifier)
          .remember(const GuestOrderRef(number: '2', token: 'bad'));
      container.listen(guestOrdersControllerProvider, (_, __) {});

      final state = await _settled(container);
      expect(state.orders, isEmpty);
      expect(state.error, isA<Failure>());
    });

    test('lookup remembers the order it found', () async {
      final container = _container(FakeLocalCache(), _FakeGuestRepo());
      container.listen(guestOrdersControllerProvider, (_, __) {});
      await _settled(container);

      final order = await container
          .read(guestOrdersControllerProvider.notifier)
          .lookup(number: '555', email: 'a@b.com', lastname: 'Test');

      expect(order.number, '555');
      final refs = container.read(guestOrderStoreProvider);
      expect(refs.single.number, '555');
      expect(refs.single.email, 'a@b.com');
    });

    test('a failed lookup remembers nothing', () async {
      final container = _container(
        FakeLocalCache(),
        _FakeGuestRepo(failFor: {'404'}),
      );
      container.listen(guestOrdersControllerProvider, (_, __) {});
      await _settled(container);

      await expectLater(
        container
            .read(guestOrdersControllerProvider.notifier)
            .lookup(number: '404', email: 'a@b.com', lastname: 'Test'),
        throwsA(isA<Failure>()),
      );
      expect(container.read(guestOrderStoreProvider), isEmpty);
    });
  });
}
