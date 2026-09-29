import 'dart:convert';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/store/store_controller.dart';

/// `MagentoEgypt_SmsExtend`'s WhatsApp OTP endpoints — REST, not GraphQL:
///
///     POST /rest/<store>/V1/whatsapp/otp/send    {mobile, type}
///     POST /rest/<store>/V1/whatsapp/otp/verify  {mobile, otp, type, password}
///
/// This is the only route on the Hub Market backend that turns a verified code
/// into a customer token: with `type: "LOGIN"`, `verify` answers `token`, a
/// customer bearer minted by Magento's token issuer (the same kind
/// `generateCustomerToken` returns). The Vnecoms GraphQL pair
/// `customerLoginSendOtp` / `customerLoginVerifyOtp` checks a code but returns
/// no token and signs no one in. The Hub Market seller app signs sellers in
/// through this same pair with `type: "VENDOR_LOGIN"`.
///
/// The backend matches the number against the customer's `mobilenumber` in any
/// stored spelling (`+971…` / `971…`), refuses a number shared by several
/// accounts, and counts wrong codes toward the account lockout.
///
/// Both endpoints answer **HTTP 200** with `{status, message, token}`; a
/// refusal ("Mobile number not found.", "Invalid OTP.", "Please wait 30
/// seconds…") is `status: "error"`, not an HTTP error. `message` comes back in
/// the language of the store view in the URL, so it is surfaced as-is.
class WhatsAppOtpApi {
  WhatsAppOtpApi({
    required this._client,
    required this._endpoint,
    required this._userAgent,
  });

  final http.Client _client;
  final Uri Function(String action) _endpoint;
  final String _userAgent;

  static const String _login = 'LOGIN';

  /// Sends a sign-in code to [mobile] (E.164). Throws [Failure] (`server`,
  /// with the store's message) when the number has no account or the resend
  /// cooldown is still running.
  Future<void> sendLoginCode(String mobile) async {
    await _post('send', <String, String>{'mobile': mobile, 'type': _login});
  }

  /// Verifies [code] for [mobile] and returns the customer token. Throws
  /// [Failure] on a wrong / expired code or a locked account.
  Future<String> verifyLoginCode(String mobile, String code) async {
    final body = await _post('verify', <String, String>{
      'mobile': mobile,
      'otp': code,
      'type': _login,
      // Only read for FORGOTPASS; the service signature still expects it.
      'password': '',
    });
    final token = body['token'];
    if (token is! String || token.isEmpty) {
      throw const Failure(FailureKind.auth, detail: 'verify returned no token');
    }
    return token;
  }

  Future<Map<String, dynamic>> _post(
    String action,
    Map<String, String> payload,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        _endpoint(action),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        },
        body: jsonEncode(payload),
      );
    } on Object catch (error) {
      throw Failure(FailureKind.network, detail: '$error');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // An edge / maintenance HTML page instead of JSON.
      throw Failure(
        FailureKind.service,
        detail: 'HTTP ${response.statusCode}: non-JSON body',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw Failure(
        FailureKind.service,
        detail: 'HTTP ${response.statusCode}: unexpected body',
      );
    }

    final message = _render(decoded['message'], decoded['parameters']);
    switch (response.statusCode) {
      case 200:
        if (decoded['status'] == 'success') return decoded;
        throw Failure(FailureKind.server, detail: message);
      case 400:
        // Magento's input validation ("Invalid input data.") — localised.
        throw Failure(FailureKind.server, detail: message);
      case 401:
        throw Failure(FailureKind.auth, detail: message);
      default:
        // 404 "Request does not match any route." (module not deployed), 5xx:
        // nothing a customer can act on, so no server text reaches the UI.
        throw Failure(
          FailureKind.unknown,
          detail: 'HTTP ${response.statusCode}: ${message ?? ''}',
        );
    }
  }

  /// Magento REST errors carry placeholders — `%fieldName` with a map of
  /// `parameters`, or `%1` with a list. Substitute them so the text reads
  /// naturally; null when there is no message.
  static String? _render(Object? message, Object? parameters) {
    if (message is! String || message.trim().isEmpty) return null;
    var text = message.trim();
    if (parameters is Map) {
      parameters.forEach((key, value) => text = text.replaceAll('%$key', '$value'));
    } else if (parameters is List) {
      for (var i = parameters.length; i >= 1; i--) {
        text = text.replaceAll('%$i', '${parameters[i - 1]}');
      }
    }
    return text;
  }
}

/// `https://host/graphql` + `en` + `send` →
/// `https://host/rest/en/V1/whatsapp/otp/send`. The store code in the path
/// picks the store view, i.e. the language of the returned message.
Uri whatsappOtpUri(String graphqlEndpoint, String storeCode, String action) {
  final base = Uri.parse(graphqlEndpoint);
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last == 'graphql') segments.removeLast();
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    pathSegments: <String>[
      ...segments,
      'rest',
      storeCode,
      'V1',
      'whatsapp',
      'otp',
      action,
    ],
  );
}

/// Same transport choice as the GraphQL client (`graphql_client.dart`): on
/// iOS/macOS route through `NSURLSession`, which honours the system proxy/VPN
/// and needs the stable User-Agent pinned on the session configuration to be
/// sure it is sent; elsewhere `dart:io`.
http.Client _platformHttpClient(String userAgent) {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    final configuration = URLSessionConfiguration.defaultSessionConfiguration()
      ..httpAdditionalHeaders = {'User-Agent': userAgent};
    return CupertinoClient.fromSessionConfiguration(configuration);
  }
  return http.Client();
}

final whatsAppOtpApiProvider = Provider<WhatsAppOtpApi>((ref) {
  final config = ref.watch(appConfigProvider);
  final client = _platformHttpClient(config.userAgent);
  ref.onDispose(client.close);
  return WhatsAppOtpApi(
    client: client,
    userAgent: config.userAgent,
    // Read at call time: the store view follows the app language.
    endpoint: (action) => whatsappOtpUri(
      config.graphqlEndpoint,
      ref.read(storeControllerProvider).activeStoreCode,
      action,
    ),
  );
});
