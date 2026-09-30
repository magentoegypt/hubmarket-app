import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/graphql/possible_types.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';

/// Test doubles for the Hub Market App foundation.
///
/// Fake the availability with one override:
///
/// ```dart
/// ProviderScope(overrides: [
///   hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
///   // or: hubAppOverride(const HubAppState.unavailable()),
///   //     hubAppOverride(const HubAppState.unknown()),
/// ], …)
/// ```
///
/// and answer the public (GET) client per operation name:
///
/// ```dart
/// publicGraphqlClientProvider.overrideWithValue(fakeHubAppClient({
///   'HmStores': {'hmStores': {...}},        // data
///   'HmStore': hubAppMissingResponse('hmStore'), // "Cannot query field"
/// })),
/// ```

/// An [HmAppConfig] with every section filled in, for store view `en`.
const HmAppConfig kSampleHmAppConfig = HmAppConfig(
  storeCode: 'en',
  locale: 'en_US',
  search: HmSearchConfig(
    hint: 'Search 20,000+ products',
    trendingTerms: ['iphone', 'abaya', 'rice'],
  ),
  contact: HmContactConfig(
    whatsappNumber: '+971501234567',
    whatsappUrl: 'https://wa.me/971501234567',
    phone: '+97145550000',
    email: 'care@hub-market.example',
    hours: 'Daily 9 am – 11 pm',
  ),
  features: {'returns': true, 'store_credit': false},
);

/// [kSampleHmAppConfig] on a server that lists its satellites: HubAppVendors
/// with the P3.1 fields (the store pages' extras, sellers on listing cards).
const HmAppConfig kVendorsHmAppConfig = HmAppConfig(
  storeCode: 'en',
  locale: 'en_US',
  search: HmSearchConfig(
    hint: 'Search 20,000+ products',
    trendingTerms: ['iphone', 'abaya', 'rice'],
  ),
  features: {'returns': true, 'store_credit': false},
  capabilities: {'vendors', 'bundle', 'returns', 'account'},
);

/// Replaces the probe with a fixed [state] (no request is made).
Override hubAppOverride(HubAppState state) =>
    hubAppProvider.overrideWith(() => FakeHubAppController(state));

/// A [HubAppController] that never probes: it starts at [initial] and counts
/// the refreshes screens ask for.
class FakeHubAppController extends HubAppController {
  FakeHubAppController(this.initial);

  final HubAppState initial;
  int refreshes = 0;

  @override
  Future<HubAppState> build() async => initial;

  @override
  Future<void> refresh() async {
    refreshes++;
    state = AsyncData(initial);
  }

  @override
  Future<void> retryIfUnknown() async {}

  @override
  Future<void> onResume() async {}

  @override
  Future<HmAlgoliaConfig?> algoliaFor(String storeCode) async =>
      initial.config?.storeCode == storeCode ? initial.config?.algolia : null;
}

/// The error Magento answers for a field the server doesn't have.
GraphQLError hubAppMissingError(String field, {String type = 'Query'}) =>
    GraphQLError(message: 'Cannot query field "$field" on type "$type".');

/// A response carrying only [hubAppMissingError] for [field].
Response hubAppMissingResponse(String field, {String type = 'Query'}) =>
    Response(
      errors: [hubAppMissingError(field, type: type)],
      response: const <String, dynamic>{},
    );

/// A GraphQL client answering by operation name: a `Map` is the `data`, a
/// [Response] is returned as is, an [Exception] fails the request (network),
/// and an operation with no entry fails like the network does.
///
/// Every request is recorded in [FakeHubAppClient.requests].
FakeHubAppClient fakeHubAppClient(Map<String, Object> answers) =>
    FakeHubAppClient(answers);

class FakeHubAppClient extends GraphQLClient {
  FakeHubAppClient(Map<String, Object> answers, {List<Request>? log})
    : this._(answers, log ?? <Request>[]);

  FakeHubAppClient._(Map<String, Object> answers, List<Request> log)
    : requests = log,
      super(
        link: Link.function((request, [forward]) {
          log.add(request);
          final name =
              request.operation.operationName ?? operationNameOf(request);
          final answer = answers[name];
          if (answer is Response) return Stream.value(answer);
          if (answer is Map<String, dynamic>) {
            return Stream.value(
              Response(data: answer, response: const <String, dynamic>{}),
            );
          }
          if (answer is Exception) return Stream.error(answer);
          return Stream.error(Exception('offline (test): $name'));
        }),
        // Canned data may leave out the `__typename`s the client adds.
        cache: GraphQLCache(
      partialDataPolicy: PartialDataCachePolicy.accept,
      possibleTypes: kPossibleTypes,
    ),
      );

  /// Every request sent, in order.
  final List<Request> requests;
}

/// The name of the first operation in [request]'s document.
String? operationNameOf(Request request) => request.operation.document
    .definitions
    .whereType<OperationDefinitionNode>()
    .firstOrNull
    ?.name
    ?.value;

/// [publicGraphqlClientProvider] answered by [answers] — see
/// [fakeHubAppClient].
Override publicClientOverride(Map<String, Object> answers) =>
    publicGraphqlClientProvider.overrideWithValue(fakeHubAppClient(answers));
