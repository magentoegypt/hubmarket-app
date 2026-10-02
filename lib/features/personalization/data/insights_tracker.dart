import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/store/store_controller.dart';
import '../../catalog/data/algolia/algolia_settings.dart';
import '../../catalog/data/algolia/algolia_settings_repository.dart';
import '../../catalog/domain/money.dart';
import '../domain/insights_event.dart';
import 'insights_client.dart';
import 'personalization_identity.dart';
import 'product_object_ids.dart';

/// One product line the app tells Insights about: the SKU it knows, how many,
/// and the unit price when it has it.
class TrackedLine {
  const TrackedLine({required this.sku, required this.quantity, this.unitPrice});

  final String sku;
  final int quantity;
  final Money? unitPrice;
}

/// Tells Algolia Insights what the shopper does with products, under this
/// install's user token, so `hmPickedForYou` has a profile to rank from: a
/// product page viewed, a product tapped in a list, added to the cart or the
/// wishlist, and an order placed (the website's events, same names).
///
/// Every call returns at once and nothing it does can fail the caller: the
/// work (settings, product ids, the request) runs in the background, is
/// skipped when the shopper switched personalisation off in Settings, and a
/// failure only means one event less.
class InsightsTracker {
  InsightsTracker({
    required this.enabled,
    required this.settings,
    required this.token,
    required this.ids,
    required this.client,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Whether personalisation is on in Settings.
  final bool Function() enabled;

  /// Algolia's credentials and index for the active store view; null when
  /// there are none.
  final Future<AlgoliaSettings?> Function() settings;

  /// This install's user token.
  final String Function() token;
  final ProductObjectIds ids;
  final InsightsClient client;
  final DateTime Function() _clock;

  /// A page rebuilt, or opened twice in a row, is one view.
  static const Duration viewWindow = Duration(seconds: 30);
  final Map<String, DateTime> _lastView = <String, DateTime>{};

  /// A product page opened.
  void productViewed(String sku) {
    final now = _clock();
    final last = _lastView[sku];
    if (last != null && now.difference(last) < viewWindow) return;
    _lastView[sku] = now;
    _run([sku], (ids, _) => [if (ids[sku] case final id?) InsightsEvent.viewed(id)]);
  }

  /// A product tapped in a list or a search.
  void productClicked(String sku) => _run(
    [sku],
    (ids, _) => [if (ids[sku] case final id?) InsightsEvent.clicked(id)],
  );

  /// [quantity] of [sku] went into the cart, at [unitPrice] when known.
  void addedToCart(String sku, {int quantity = 1, Money? unitPrice}) => _run(
    [sku],
    (ids, settings) => [
      if (ids[sku] case final id?)
        InsightsEvent.addedToCart(
          [
            InsightsLine(
              objectId: id,
              quantity: quantity,
              unitPrice: unitPrice?.amount,
            ),
          ],
          unitPrice?.currency ?? settings.currencyCode,
        ),
    ],
  );

  /// [sku] went into the wishlist.
  void addedToWishlist(String sku) => _run(
    [sku],
    (ids, _) => [if (ids[sku] case final id?) InsightsEvent.addedToWishlist(id)],
  );

  /// The order of [lines] was placed.
  void orderPlaced(List<TrackedLine> lines) {
    if (lines.isEmpty) return;
    _run([for (final line in lines) line.sku], (ids, settings) {
      final known = [
        for (final line in lines)
          if (ids[line.sku] != null) line,
      ];
      if (known.isEmpty) return const <InsightsEvent>[];
      return [
        InsightsEvent.purchased(
          [
            for (final line in known)
              InsightsLine(
                objectId: ids[line.sku]!,
                quantity: line.quantity,
                unitPrice: line.unitPrice?.amount,
              ),
          ],
          known
                  .map((l) => l.unitPrice?.currency)
                  .whereType<String>()
                  .firstOrNull ??
              settings.currencyCode,
        ),
      ];
    });
  }

  void _run(
    List<String> skus,
    List<InsightsEvent> Function(Map<String, String> ids, AlgoliaSettings settings)
    build,
  ) {
    if (!enabled()) return;
    unawaited(_send(skus, build));
  }

  Future<void> _send(
    List<String> skus,
    List<InsightsEvent> Function(Map<String, String> ids, AlgoliaSettings settings)
    build,
  ) async {
    try {
      final algolia = await settings();
      if (algolia == null) return;
      final resolved = await ids.resolve(skus);
      if (resolved.isEmpty) return;
      // The switch may have been turned off while the ids were on their way.
      if (!enabled()) return;
      final at = _clock();
      final userToken = token();
      final payload = [
        for (final event in build(resolved, algolia))
          ...event.toJson(index: algolia.productsIndex, userToken: userToken, at: at),
      ];
      await client.send(
        appId: algolia.appId,
        apiKey: algolia.searchKey,
        events: payload,
      );
    } on Object {
      // Best effort: one event less.
    }
  }
}

/// The shopper's Insights events. Always the same tracker; it asks Settings
/// and the active store view when it sends, not when it is built.
final insightsTrackerProvider = Provider<InsightsTracker>((ref) {
  return InsightsTracker(
    enabled: () => ref.read(personalizationEnabledProvider),
    settings: () async {
      try {
        final storeCode = ref.read(storeControllerProvider).activeStoreCode;
        return await ref
            .read(algoliaSettingsRepositoryProvider)
            .settingsFor(storeCode);
      } on Object {
        return null;
      }
    },
    token: () => ref.read(personalizationTokenProvider),
    ids: ref.watch(productObjectIdsProvider),
    client: InsightsClient(
      ref.watch(algoliaHttpClientProvider),
      userAgent: ref.watch(appConfigProvider).userAgent,
    ),
  );
});

/// Tells the tracker from [tracker] about [event], and never lets telling go
/// wrong: a missing provider or a failure inside it costs one event, never
/// the cart add, the page or the order it was reported from.
void trackInsights(
  InsightsTracker Function() tracker,
  void Function(InsightsTracker tracker) event,
) {
  try {
    event(tracker());
  } on Object {
    // Tracking is an extra.
  }
}
