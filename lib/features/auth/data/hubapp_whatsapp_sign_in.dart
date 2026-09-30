import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/hubapp_operation.dart';
import '../../../core/hubapp/hubapp.dart';

/// Sign-in by WhatsApp code over the Hub Market App backend
/// (`MagentoEgypt_HubAppAccount`): `hmSendWhatsAppCode`, then
/// `hmSignInWithWhatsAppCode`, which answers a customer token (the kind
/// `generateCustomerToken` returns). The app then merges the guest cart as
/// after any sign-in.
///
/// Both are anonymous, so they go out as POST through the token-less client:
/// a refused code is an authentication error, which on the token client would
/// read as an expired session.
abstract final class HubAppSignInQueries {
  static const String sendCode = r'''
mutation HmSendWhatsAppCode($mobile: String!) {
  hmSendWhatsAppCode(input: { mobile: $mobile }) {
    sent
    message
    resend_after_seconds
  }
}
''';

  static const String signIn = r'''
mutation HmSignInWithWhatsAppCode($mobile: String!, $code: String!) {
  hmSignInWithWhatsAppCode(input: { mobile: $mobile, code: $code }) { token }
}
''';
}

class HubAppWhatsAppSignIn {
  HubAppWhatsAppSignIn(this._client);

  /// The token-less (guest) client.
  final GraphQLClient _client;

  /// Sends a sign-in code to [mobile] (E.164) and returns the seconds before
  /// another may be asked for.
  ///
  /// The server answers alike for every number — whether or not an account
  /// has it — unless it is set to reveal unknown numbers. A request it turns
  /// down (`sent: false`: the per-number / per-address limits, or, revealing,
  /// no account / a number shared by several / a delivery failure) throws a
  /// `server` [Failure] with its (localized) message; [HubAppMissing] when the
  /// server doesn't have the module.
  Future<int?> sendCode(String mobile) async {
    final data = await runHubAppOperation(
      _client,
      HubAppSignInQueries.sendCode,
      variables: {'mobile': mobile},
      mutation: true,
      mapFailure: _refusal,
    );
    final answer = data['hmSendWhatsAppCode'] as Map<String, dynamic>?;
    if (answer == null) {
      throw const Failure(
        FailureKind.server,
        detail: 'hmSendWhatsAppCode is empty',
      );
    }
    if (answer['sent'] != true) {
      final message = (answer['message'] as String?)?.trim();
      throw Failure(
        FailureKind.server,
        detail: message == null || message.isEmpty ? null : message,
      );
    }
    return (answer['resend_after_seconds'] as num?)?.toInt();
  }

  /// Trades [code] for a customer token. Every refusal — a wrong or expired
  /// code, a locked account, no account — answers the same "incorrect or
  /// expired" error, kept as the [Failure]'s detail.
  Future<String> signIn(String mobile, String code) async {
    final data = await runHubAppOperation(
      _client,
      HubAppSignInQueries.signIn,
      variables: {'mobile': mobile, 'code': code},
      mutation: true,
      mapFailure: _refusal,
    );
    final token =
        (data['hmSignInWithWhatsAppCode'] as Map<String, dynamic>?)?['token'];
    if (token is! String || token.isEmpty) {
      throw const Failure(
        FailureKind.auth,
        detail: 'sign-in returned no token',
      );
    }
    return token;
  }

  /// This pair's refusals are worded for the customer: keep the message,
  /// which the shared mapper drops for authentication errors. Anything that
  /// never reached the resolver (network, edge) maps as usual.
  static Failure _refusal(OperationException exception) {
    final errors = graphqlErrorsOf(exception);
    if (errors.isEmpty) return mapOperationException(exception);
    final error = errors.first;
    return Failure(
      isAuthGraphqlError(error) ? FailureKind.auth : FailureKind.server,
      detail: error.message,
    );
  }
}
