import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../catalog/data/product_mapper.dart';
import '../../deals/data/deals_repository.dart';
import '../../marketplace/data/listing_sellers.dart';
import '../../marketplace/marketplace_features.dart';
import '../domain/personal_picks.dart';

/// `hmPickedForYou`: the Picked For You products for one shopper, ranked by
/// Algolia Personalization from the Insights events sent under their user
/// token. The answer depends on the token, so it is **not cached** and goes
/// out as a POST (the token-carrying client; the public GET client would put
/// the token in the URL and the full-page cache would serve it to others).
class PickedForYouRepository {
  PickedForYouRepository(
    this._client, {
    this._marketplace = const FixedMarketplaceGate(),
  });

  final GraphQLClient _client;
  final MarketplaceGate _marketplace;

  /// The most the query pages through, asked in one call: Refresh rotates the
  /// 16 four at a time on the phone instead of asking again.
  static const int poolSize = 16;

  static const String document = r'''
query HmPickedForYou($token: String!, $pageSize: Int!) {
  hmPickedForYou(user_token: $token, pageSize: $pageSize, currentPage: 1) {
    total_count
    personalized
    items { ...HmCardProduct }
  }
}
''';

  /// The picks for [userToken]. Throws [HubAppMissing] when the server has no
  /// `hmPickedForYou`, a `Failure` for a network or server error (a malformed
  /// token comes back as a `graphql-input` one).
  Future<PersonalPicks> fetch(String userToken, {int pageSize = poolSize}) async {
    final data = await sendListing(
      _marketplace,
      document + DealsFragments.cardProduct,
      (doc, _) => runHubAppQuery(
        _client,
        doc,
        variables: {'token': userToken, 'pageSize': pageSize},
      ),
    );
    return personalPicksFromJson(data['hmPickedForYou']);
  }
}

/// `hmPickedForYou` → [PersonalPicks]; nothing readable is an empty,
/// not-personal answer.
PersonalPicks personalPicksFromJson(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const PersonalPicks(items: [], personalized: false);
  }
  final items = json['items'];
  return PersonalPicks(
    items: [
      for (final item in items is List ? items : const [])
        if (item is Map<String, dynamic>) productFromJson(item),
    ],
    personalized: json['personalized'] == true,
  );
}

final pickedForYouRepositoryProvider = Provider<PickedForYouRepository>(
  (ref) => PickedForYouRepository(
    ref.watch(graphqlClientProvider),
    marketplace: ref.watch(marketplaceGateProvider),
  ),
);
