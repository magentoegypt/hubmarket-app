import 'package:graphql_flutter/graphql_flutter.dart';

import 'failure.dart';

/// Maps a graphql_flutter [OperationException] to a domain [Failure].
///
/// Kept defensive (string-based link inspection) so it stays robust across
/// graphql_flutter point releases that rename concrete exception classes.
Failure mapOperationException(OperationException exception) {
  final linkException = exception.linkException;
  if (linkException != null) {
    // A link exception can still carry a *parsed* GraphQL response: Magento
    // returns auth failures (e.g. "Consumer key has expired",
    // `graphql-authentication`) as HTTP 401 + an errors payload, which graphql
    // wraps in a ServerException. Classify by those errors (auth/server) rather
    // than mistaking it for a transport/service failure — otherwise the stale
    // token is never cleared and every request keeps failing.
    if (linkException is ServerException) {
      final errors = linkException.parsedResponse?.errors;
      if (errors != null && errors.isNotEmpty) {
        if (errors.any(isAuthGraphqlError)) {
          return const Failure(FailureKind.auth);
        }
        return Failure(FailureKind.server, detail: errors.first.message);
      }
    }
    final raw = linkException.toString();
    final detail = raw.length > 400 ? '${raw.substring(0, 400)}…' : raw;
    final text = raw.toLowerCase();
    // Otherwise a non-JSON / HTML body (WAF, CloudFront error page, maintenance)
    // — or a response the transport couldn't decode into JSON — surfaces as a
    // parse/format failure. Keep the raw cause in `detail` so transport-specific
    // issues (e.g. an undecoded compressed body on iOS) stay diagnosable on the
    // connection-test screen.
    if (text.contains('format') ||
        text.contains('html') ||
        text.contains('<!doctype')) {
      return Failure(FailureKind.service, detail: detail);
    }
    return Failure(FailureKind.network, detail: detail);
  }

  final graphqlErrors = exception.graphqlErrors;
  if (graphqlErrors.isNotEmpty) {
    final isAuth = graphqlErrors.any(isAuthGraphqlError);
    if (isAuth) return const Failure(FailureKind.auth);
    return Failure(FailureKind.server, detail: graphqlErrors.first.message);
  }

  return const Failure(FailureKind.unknown);
}

/// True when a GraphQL error indicates the customer token is invalid/expired
/// (Magento returns these as a 200 + errors payload, category
/// `graphql-authorization`/`graphql-authentication`). Shared by the failure
/// mapper and the resilience link's mid-session logout trigger.
bool isAuthGraphqlError(GraphQLError error) {
  final category = error.extensions?['category'];
  if (category == 'graphql-authorization' ||
      category == 'graphql-authentication') {
    return true;
  }
  // Fall back to auth-SPECIFIC phrases only. A bare "token" match wrongly
  // classified unrelated errors — paymentSession(token:), cart/form/masked
  // tokens — as a session expiry, which then logged the customer out
  // mid-session. "consumer key" catches Magento's "Consumer key has expired".
  final message = error.message.toLowerCase();
  return message.contains('not authorized') ||
      message.contains('current customer') ||
      message.contains('not currently authenticated') ||
      message.contains('consumer key');
}
