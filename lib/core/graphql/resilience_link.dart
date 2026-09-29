import 'dart:async';

import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../error/graphql_failure_mapper.dart';

/// A terminating-adjacent link that adds two cross-cutting concerns to every
/// operation (CLAUDE.md §3.2 + §7):
///
/// 1. **Retry-with-backoff** on transient transport errors (timeouts, dropped
///    connections, 5xx / gateway / "temporarily unavailable"). Only **queries**
///    are retried — never mutations — so a lost response on `placeOrder` /
///    `addProductsToCart` can't double-submit.
/// 2. **Mid-session auth detection**: if a response carries a
///    `graphql-authorization`/`graphql-authentication` error, [onAuthError] is
///    invoked so the session can be dropped to guest immediately (Magento
///    returns these as HTTP 200 + an errors payload, so they never throw).
class ResilienceLink extends Link {
  ResilienceLink({
    required this.onAuthError,
    this.maxAttempts = 3,
    this.initialBackoff = const Duration(milliseconds: 400),
    this.requestTimeout = const Duration(seconds: 30),
  });

  /// Called (at most once per operation) when the response reports the token is
  /// no longer valid. Should be cheap/non-throwing — typically schedules a
  /// logout on a microtask.
  final void Function() onAuthError;

  /// Total attempts for a retryable (query) operation, including the first.
  final int maxAttempts;

  /// Base delay; doubles each retry (400ms → 800ms → 1600ms …).
  final Duration initialBackoff;

  /// Per-attempt response timeout. We own the request timeout here (consumed via
  /// `await for`, so a timeout is just a stream error we catch) instead of using
  /// graphql's `queryRequestTimeout`: that path completes a response `Completer`
  /// from an unguarded `listen(onData)`, so a retry's late response double-
  /// completes it → "Bad state: Future already completed" (graphql 5.2.4). The
  /// client passes `queryRequestTimeout: null` to disable it. 30s suits the
  /// CloudFront/WAF-fronted endpoint, where the old 5s default timed out
  /// checkout mutations (CLAUDE.md §7).
  final Duration requestTimeout;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    assert(forward != null, 'ResilienceLink must not be the terminating link');
    final retryable = _isQuery(request);
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        await for (final response in forward!(request).timeout(requestTimeout)) {
          if (_responseHasAuthError(response)) onAuthError();
          yield response;
        }
        return;
      } catch (error) {
        // Magento returns auth failures as HTTP 401 + an errors payload, which
        // graphql throws as a ServerException (it never reaches the yielded-
        // response check above). Detect the auth error here too so the stale
        // token is dropped to guest — otherwise every request keeps failing.
        if (_thrownHasAuthError(error)) onAuthError();
        if (!retryable || attempt >= maxAttempts || !_isTransient(error)) {
          rethrow;
        }
        await Future<void>.delayed(initialBackoff * (1 << (attempt - 1)));
      }
    }
  }

  static bool _isQuery(Request request) {
    for (final def in request.operation.document.definitions) {
      if (def is OperationDefinitionNode) {
        return def.type == OperationType.query;
      }
    }
    return false;
  }

  static bool _responseHasAuthError(Response response) {
    final errors = response.errors;
    if (errors == null || errors.isEmpty) return false;
    return errors.any(isAuthGraphqlError);
  }

  /// True when a *thrown* exception carries a parsed auth error — i.e. a
  /// ServerException from a non-200 (Magento 401) whose payload reports the
  /// token is invalid/expired (`graphql-authorization`/`graphql-authentication`).
  static bool _thrownHasAuthError(Object error) {
    if (error is ServerException) {
      final errors = error.parsedResponse?.errors;
      return errors != null && errors.any(isAuthGraphqlError);
    }
    return false;
  }

  /// String-based, version-robust transient detection (mirrors the failure
  /// mapper's defensive style). Auth/4xx/validation errors are NOT transient.
  static bool _isTransient(Object error) {
    if (error is TimeoutException) return true;
    final s = error.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('connection') ||
        s.contains('failed host lookup') ||
        s.contains('temporarily') ||
        s.contains('unavailable') ||
        s.contains('gateway') ||
        s.contains('500') ||
        s.contains('502') ||
        s.contains('503') ||
        s.contains('504');
  }
}
