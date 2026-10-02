import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Sends Algolia Insights events (`POST https://insights.algolia.io/1/events`).
///
/// Best effort, never throws: personalisation is an extra, and a lost event
/// only means a slightly thinner profile. The key is the same search-only
/// (secured) key the search uses; it travels in the `X-Algolia-API-Key` header
/// only and is never logged.
class InsightsClient {
  InsightsClient(
    this._http, {
    this.host = 'insights.algolia.io',
    this.timeout = const Duration(seconds: 6),
    this.userAgent,
  });

  final http.Client _http;
  final String host;
  final Duration timeout;
  final String? userAgent;

  /// Whether Algolia accepted [events] (HTTP 200). An empty list is nothing to
  /// send and counts as accepted.
  Future<bool> send({
    required String appId,
    required String apiKey,
    required List<Map<String, Object?>> events,
  }) async {
    if (events.isEmpty) return true;
    try {
      final response = await _http
          .post(
            Uri.https(host, '/1/events'),
            headers: {
              'X-Algolia-Application-Id': appId,
              'X-Algolia-API-Key': apiKey,
              'Content-Type': 'application/json; charset=UTF-8',
              'Accept': 'application/json',
              if (userAgent != null) 'User-Agent': userAgent!,
            },
            body: jsonEncode({'events': events}),
          )
          .timeout(timeout);
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }
}
