import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/data/whatsapp_otp_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A GraphQL backend that answers by operation name and records every request,
/// so a test can pin exactly which Hub Market operation (and variables) a flow
/// sends. `__typename` is on every object because graphql_flutter adds it to
/// each document and its cache rejects a response without it.
class _GraphQl {
  _GraphQl(this.answers);

  final Map<String, Map<String, dynamic>> answers;
  final List<Request> requests = [];

  /// The operation as written in the document (graphql_flutter leaves
  /// `Operation.operationName` null unless the options set it).
  static OperationDefinitionNode _definition(Request request) => request
      .operation
      .document
      .definitions
      .whereType<OperationDefinitionNode>()
      .first;

  static String _name(Request request) =>
      _definition(request).name?.value ?? '?';

  List<String> get operations => [for (final r in requests) _name(r)];

  Map<String, dynamic> variablesOf(String operation) =>
      requests.firstWhere((r) => _name(r) == operation).variables;

  GraphQLClient get client => GraphQLClient(
    link: Link.function((request, [forward]) {
      requests.add(request);
      final data = answers[_name(request)];
      if (data == null) {
        return Stream<Response>.error(Exception('unexpected ${_name(request)}'));
      }
      final isQuery = _definition(request).type == OperationType.query;
      return Stream<Response>.value(
        Response(
          data: <String, dynamic>{
            '__typename': isQuery ? 'Query' : 'Mutation',
            ...data,
          },
          response: const <String, dynamic>{},
          context: const Context(),
        ),
      );
    }),
    cache: GraphQLCache(),
  );
}

Map<String, dynamic> _otp(String field, Map<String, dynamic> body) => {
  field: <String, dynamic>{'__typename': 'CustomerSendOtpOutput', ...body},
};

/// The REST side (MagentoEgypt_SmsExtend) — records what the app posts.
class _Rest {
  final List<http.Request> requests = [];
  Map<String, dynamic> reply = {'status': 'success', 'message': 'OK'};

  WhatsAppOtpApi get api => WhatsAppOtpApi(
    client: MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(reply),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
    endpoint: (action) =>
        Uri.parse('https://store.test/rest/en/V1/whatsapp/otp/$action'),
    userAgent: 'HubMarketApp-test',
  );
}

const _mobile = '+971501234567';

