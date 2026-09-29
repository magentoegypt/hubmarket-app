import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';

/// Outcome of a newsletter sign-up.
///
/// Magento returns `SUBSCRIBED` when the address goes live immediately, and
/// `UNCONFIRMED` when the store has double opt-in enabled (Stores →
/// Configuration → Customers → Newsletter → "Need to Confirm"). In the second
/// case a confirmation email is on its way and the user is **not** subscribed
/// yet, so the two must not share a success message.
enum NewsletterSubscription { subscribed, pendingConfirmation }

/// Subscribes an email address to the active store view's newsletter.
///
/// The `Store` header applied by the link chain scopes the subscription to the
/// right store view, so an Arabic-store sign-up lands on the Arabic list.
class NewsletterRepository {
  NewsletterRepository(this._client);

  final GraphQLClient _client;

  static const String _subscribeDoc = r'''
mutation SubscribeToNewsletter($email: String!) {
  subscribeEmailToNewsletter(email: $email) { status }
}''';

  /// Throws [Failure] when the sign-up did not take. Magento reports an already
  /// subscribed address, a malformed one, and a disabled newsletter module as
  /// GraphQL errors, so every non-success path arrives here as a throw.
  Future<NewsletterSubscription> subscribe(String email) async {
    final data = await _mutate(_subscribeDoc, {'email': email});
    final status =
        (data['subscribeEmailToNewsletter'] as Map<String, dynamic>?)?['status']
            as String?;
    return switch (status) {
      'SUBSCRIBED' => NewsletterSubscription.subscribed,
      'UNCONFIRMED' => NewsletterSubscription.pendingConfirmation,
      // `NOT_ACTIVE`, null, or anything the schema grows later. Treat it as a
      // failure rather than guessing: telling someone they're subscribed when
      // they aren't is the exact bug this repository was written to fix.
      _ => throw Failure(FailureKind.unknown, detail: 'status=$status'),
    };
  }

  Future<Map<String, dynamic>> _mutate(
    String document,
    Map<String, dynamic> variables,
  ) async {
    try {
      final result = await _client.mutate(
        MutationOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }
}

final newsletterRepositoryProvider = Provider<NewsletterRepository>(
  (ref) => NewsletterRepository(ref.watch(graphqlClientProvider)),
);
