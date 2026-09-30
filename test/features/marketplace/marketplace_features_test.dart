import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

/// The features a container sees with the HubApp probe in [state].
Future<ProviderContainer> _container(HubAppState state) async {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      hubAppOverride(state),
    ],
  );
  addTearDown(container.dispose);
  await container.read(hubAppProvider.future);
  return container;
}

HubAppState _available({Set<String>? capabilities}) => HubAppState.available(
  HmAppConfig(storeCode: 'en', capabilities: capabilities),
);

void main() {
  test(
    'a server listing HubAppVendors gets sellers on listing cards and the store extras',
    () async {
      final container = await _container(
        _available(capabilities: {'vendors', 'returns'}),
      );

      expect(
        container.read(marketplaceFeaturesProvider),
        const MarketplaceFeatures(
          sellers: true,
          listingSellers: true,
          storeExtras: true,
        ),
      );
    },
  );

  test('a satellite the server does not list is off from the start', () async {
    final container = await _container(_available(capabilities: {'bundle'}));

    expect(
      container.read(marketplaceFeaturesProvider),
      const MarketplaceFeatures(bundles: true),
    );
  });

  test(
    'a HubApp from before capabilities keeps the P3 behaviour, no listing sellers',
    () async {
      final container = await _container(_available());

      expect(
        container.read(marketplaceFeaturesProvider),
        const MarketplaceFeatures(sellers: true, bundles: true, packages: true),
      );
    },
  );

  test(
    'order packages need the orders capability once the server lists any',
    () async {
      final listed = await _container(
        _available(capabilities: {'orders', 'vendors'}),
      );
      final unlisted = await _container(_available(capabilities: {'vendors'}));

      expect(listed.read(marketplaceFeaturesProvider).packages, isTrue);
      expect(unlisted.read(marketplaceFeaturesProvider).packages, isFalse);
    },
  );

  test(
    'hm_packages turned down at run time switches only the packages off',
    () async {
      final container = await _container(
        _available(capabilities: {'orders', 'vendors', 'bundle'}),
      );

      container.read(marketplaceMissingProvider.notifier).packagesMissing();

      expect(
        container.read(marketplaceFeaturesProvider),
        const MarketplaceFeatures(
          sellers: true,
          bundles: true,
          listingSellers: true,
          storeExtras: true,
        ),
      );
    },
  );

  test(
    'hm_seller turned down at run time takes the listing sellers with it',
    () async {
      final container = await _container(_available(capabilities: {'vendors'}));

      container.read(marketplaceMissingProvider.notifier).sellersMissing();

      expect(
        container.read(marketplaceFeaturesProvider),
        MarketplaceFeatures.none,
      );
    },
  );

  test('without HubApp, nothing', () async {
    for (final state in [
      const HubAppState.unknown(),
      const HubAppState.unavailable(),
    ]) {
      final container = await _container(state);
      expect(
        container.read(marketplaceFeaturesProvider),
        MarketplaceFeatures.none,
      );
      expect(container.read(hubAppCapabilityProvider('vendors')), isFalse);
    }
  });
}
