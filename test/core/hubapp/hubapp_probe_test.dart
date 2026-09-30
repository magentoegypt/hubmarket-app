import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' show printNode;
import 'package:graphql_flutter/graphql_flutter.dart';
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

    test('asks for capabilities and reads them', () async {
      final log = <Request>[];
      final container = _container({
        'HmAppConfig': {
          'hmAppConfig': hmAppConfigJson(capabilities: ['bundle', 'vendors']),
        },
      }, log: log);

      await container.read(hubAppProvider.future);

      expect(printNode(log.single.operation.document), contains('capabilities'));
      expect(container.read(hubAppCapabilityProvider('vendors')), isTrue);
      expect(container.read(hubAppCapabilityProvider('returns')), isFalse);
    });

    test('a HubApp from before capabilities is asked again without them', () async {
      final sent = <String>[];
      final container = ProviderContainer(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          networkStatusSourceProvider.overrideWithValue(
            () => Stream<bool>.value(true),
          ),
          publicGraphqlClientProvider.overrideWithValue(
            GraphQLClient(
              link: Link.function((request, [forward]) {
                final document = printNode(request.operation.document);
                sent.add(document);
                return Stream.value(
                  document.contains('capabilities')
                      ? hubAppMissingResponse(
                          'capabilities',
                          type: 'HmAppConfig',
                        )
                      : Response(
                          data: {'hmAppConfig': hmAppConfigJson()},
                          response: const <String, dynamic>{},
                        ),
                );
              }),
              // Canned data leaves out the `__typename`s the client adds.
              cache: GraphQLCache(
                partialDataPolicy: PartialDataCachePolicy.accept,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(hubAppProvider.future);

      expect(sent, hasLength(2));
      expect(sent.last, isNot(contains('capabilities')));
      expect(state.status, HubAppStatus.available);
      expect(state.config!.capabilities, isNull);
      expect(container.read(hubAppCapabilityProvider('vendors')), isFalse);
    });

    test('without hmAppConfig itself the retry is not made', () async {
      final log = <Request>[];
      final container = _container({
        'HmAppConfig': hubAppMissingResponse('hmAppConfig'),
      }, log: log);

      final state = await container.read(hubAppProvider.future);

      expect(log, hasLength(1));
      expect(state.status, HubAppStatus.unavailable);
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
