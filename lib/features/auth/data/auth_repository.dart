import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../domain/customer.dart';
import 'auth_queries.dart';
import 'otp_queries.dart';

class AuthRepository {
  AuthRepository(this._client);

  final GraphQLClient _client;

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

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? mobileNumber,
  }) async {
    await _mutate(AuthQueries.createCustomer, {
      'input': <String, dynamic>{
        'firstname': firstName,
        'lastname': lastName,
        'email': email,
        'password': password,
        // The registration guard requires a verified `mobile_number` custom
        // attribute (INTEGRATION.md §3/§7a). Send the same E.164 number that was
        // WhatsApp-verified; `CustomerCreateInput.custom_attributes` is confirmed
        // on the live schema.
        if (mobileNumber != null && mobileNumber.isNotEmpty)
          'custom_attributes': <Map<String, dynamic>>[
            {'attribute_code': 'mobile_number', 'value': mobileNumber},
          ],
      },
    });
  }

  // --- WhatsApp OTP (MagentoEgypt_OtpVerification) ---------------------------

  /// Requests a login OTP. Always succeeds server-side (anti-enumeration), so a
  /// non-error return says nothing about whether the number has an account.
  Future<void> requestLoginOtp(String phone) async {
    await _mutate(OtpQueries.requestLoginOtp, {'phone': phone});
  }

  /// Verifies a login OTP and returns the customer token. Throws [Failure] on a
  /// wrong/expired code (the module returns it as a GraphQL error).
  Future<String> loginWithOtp(String phone, String code) async {
    final data = await _mutate(OtpQueries.loginWithOtp, {
      'phone': phone,
      'code': code,
    });
    final token =
        (data['loginWithOtp'] as Map<String, dynamic>?)?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const Failure(FailureKind.auth);
    }
    return token;
  }

  Future<void> requestRegistrationOtp(String phone) async {
    await _mutate(OtpQueries.requestRegistrationOtp, {'phone': phone});
  }

  /// Verifies a registration OTP within the post-verify window. Throws [Failure]
  /// on a wrong/expired code so the UI keeps Create Account disabled.
  Future<void> verifyRegistrationOtp(String phone, String code) async {
    await _mutate(OtpQueries.verifyRegistrationOtp, {
      'phone': phone,
      'code': code,
    });
  }

  Future<void> requestPasswordResetOtp(String phone) async {
    await _mutate(OtpQueries.requestPasswordResetOtp, {'phone': phone});
  }

  Future<void> resetPasswordWithOtp({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    await _mutate(OtpQueries.resetPasswordWithOtp, {
      'phone': phone,
      'code': code,
      'newPassword': newPassword,
    });
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

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(graphqlClientProvider)),
);
