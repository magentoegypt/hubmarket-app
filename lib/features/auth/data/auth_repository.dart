import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/config/hubapp_account.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../domain/customer.dart';
import '../domain/password_reset_ticket.dart';
import 'auth_queries.dart';
import 'hubapp_whatsapp_sign_in.dart';
import 'otp_queries.dart';
import 'vnecoms_otp.dart';
import 'whatsapp_otp_api.dart';

class AuthRepository {
  AuthRepository(
    this._client,
    this._whatsapp, {
    HubAppWhatsAppSignIn? graphqlSignIn,
    void Function()? onGraphqlMissing,
  }) : _hubAppSignIn = graphqlSignIn,
       _onHubAppMissing = onGraphqlMissing;

  final GraphQLClient _client;

  /// REST transport for passwordless sign-in (Build 1) — SmsExtend's pair,
  /// which answers a verified code with a customer token.
  final WhatsAppOtpApi _whatsapp;

  /// The Hub Market App's GraphQL pair, when the server has it and its
  /// `whatsapp_login` switch is on; sign-in by code then goes through it.
  final HubAppWhatsAppSignIn? _hubAppSignIn;

  /// Told when the server turns out not to have the GraphQL pair after all.
  final void Function()? _onHubAppMissing;

  /// Returns a customer token. Throws [Failure] (auth) on bad credentials.
  Future<String> login(String email, String password) async {
    final data = await _mutate(AuthQueries.generateToken, {
      'email': email,
      'password': password,
    });
    final token =
        (data['generateCustomerToken'] as Map<String, dynamic>?)?['token']
            as String?;
    if (token == null || token.isEmpty) {
      throw const Failure(FailureKind.auth);
    }
    return token;
  }

