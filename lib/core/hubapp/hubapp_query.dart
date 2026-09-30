import 'dart:async';

import 'package:graphql_flutter/graphql_flutter.dart';

import '../error/failure.dart';
import '../error/graphql_failure_mapper.dart';

/// The server doesn't have the `hm*` fields or types a document asked for:
/// the Hub Market App module (or the satellite that owns them) isn't deployed
/// there. Features fall back to what they did before it existed.
///
/// Distinct from a [Failure]: a network or server error says nothing about
/// whether the module exists, so it must never be read as "not deployed".
class HubAppMissing implements Exception {
  const HubAppMissing(this.message);

  /// The server's first validation message, e.g.
  /// `Cannot query field "hmAppConfig" on type "Query".`
  final String message;

  @override
  String toString() => 'HubAppMissing($message)';
}

/// Whether [missing] says the root field [field] itself is unknown — the
/// module that owns it isn't deployed — rather than one of its arguments,
/// sub-fields or types (an older build of the module).
bool isMissingRootField(HubAppMissing missing, String field) =>
    missing.message.contains('Cannot query field "$field" on type "Query"') ||
    missing.message.contains('Cannot query field "$field" on type "Mutation"');

/// Validation messages that mean "this schema has no such field / type /
/// argument". Magento answers them with HTTP 200 and no `extensions.category`
/// in production mode, so the message is all there is to go on.
final RegExp _schemaMissing = RegExp(
  r'^(Cannot query field|Unknown type|Unknown argument)\b',
);

/// Whether [error] is a schema-validation error of the kind [HubAppMissing]
/// stands for.
bool isSchemaMissingError(GraphQLError error) =>
    _schemaMissing.hasMatch(error.message.trim());

/// Whether [exception] says the queried hm* schema isn't on the server — every
/// GraphQL error it carries is [isSchemaMissingError] (a parsed non-200 body
/// counts too).
bool isHubAppMissing(OperationException exception) {
  final errors = <GraphQLError>[
    ...exception.graphqlErrors,
    if (exception.linkException case final ServerException server)
      ...?server.parsedResponse?.errors,
  ];
  return errors.isNotEmpty && errors.every(isSchemaMissingError);
}

/// Runs a public `hm*` read — through `publicGraphqlClientProvider` (GET,
/// token-less, `Store` header) — and returns its `data`.
///
/// Throws [HubAppMissing] when the server lacks what [document] asks for, a
/// [Failure] for everything else (network, edge, server errors), exactly as
/// the repositories' own `_query` helpers do. [timeout] bounds the whole
/// call, retries included.
///
/// **Declare no variables of `Hm*` types** (`$p: HmPlatform`,
/// `$f: HmStoreFilterInput`, …): while a module is missing, Magento answers a
/// variable of an unknown type with HTTP 500 "Internal server error" instead
/// of "Cannot query field", and the missing module then looks like an outage.
/// Inline enum and input values, or use scalar variables.
Future<Map<String, dynamic>> runHubAppQuery(
  GraphQLClient client,
  String document, {
  Map<String, dynamic> variables = const <String, dynamic>{},
  Duration? timeout,
}) async {
  final QueryResult result;
  try {
    final pending = client.query(
      QueryOptions(
        document: gql(document),
        variables: variables,
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    result = timeout == null ? await pending : await pending.timeout(timeout);
  } on TimeoutException catch (error) {
    throw Failure(FailureKind.network, detail: 'timed out: $error');
  } on Failure {
    rethrow;
  } catch (error) {
    throw Failure(FailureKind.unknown, detail: error.toString());
  }
  final exception = result.exception;
  if (exception != null) {
    if (isHubAppMissing(exception)) {
      final first = [
        ...exception.graphqlErrors,
        if (exception.linkException case final ServerException server)
          ...?server.parsedResponse?.errors,
      ].first;
      throw HubAppMissing(first.message);
    }
    throw mapOperationException(exception);
  }
  return result.data ?? const <String, dynamic>{};
}
