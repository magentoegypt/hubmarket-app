import 'package:graphql_flutter/graphql_flutter.dart';

import '../error/failure.dart';
import '../error/graphql_failure_mapper.dart';
import '../hubapp/hubapp_query.dart';

/// Every GraphQL error [exception] carries, a parsed non-200 body included.
List<GraphQLError> graphqlErrorsOf(OperationException exception) => [
  ...exception.graphqlErrors,
  if (exception.linkException case final ServerException server)
    ...?server.parsedResponse?.errors,
];

/// Runs an `hm*` operation that goes out as POST — a mutation, or a query
/// tied to the customer — and returns its `data`. [runHubAppQuery] is the
/// public (GET) counterpart.
///
/// [client] is the authenticated client for anything tied to the customer
/// (store credit, devices) and the token-less one for the anonymous sign-in
/// pair. Throws [HubAppMissing] when the server lacks what [document] asks
/// for, and otherwise a [Failure] — from [mapFailure] when given, else
/// [mapOperationException], as the repositories' own helpers do.
///
/// Declare no variables of `Hm*` types in [document]: while a module is
/// missing Magento answers a variable of an unknown type with HTTP 500
/// instead of "Cannot query field", and a missing module would look like an
/// outage. Inline input objects and enum values around scalar variables.
Future<Map<String, dynamic>> runHubAppOperation(
  GraphQLClient client,
  String document, {
  Map<String, dynamic> variables = const <String, dynamic>{},
  bool mutation = false,
  Failure Function(OperationException exception)? mapFailure,
}) async {
  final QueryResult result;
  try {
    result = mutation
        ? await client.mutate(
            MutationOptions(
              document: gql(document),
              variables: variables,
              fetchPolicy: FetchPolicy.networkOnly,
            ),
          )
        : await client.query(
            QueryOptions(
              document: gql(document),
              variables: variables,
              fetchPolicy: FetchPolicy.networkOnly,
            ),
          );
  } on Failure {
    rethrow;
  } catch (error) {
    throw Failure(FailureKind.unknown, detail: error.toString());
  }
  final exception = result.exception;
  if (exception != null) {
    if (isHubAppMissing(exception)) {
      throw HubAppMissing(graphqlErrorsOf(exception).first.message);
    }
    throw (mapFailure ?? mapOperationException)(exception);
  }
  return result.data ?? const <String, dynamic>{};
}
