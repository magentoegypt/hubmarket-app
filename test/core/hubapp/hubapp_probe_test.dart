import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/network/connectivity.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import 'hubapp_fixtures.dart';

/// A container whose public client answers `HmAppConfig` from [answers]
/// (mutable: tests change the server between probes).
ProviderContainer _container(
  Map<String, Object> answers, {
  List<Request>? log,
  Stream<bool> Function()? network,
}) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      networkStatusSourceProvider.overrideWithValue(
        network ?? () => Stream<bool>.value(true),
      ),
      publicGraphqlClientProvider.overrideWithValue(
        FakeHubAppClient(answers, log: log),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Map<String, Object> _deployed() => {
  'HmAppConfig': {'hmAppConfig': hmAppConfigJson()},
};

void main() {
  group('the HubApp probe', () {
    test('an hmAppConfig answer means available, with the settings', () async {
      final container = _container(_deployed());

      final state = await container.read(hubAppProvider.future);

      expect(state.status, HubAppStatus.available);
      expect(container.read(hubAppStatusProvider), HubAppStatus.available);
      final config = container.read(hmAppConfigProvider)!;
      expect(config.storeCode, 'en');
      expect(config.search.hint, 'Search Hub Market');
      expect(container.read(hubAppFlagProvider('returns')), isTrue);
      expect(container.read(hubAppFlagProvider('store_credit')), isFalse);
      expect(container.read(hubAppFlagProvider('push')), isNull);
    });

    test('"Cannot query field" means unavailable (module not deployed)', () async {
      final container = _container({
        'HmAppConfig': hubAppMissingResponse('hmAppConfig'),
      });

      final state = await container.read(hubAppProvider.future);

      expect(state.status, HubAppStatus.unavailable);
      expect(state.error, isA<HubAppMissing>());
      expect(container.read(hmAppConfigProvider), isNull);
      expect(container.read(hubAppFlagProvider('returns')), isNull);
    });

    test('an older HubApp (no P3.1 fields) is still available, read with '
        'the P2 document', () async {
      final log = <Request>[];
      final container = _container({
        'HmAppConfig': hubAppMissingResponse('shipping', type: 'HmAppConfig'),
        'HmAppConfigP2': {'hmAppConfig': hmAppConfigJson()},
      }, log: log);

      final state = await container.read(hubAppProvider.future);

      expect(state.status, HubAppStatus.available);
      expect(log.map(operationNameOf), [
        'HmAppConfig',
        'HmAppConfigP2',
      ]);
      expect(state.config!.shipping.freeOver, isNull);
      expect(await container.read(freeShippingThresholdProvider.future), isNull);
      expect(
        HubAppConfigRepository.documentFor(
          HmPlatform.ios,
          base: HubAppConfigRepository.p2Document,
        ),
        allOf(contains('hmAppConfig(platform: IOS)'), isNot(contains('shipping'))),
      );
    });

    test('the free-shipping threshold is hmAppConfig.shipping.free_over, '
        'only while HubApp is available', () async {
      final container = _container({
        'HmAppConfig': {
          'hmAppConfig': hmAppConfigJson(
            shipping: {
              'free_over': {'value': 50, 'currency': 'AED'},
            },
          ),
        },
      });
      await container.read(hubAppProvider.future);
      expect(await container.read(freeShippingThresholdProvider.future), 50.0);

      final build1 = _container({
        'HmAppConfig': hubAppMissingResponse('hmAppConfig'),
      });
      await build1.read(hubAppProvider.future);
      expect(await build1.read(freeShippingThresholdProvider.future), isNull);
    });

    test('a network failure is unknown, and is not latched', () async {
      final answers = <String, Object>{
        'HmAppConfig': Exception('SocketException: Failed host lookup'),
      };
      final container = _container(answers);

      expect(
        (await container.read(hubAppProvider.future)).status,
        HubAppStatus.unknown,
      );
      expect(container.read(hubAppStatusProvider), HubAppStatus.unknown);

      // Back online: the next probe finds the module.
      answers['HmAppConfig'] = {'hmAppConfig': hmAppConfigJson()};
      await container.read(hubAppProvider.notifier).retryIfUnknown();

      expect(container.read(hubAppStatusProvider), HubAppStatus.available);
    });

    test('a server error (HTTP 500) is unknown, never unavailable', () async {
      final container = _container({
        'HmAppConfig': ServerException(
          parsedResponse: Response(
            errors: const [GraphQLError(message: 'Internal server error')],
            response: const <String, dynamic>{},
          ),
          statusCode: 500,
        ),
      });

      expect(
        (await container.read(hubAppProvider.future)).status,
        HubAppStatus.unknown,
      );
    });

    test('coming back online retries an unknown probe', () async {
      final answers = <String, Object>{'HmAppConfig': Exception('offline')};
      final network = StreamController<bool>();
      addTearDown(network.close);
      final container = _container(answers, network: () => network.stream);
      network.add(false);
      await container.read(hubAppProvider.future);
      expect(container.read(hubAppStatusProvider), HubAppStatus.unknown);

      answers['HmAppConfig'] = {'hmAppConfig': hmAppConfigJson()};
      network.add(true);
      await pumpEventQueue();

      expect(container.read(hubAppStatusProvider), HubAppStatus.available);
    });

    test('unavailable is settled until a store switch probes again', () async {
      final log = <Request>[];
      final answers = <String, Object>{
        'HmAppConfig': hubAppMissingResponse('hmAppConfig'),
      };
      final container = _container(answers, log: log);
      await container.read(hubAppProvider.future);

      // Neither coming back nor a retry-if-unknown re-asks a settled answer.
      await container.read(hubAppProvider.notifier).retryIfUnknown();
      expect(log, hasLength(1));

      answers['HmAppConfig'] = {
        'hmAppConfig': hmAppConfigJson(storeCode: 'ar'),
      };
      await container.read(storeControllerProvider.notifier).switchLocale('ar');
      final state = await container.read(hubAppProvider.future);

      expect(log, hasLength(2));
      expect(state.status, HubAppStatus.available);
      expect(state.config!.storeCode, 'ar');
    });

    test('sends the platform inline, never as an Hm-typed variable', () async {
      final log = <Request>[];
      final container = _container(_deployed(), log: log);
      await container.read(hubAppProvider.future);

      final request = log.single;
      expect(request.variables, isEmpty);
      expect(
        HubAppConfigRepository.documentFor(HmPlatform.ios),
        contains('hmAppConfig(platform: IOS)'),
      );
      expect(
        HubAppConfigRepository.documentFor(null),
        contains('hmAppConfig {'),
      );
      expect(HubAppConfigRepository.document, isNot(contains(r'$')));
    });

    test('algoliaFor re-reads the config when its key is expiring', () async {
      final until = DateTime.now().add(const Duration(minutes: 1));
      final answers = <String, Object>{
        'HmAppConfig': {
          'hmAppConfig': hmAppConfigJson(
            algolia: _algolia(until.millisecondsSinceEpoch ~/ 1000),
          ),
        },
      };
      final log = <Request>[];
      final container = _container(answers, log: log);
      await container.read(hubAppProvider.future);

      final fresh = DateTime.now().add(const Duration(hours: 23));
      answers['HmAppConfig'] = {
        'hmAppConfig': hmAppConfigJson(
          algolia: _algolia(fresh.millisecondsSinceEpoch ~/ 1000),
        ),
      };
      final algolia = await container
          .read(hubAppProvider.notifier)
          .algoliaFor('en');

      expect(log, hasLength(2));
      expect(algolia!.validUntil!.isAfter(until), isTrue);
      expect(
        await container.read(hubAppProvider.notifier).algoliaFor('ar'),
        isNull,
      );
    });
  });

  test('a missing module is its root field; anything else is an older one', () {
    expect(
      isMissingRootField(
        const HubAppMissing('Cannot query field "hmDeals" on type "Query".'),
        'hmDeals',
      ),
      isTrue,
    );
    for (final older in [
      'Unknown argument "category_id" on field "hmDeals" of type "Query".',
      'Cannot query field "categories" on type "HmProductPage".',
      'Cannot query field "product_count" on type "HmBrand".',
    ]) {
      expect(isMissingRootField(HubAppMissing(older), 'hmDeals'), isFalse);
    }
  });

  group('runHubAppQuery', () {
    test('HubAppMissing only when every error is a missing field', () async {
      final client = fakeHubAppClient({
        'HmStores': Response(
          errors: [
            hubAppMissingError('hmStores'),
            const GraphQLError(message: 'Unknown type "HmStoreSort".'),
          ],
          response: const <String, dynamic>{},
        ),
        'Mixed': Response(
          errors: [
            hubAppMissingError('hmStores'),
            const GraphQLError(message: 'Internal server error'),
          ],
          response: const <String, dynamic>{},
        ),
      });

      await expectLater(
        runHubAppQuery(client, 'query HmStores { hmStores { total_count } }'),
        throwsA(isA<HubAppMissing>()),
      );
      await expectLater(
        runHubAppQuery(client, 'query Mixed { hmStores { total_count } }'),
        throwsA(isNot(isA<HubAppMissing>())),
      );
    });
  });
}

Map<String, dynamic> _algolia(int validUntil) => {
  'application_id': 'HL67ED06DQ',
  'search_api_key': 'secured-key',
  'valid_until': validUntil,
  'index_prefix': 'hubmarket_',
  'product_index': 'hubmarket_en_products',
  'category_index': 'hubmarket_en_categories',
  'page_index': 'hubmarket_en_pages',
};
