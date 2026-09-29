import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/newsletter/data/newsletter_repository.dart';

import '../../support/fakes.dart';

/// A client that answers every request with `subscribeEmailToNewsletter` set to
/// [status], so each branch of the status mapping can be driven directly.
GraphQLClient _clientReturning(String? status) => GraphQLClient(
  link: Link.function(
    (request, [forward]) => Stream<Response>.value(
      Response(
        // `__typename` is present because graphql_flutter injects it into every
        // document, so a faithful fake has to carry it — the normalizing cache
        // rejects the response without it.
        data: <String, dynamic>{
          '__typename': 'Mutation',
          'subscribeEmailToNewsletter': <String, dynamic>{
            '__typename': 'SubscribeEmailToNewsletterOutput',
            'status': status,
          },
        },
        response: const <String, dynamic>{},
        context: const Context(),
      ),
    ),
  ),
  cache: GraphQLCache(),
);

void main() {
  group('NewsletterRepository.subscribe', () {
    test('SUBSCRIBED means the address is live immediately', () async {
      final repo = NewsletterRepository(_clientReturning('SUBSCRIBED'));

      expect(
        await repo.subscribe('shopper@example.com'),
        NewsletterSubscription.subscribed,
      );
    });

    test('UNCONFIRMED means double opt-in — not subscribed yet', () async {
      // The store has "Need to Confirm" on, so a confirmation email is out and
      // the UI must say so rather than claiming success.
      final repo = NewsletterRepository(_clientReturning('UNCONFIRMED'));

      expect(
        await repo.subscribe('shopper@example.com'),
        NewsletterSubscription.pendingConfirmation,
      );
    });

    test('an unexpected status throws instead of reporting success', () async {
      // Regression guard for the bug this replaced: the footer used to confirm
      // a subscription that never happened. Anything that isn't an explicit
      // success must reach the user as a failure.
      for (final status in <String?>['NOT_ACTIVE', 'WHATEVER', null]) {
        final repo = NewsletterRepository(_clientReturning(status));
        await expectLater(
          repo.subscribe('shopper@example.com'),
          throwsA(isA<Failure>()),
          reason: 'status=$status must not be treated as a subscription',
        );
      }
    });

    test('a transport failure surfaces as a Failure', () async {
      final repo = NewsletterRepository(fakeGraphQLClient());

      await expectLater(
        repo.subscribe('shopper@example.com'),
        throwsA(isA<Failure>()),
      );
    });
  });
}