  /// Creates the account with its WhatsApp-verified [mobileNumber] (E.164).
  ///
  /// The number goes out as `mobilenumber` on `createCustomer` — the backend
  /// requires it on every GraphQL sign-up (see [AuthQueries.createCustomer])
  /// and refuses one another account already holds. It does not re-check the
  /// code; the sign-up screen only creates the account once
  /// [verifyRegistrationOtp] has passed. [subscribeToNewsletter] is the
  /// Register form's "Send me offers" box (`is_subscribed`; the store's
  /// newsletter is enabled).
  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? mobileNumber,
    bool subscribeToNewsletter = false,
  }) async {
    await _mutate(AuthQueries.createCustomer, {
      'input': <String, dynamic>{
        'firstname': firstName,
        'lastname': lastName,
        'email': email,
        'password': password,
        if (mobileNumber != null && mobileNumber.isNotEmpty)
          'mobilenumber': mobileNumber,
        if (subscribeToNewsletter) 'is_subscribed': true,
      },
    });
  }

  // --- WhatsApp OTP ----------------------------------------------------------
  // Sign-in: the Hub Market App's GraphQL pair when the server has it, else
  // MagentoEgypt_SmsExtend REST (both return a token). Registration and
  // password reset: Vnecoms SMS GraphQL, the same flows the website runs.

  /// Sends a sign-in code and returns the seconds before another may be sent
  /// (null when the transport doesn't say). Throws [Failure] (`server`, with
  /// the store's message) when the send is refused — over REST also when no
  /// account holds the number; over GraphQL the answer is the same for every
  /// number unless the store reveals unknown ones.
  ///
  /// A refusal never falls back to REST: a limit must not be dodged by
  /// switching transport. Only a server without the GraphQL pair does.
  Future<int?> requestLoginOtp(String phone) async {
    final hubApp = _hubAppSignIn;
    if (hubApp != null) {
      try {
        return await hubApp.sendCode(phone);
      } on HubAppMissing {
        _onHubAppMissing?.call();
      }
    }
    await _whatsapp.sendLoginCode(phone);
    return null;
  }

  /// Verifies a sign-in code and returns the customer token. Throws [Failure]
  /// on a wrong / expired code.
  Future<String> loginWithOtp(String phone, String code) async {
    final hubApp = _hubAppSignIn;
    if (hubApp != null) {
      try {
        return await hubApp.signIn(phone, code);
      } on HubAppMissing {
        _onHubAppMissing?.call();
      }
    }
    return _whatsapp.verifyLoginCode(phone, code);
  }

  /// `customerRegisterSendOtp`. Throws [Failure] (`server`, with the store's
  /// message) when another account already holds the number.
  Future<void> requestRegistrationOtp(String phone, {bool resend = false}) async {
    final data = await _mutate(
      OtpQueries.registerSendOtp,
      VnecomsOtp.sendVariables(phone, resend: resend),
    );
    VnecomsOtp.requireSuccess(data['customerRegisterSendOtp']);
  }

  /// `customerRegisterVerifyOtp`. Throws [Failure] on a wrong / expired code so
  /// the UI keeps Create Account disabled.
  Future<void> verifyRegistrationOtp(String phone, String code) async {
    final data = await _mutate(
      OtpQueries.registerVerifyOtp,
      VnecomsOtp.verifyVariables(phone, code),
    );
    VnecomsOtp.requireSuccess(data['customerRegisterVerifyOtp']);
  }

  /// `customerForgotPasswordSendOtp`. Throws [Failure] when no account holds
  /// the number.
  Future<void> requestPasswordResetOtp(
    String phone, {
    bool resend = false,
  }) async {
    final data = await _mutate(
      OtpQueries.forgotPasswordSendOtp,
      VnecomsOtp.sendVariables(phone, resend: resend),
    );
    VnecomsOtp.requireSuccess(data['customerForgotPasswordSendOtp']);
  }

  /// Exchanges the code for the account's e-mail + a reset token
  /// (`customerForgotPasswordVerifyOtp`). The new password is then set with
  /// [resetPassword] — core `resetPassword`, so the store's password rules
  /// apply as on the website. Throws [Failure] on a wrong / expired code.
  Future<PasswordResetTicket> verifyPasswordResetOtp(
    String phone,
    String code,
  ) async {
    final data = await _mutate(
      OtpQueries.forgotPasswordVerifyOtp,
      VnecomsOtp.verifyVariables(phone, code),
    );
    final result = VnecomsOtp.requireSuccess(
      data['customerForgotPasswordVerifyOtp'],
    );
    final email = (result['email'] as String?)?.trim() ?? '';
    final token = (result['resetPasswordToken'] as String?)?.trim() ?? '';
    if (email.isEmpty || token.isEmpty) {
      throw const Failure(
        FailureKind.unknown,
        detail: 'customerForgotPasswordVerifyOtp returned no email/token',
      );
    }
    return PasswordResetTicket(email: email, token: token);
  }

  /// Best-effort token revocation; failures are swallowed so logout always
  /// proceeds to clear local state.
  Future<void> revokeToken() async {
    try {
      await _mutate(AuthQueries.revokeToken, const {});
    } on Object {
      // ignore
    }
  }

  /// Permanently deletes the signed-in customer server-side. Unlike
  /// [revokeToken] this must NOT swallow failures: the caller wipes local state
  /// on success, and silently signing someone out while their account still
  /// exists would look like deletion without being it.
  Future<void> deleteAccount() async {
    await _mutate(AuthQueries.deleteCustomer, const {});
  }

  Future<void> requestPasswordReset(String email) async {
    await _mutate(AuthQueries.requestPasswordReset, {'email': email});
  }

  /// Completes a password reset with the token from the reset email. Throws
  /// [Failure] when the token/email is invalid or expired.
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    final data = await _mutate(AuthQueries.resetPassword, {
      'email': email,
      'resetPasswordToken': token,
      'newPassword': newPassword,
    });
    if (data['resetPassword'] != true) {
      throw const Failure(FailureKind.auth);
    }
  }

  Future<Customer> fetchCustomer() async {
    final data = await _query(AuthQueries.customer);
    final customer = data['customer'] as Map<String, dynamic>?;
    if (customer == null) throw const Failure(FailureKind.auth);
    return Customer.fromJson(customer);
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

  Future<Map<String, dynamic>> _query(String document) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(document),
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

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final graphqlSignIn = ref.watch(
    hubAppAccountFeaturesProvider.select((f) => f.whatsappSignIn),
  );
  return AuthRepository(
    ref.watch(graphqlClientProvider),
    ref.watch(whatsAppOtpApiProvider),
    graphqlSignIn: graphqlSignIn
        ? HubAppWhatsAppSignIn(ref.watch(guestGraphqlClientProvider))
        : null,
    onGraphqlMissing: () =>
        ref.read(hubAppAccountMissingProvider.notifier).mark(),
  );
});
