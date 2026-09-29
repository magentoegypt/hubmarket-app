import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/graphql/resilience_link.dart';

Request _query() =>
    Request(operation: Operation(document: gql('query Q { a }')));
Request _mutation() =>
    Request(operation: Operation(document: gql('mutation M { a }')));

Response _ok() => Response(data: const {'a': 1}, response: const {});
Response _authError() => Response(
  errors: const [
    GraphQLError(
      message: "The current customer isn't authorized.",
      extensions: {'category': 'graphql-authorization'},
    ),
  ],
  response: const {},
);

void main() {
  group('ResilienceLink', () {
    test('retries a transient query failure, then succeeds', () async {
      var calls = 0;
      final link = ResilienceLink(
        onAuthError: () {},
        initialBackoff: Duration.zero,
      );
      Stream<Response> forward(Request r) async* {
        calls++;
        if (calls < 3) throw TimeoutException('timed out');
        yield _ok();
      }

      final responses = await link.request(_query(), forward).toList();
      expect(calls, 3);
      expect(responses, hasLength(1));
    });

    test('gives up after maxAttempts and rethrows', () async {
      var calls = 0;
      final link = ResilienceLink(
        onAuthError: () {},
        maxAttempts: 2,
        initialBackoff: Duration.zero,
      );
      Stream<Response> forward(Request r) async* {
        calls++;
        throw TimeoutException('still down');
      }

      await expectLater(
        link.request(_query(), forward).toList(),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 2);
    });

    test('never retries a mutation, even on a transient error', () async {
      var calls = 0;
      final link = ResilienceLink(
        onAuthError: () {},
        initialBackoff: Duration.zero,
      );
      Stream<Response> forward(Request r) async* {
        calls++;
        throw TimeoutException('timed out');
      }

      await expectLater(
        link.request(_mutation(), forward).toList(),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1, reason: 'mutations must not be re-sent');
    });

    test('does not retry a non-transient query error', () async {
      var calls = 0;
      final link = ResilienceLink(
        onAuthError: () {},
        initialBackoff: Duration.zero,
      );
      Stream<Response> forward(Request r) async* {
        calls++;
        throw Exception('400 bad request');
      }

      await expectLater(
        link.request(_query(), forward).toList(),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    });

    test('invokes onAuthError when the response carries an auth error', () async {
      var triggered = 0;
      final link = ResilienceLink(
        onAuthError: () => triggered++,
        initialBackoff: Duration.zero,
      );
      Stream<Response> forward(Request r) async* {
        yield _authError();
      }

      final responses = await link.request(_query(), forward).toList();
      expect(triggered, 1);
      expect(responses, hasLength(1)); // response still passes through
    });

    test('does not flag a clean response as an auth error', () async {
      var triggered = 0;
      final link = ResilienceLink(
        onAuthError: () => triggered++,
        initialBackoff: Duration.zero,
      );
      Stream<Response> forward(Request r) async* {
        yield _ok();
      }

      await link.request(_query(), forward).toList();
      expect(triggered, 0);
    });

    test('invokes onAuthError when a thrown ServerException carries an auth '
        'error (Magento 401), then rethrows', () async {
      var triggered = 0;
      final link = ResilienceLink(
        onAuthError: () => triggered++,
        maxAttempts: 2,
        initialBackoff: Duration.zero,
      );
      var calls = 0;
      Stream<Response> forward(Request r) async* {
        calls++;
        throw const ServerException(
          statusCode: 401,
          parsedResponse: Response(
            response: {},
            errors: [
              GraphQLError(
                message: 'Consumer key has expired',
                extensions: {'category': 'graphql-authentication'},
              ),
            ],
          ),
        );
      }

      await expectLater(
        link.request(_query(), forward).toList(),
        throwsA(isA<ServerException>()),
      );
      expect(triggered, 1, reason: 'stale token must be dropped to guest');
      expect(calls, 1, reason: 'an auth error is not transient — no retry');
    });
  });
}
