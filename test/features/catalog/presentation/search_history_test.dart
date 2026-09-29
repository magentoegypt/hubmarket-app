import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/catalog/presentation/search_history.dart';

import '../../../support/fakes.dart';

void main() {
  late FakeLocalCache cache;
  late ProviderContainer container;

  setUp(() async {
    cache = FakeLocalCache();
    await cache.writeString(
      'search_history',
      jsonEncode(['sofa bed', 'Office Desk', 'milk']),
    );
    container = ProviderContainer(
      overrides: [localCacheProvider.overrideWithValue(cache)],
    );
  });

  tearDown(() => container.dispose());

  List<String> stored() =>
      (jsonDecode(cache.readString('search_history')!) as List).cast<String>();

  test('remove drops one term, case-insensitively, and persists', () async {
    final history = container.read(searchHistoryProvider.notifier);

    await history.remove('office desk');

    expect(container.read(searchHistoryProvider), ['sofa bed', 'milk']);
    expect(stored(), ['sofa bed', 'milk']);
  });

  test('removing a term that is not there changes nothing', () async {
    final history = container.read(searchHistoryProvider.notifier);

    await history.remove('lamp');

    expect(container.read(searchHistoryProvider), [
      'sofa bed',
      'Office Desk',
      'milk',
    ]);
  });

  test('removing the last term clears the stored list', () async {
    final history = container.read(searchHistoryProvider.notifier);
    await history.remove('sofa bed');
    await history.remove('Office Desk');
    await history.remove('milk');

    expect(container.read(searchHistoryProvider), isEmpty);
    expect(cache.readString('search_history'), isNull);
  });

  test('add still puts the newest first without duplicates', () async {
    final history = container.read(searchHistoryProvider.notifier);

    await history.add('MILK');

    expect(container.read(searchHistoryProvider), [
      'MILK',
      'sofa bed',
      'Office Desk',
    ]);
  });
}