void main() {
  group('registration OTP → Vnecoms GraphQL', () {
    test('send maps to customerRegisterSendOtp {mobile, resend}', () async {
      final gql = _GraphQl({
        'RegisterSendOtp': _otp('customerRegisterSendOtp', {
          'success': true,
          'msg': null,
        }),
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await repo.requestRegistrationOtp(_mobile);
      await repo.requestRegistrationOtp(_mobile, resend: true);

      expect(gql.operations, ['RegisterSendOtp', 'RegisterSendOtp']);
      expect(gql.requests.first.variables, {
        'input': {'mobile': _mobile, 'resend': false},
      });
      expect(gql.requests.last.variables, {
        'input': {'mobile': _mobile, 'resend': true},
      });
    });

    test('a refused send surfaces the store message as a server Failure',
        () async {
      // The module never raises a GraphQL error — refusal is success:false.
      final gql = _GraphQl({
        'RegisterSendOtp': _otp('customerRegisterSendOtp', {
          'success': false,
          'msg': 'The mobile number is used by another customer account.',
        }),
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await expectLater(
        repo.requestRegistrationOtp(_mobile),
        throwsA(
          isA<Failure>()
              .having((f) => f.kind, 'kind', FailureKind.server)
              .having(
                (f) => f.detail,
                'detail',
                'The mobile number is used by another customer account.',
              ),
        ),
      );
    });

    test('verify maps to customerRegisterVerifyOtp {mobile, otp}', () async {
      final gql = _GraphQl({
        'RegisterVerifyOtp': _otp('customerRegisterVerifyOtp', {
          'success': true,
          'msg': null,
        }),
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await repo.verifyRegistrationOtp(_mobile, '123456');

      expect(gql.variablesOf('RegisterVerifyOtp'), {
        'input': {'mobile': _mobile, 'otp': '123456'},
      });
    });

    test('a wrong code fails verification', () async {
      final gql = _GraphQl({
        'RegisterVerifyOtp': _otp('customerRegisterVerifyOtp', {
          'success': false,
          'msg': 'The OTP code is not valid.',
        }),
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await expectLater(
        repo.verifyRegistrationOtp(_mobile, '000000'),
        throwsA(isA<Failure>().having((f) => f.kind, 'kind', FailureKind.server)),
      );
    });

    test('register sends the number as top-level `mobilenumber` on createCustomer',
        () async {
      // createCustomerV2 can't carry it, and the backend refuses a GraphQL
      // sign-up without it.
      final gql = _GraphQl({
        'CreateCustomer': {
          'createCustomer': <String, dynamic>{
            '__typename': 'CustomerOutput',
            'customer': <String, dynamic>{
              '__typename': 'Customer',
              'firstname': 'Sara',
              'lastname': 'Ali',
              'email': 'sara@example.com',
            },
          },
        },
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await repo.register(
        firstName: 'Sara',
        lastName: 'Ali',
        email: 'sara@example.com',
        password: 'Secret123!',
        mobileNumber: _mobile,
      );

      final input = gql.variablesOf('CreateCustomer')['input'] as Map;
      expect(input['mobilenumber'], _mobile);
      expect(input.containsKey('custom_attributes'), isFalse);
      expect(input['email'], 'sara@example.com');
      // The "Send me offers" box was left unticked.
      expect(input.containsKey('is_subscribed'), isFalse);
    });

    test('the "Send me offers" box subscribes the new account', () async {
      final gql = _GraphQl({
        'CreateCustomer': {
          'createCustomer': <String, dynamic>{
            '__typename': 'CustomerOutput',
            'customer': <String, dynamic>{
              '__typename': 'Customer',
              'firstname': 'Sara',
              'lastname': 'Ali',
              'email': 'sara@example.com',
            },
          },
        },
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await repo.register(
        firstName: 'Sara',
        lastName: 'Ali',
        email: 'sara@example.com',
        password: 'Secret123!',
        mobileNumber: _mobile,
        subscribeToNewsletter: true,
      );

      final input = gql.variablesOf('CreateCustomer')['input'] as Map;
      expect(input['is_subscribed'], isTrue);
    });
  });

  group('password reset OTP → Vnecoms GraphQL + core resetPassword', () {
    test('send maps to customerForgotPasswordSendOtp', () async {
      final gql = _GraphQl({
        'ForgotPasswordSendOtp': _otp('customerForgotPasswordSendOtp', {
          'success': true,
          'msg': null,
        }),
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await repo.requestPasswordResetOtp(_mobile);

      expect(gql.variablesOf('ForgotPasswordSendOtp'), {
        'input': {'mobile': _mobile, 'resend': false},
      });
    });

    test('verify yields email + token, which reset the password', () async {
      final gql = _GraphQl({
        'ForgotPasswordVerifyOtp': _otp('customerForgotPasswordVerifyOtp', {
          'success': true,
          'msg': null,
          'email': 'sara@example.com',
          'resetPasswordToken': 'rp-token-1',
        }),
        'ResetPassword': {'resetPassword': true},
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      final ticket = await repo.verifyPasswordResetOtp(_mobile, '123456');
      expect(ticket.email, 'sara@example.com');
      expect(ticket.token, 'rp-token-1');
      await repo.resetPassword(
        email: ticket.email,
        token: ticket.token,
        newPassword: 'NewSecret1!',
      );

      expect(gql.operations, ['ForgotPasswordVerifyOtp', 'ResetPassword']);
      expect(gql.variablesOf('ForgotPasswordVerifyOtp'), {
        'input': {'mobile': _mobile, 'otp': '123456'},
      });
      expect(gql.variablesOf('ResetPassword'), {
        'email': 'sara@example.com',
        'resetPasswordToken': 'rp-token-1',
        'newPassword': 'NewSecret1!',
      });
    });

    test('a wrong code never reaches resetPassword', () async {
      final gql = _GraphQl({
        // GraphQL returns every selected field; the resolver leaves these out
        // on failure, so they arrive as null.
        'ForgotPasswordVerifyOtp': _otp('customerForgotPasswordVerifyOtp', {
          'success': false,
          'msg': 'The OTP code is expired.',
          'email': null,
          'resetPasswordToken': null,
        }),
        'ResetPassword': {'resetPassword': true},
      });
      final repo = AuthRepository(gql.client, _Rest().api);

      await expectLater(
        repo.verifyPasswordResetOtp(_mobile, '000000'),
        throwsA(
          isA<Failure>().having(
            (f) => f.detail,
            'detail',
            'The OTP code is expired.',
          ),
        ),
      );
      expect(gql.operations, ['ForgotPasswordVerifyOtp']);
    });
  });

  group('sign-in OTP → SmsExtend REST (the only path that returns a token)', () {
    test('send posts {mobile, type: LOGIN} to /whatsapp/otp/send', () async {
      final rest = _Rest();
      final gql = _GraphQl({});
      final repo = AuthRepository(gql.client, rest.api);

      await repo.requestLoginOtp(_mobile);

      expect(gql.requests, isEmpty); // nothing on GraphQL
      expect(rest.requests.single.method, 'POST');
      expect(
        rest.requests.single.url.toString(),
        'https://store.test/rest/en/V1/whatsapp/otp/send',
      );
      expect(jsonDecode(rest.requests.single.body), {
        'mobile': _mobile,
        'type': 'LOGIN',
      });
    });

    test('verify returns the customer token', () async {
      final rest = _Rest()
        ..reply = {
          'status': 'success',
          'message': 'OTP verified successfully.',
          'token': 'customer-jwt',
        };
      final repo = AuthRepository(_GraphQl({}).client, rest.api);

      final token = await repo.loginWithOtp(_mobile, '123456');

      expect(token, 'customer-jwt');
      expect(
        rest.requests.single.url.path,
        '/rest/en/V1/whatsapp/otp/verify',
      );
      expect(jsonDecode(rest.requests.single.body), {
        'mobile': _mobile,
        'otp': '123456',
        'type': 'LOGIN',
        'password': '',
      });
    });
  });

  test('fetchCustomer reads the mobile from `mobilenumber`', () async {
    final gql = _GraphQl({
      'CurrentCustomer': {
        'customer': <String, dynamic>{
          '__typename': 'Customer',
          'firstname': 'Sara',
          'lastname': 'Ali',
          'email': 'sara@example.com',
          'mobilenumber': _mobile,
        },
      },
    });
    final repo = AuthRepository(gql.client, _Rest().api);

    final customer = await repo.fetchCustomer();

    expect(customer.mobileNumber, _mobile);
    expect(customer.avatarUrl, isNull);
  });
}
