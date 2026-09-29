import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/auth/data/whatsapp_otp_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

WhatsAppOtpApi _api(http.Response Function(http.Request) respond) =>
    WhatsAppOtpApi(
      client: MockClient((request) async => respond(request)),
      endpoint: (action) =>
          whatsappOtpUri('https://store.test/graphql', 'ar', action),
      userAgent: 'HubMarketApp-test',
    );

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Matcher _failure(FailureKind kind, [Object? detail]) {
  var matcher = isA<Failure>().having((f) => f.kind, 'kind', kind);
  if (detail != null) matcher = matcher.having((f) => f.detail, 'detail', detail);
  return throwsA(matcher);
}

void main() {
  group('whatsappOtpUri', () {
    test('swaps /graphql for the store-scoped REST route', () {
      expect(
        whatsappOtpUri(
          'https://hub-market.magento2.click/graphql',
          'en',
          'send',
        ).toString(),
        'https://hub-market.magento2.click/rest/en/V1/whatsapp/otp/send',
      );
    });

    test('keeps a sub-path install and an explicit port', () {
      expect(
        whatsappOtpUri('http://localhost:8080/shop/graphql', 'ar', 'verify')
            .toString(),
        'http://localhost:8080/shop/rest/ar/V1/whatsapp/otp/verify',
      );
    });
  });

  group('WhatsAppOtpApi', () {
    test('sends the stable User-Agent and JSON', () async {
      late http.Request sent;
      await _api((r) {
        sent = r;
        return _json({'status': 'success', 'message': 'sent'});
      }).sendLoginCode('+971501234567');

      expect(sent.url.path, '/rest/ar/V1/whatsapp/otp/send');
      expect(sent.headers['User-Agent'], 'HubMarketApp-test');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
    });

    test('a refusal arrives as HTTP 200 + status:error → server Failure', () async {
      final api = _api(
        (_) => _json({'status': 'error', 'message': 'Mobile number not found.'}),
      );
      await expectLater(
        api.sendLoginCode('+971501234567'),
        _failure(FailureKind.server, 'Mobile number not found.'),
      );
    });

    test('verify without a token is an auth Failure, not a session', () async {
      final api = _api((_) => _json({'status': 'success', 'message': 'ok'}));
      await expectLater(
        api.verifyLoginCode('+971501234567', '123456'),
        _failure(FailureKind.auth),
      );
    });

    test('Magento input errors are rendered with their parameters', () async {
      final api = _api(
        (_) => _json({
          'message': '"%fieldName" is required. Enter and try again.',
          'parameters': {'fieldName': 'otp'},
        }, 400),
      );
      await expectLater(
        api.verifyLoginCode('+971501234567', ''),
        _failure(FailureKind.server, '"otp" is required. Enter and try again.'),
      );
    });

    test('a missing route (module not deployed) never shows server text',
        () async {
      final api = _api(
        (_) => _json({'message': 'Request does not match any route.'}, 404),
      );
      await expectLater(
        api.sendLoginCode('+971501234567'),
        _failure(FailureKind.unknown),
      );
    });

    test('an HTML edge page is a service Failure', () async {
      final api = _api(
        (_) => http.Response('<!doctype html><title>502</title>', 502),
      );
      await expectLater(
        api.sendLoginCode('+971501234567'),
        _failure(FailureKind.service),
      );
    });

    test('a transport error is a network Failure', () async {
      final api = WhatsAppOtpApi(
        client: MockClient((_) async => throw http.ClientException('offline')),
        endpoint: (a) => Uri.parse('https://store.test/rest/en/V1/x/$a'),
        userAgent: 'HubMarketApp-test',
      );
      await expectLater(
        api.sendLoginCode('+971501234567'),
        _failure(FailureKind.network),
      );
    });
  });
}
