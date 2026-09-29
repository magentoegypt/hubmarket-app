import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Why an Algolia call failed.
enum AlgoliaErrorKind {
  /// No host answered: offline, DNS, TLS, a timeout, or 5xx from every host.
  unreachable,

  /// Algolia refused the request (4xx): a bad parameter, an unknown index, or
  /// a key that is invalid, expired (`validUntil`) or lacks the ACL.
  rejected,

  /// A host answered 200 with something that isn't a search response.
  malformed,
}

/// An Algolia request that failed. Carries the HTTP status and Algolia's
/// message, never the key.
class AlgoliaException implements Exception {
  const AlgoliaException(this.kind, {this.status, this.message});

  final AlgoliaErrorKind kind;
  final int? status;
  final String? message;

  /// The key itself was refused — expired or revoked — so fetching a fresh
  /// one may help.
  bool get isKeyRejected => status == 401 || status == 403;

  @override
  String toString() =>
      'AlgoliaException(${kind.name}'
      '${status == null ? '' : ', HTTP $status'}'
      '${message == null ? '' : ': $message'})';
}

/// One search of a multi-query: an index and its search parameters.
@immutable
class AlgoliaQuery {
  const AlgoliaQuery(this.indexName, this.params);

  final String indexName;

  /// Search parameters (`query`, `hitsPerPage`, `facetFilters`, …). Null
  /// values are left out; lists and maps are sent as JSON.
  final Map<String, Object?> params;

  /// [params] the way the REST API takes them: one URL-encoded string.
  String encodedParams() => [
    for (final entry in params.entries)
      if (entry.value != null)
        '${Uri.encodeComponent(entry.key)}='
            '${Uri.encodeComponent(_encodeValue(entry.value!))}',
  ].join('&');

  Map<String, Object?> toJson() => {
    'indexName': indexName,
    'params': encodedParams(),
  };

  static String _encodeValue(Object value) =>
      value is String || value is num || value is bool
      ? '$value'
      : jsonEncode(value);
}

/// A minimal Algolia Search REST client on `package:http` — the one call the
/// app needs, the multi-query `POST /1/indexes/*/queries`, which runs several
/// searches (products, categories, pages) in a single round trip.
///
/// It follows Algolia's retry strategy: the read-optimised
/// `{appId}-dsn.algolia.net` first, then `{appId}-1/2/3.algolianet.com` when a
/// host can't be reached, times out or answers 5xx. A 4xx is Algolia's answer
/// and is not retried on another host.
///
/// The API key travels in the `X-Algolia-API-Key` header only. It is public
/// by design (the website ships it in its HTML) but is still never logged.
class AlgoliaClient {
  AlgoliaClient(
    this._http, {
    this.timeout = const Duration(seconds: 4),
    this.userAgent,
  });

  final http.Client _http;

  /// Per-host limit; the next host is tried when it passes.
  final Duration timeout;
  final String? userAgent;

  /// The hosts to try for [appId], in order.
  static List<String> hostsFor(String appId) => <String>[
    '$appId-dsn.algolia.net',
    '$appId-1.algolianet.com',
    '$appId-2.algolianet.com',
    '$appId-3.algolianet.com',
  ];

  /// Runs [queries] and returns one result map per query, in order. Throws
  /// [AlgoliaException].
  Future<List<Map<String, dynamic>>> multiQuery({
    required String appId,
    required String apiKey,
    required List<AlgoliaQuery> queries,
  }) async {
    final body = jsonEncode({
      'requests': [for (final query in queries) query.toJson()],
    });
    final headers = <String, String>{
      'X-Algolia-Application-Id': appId,
      'X-Algolia-API-Key': apiKey,
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
      if (userAgent != null) 'User-Agent': userAgent!,
    };

    AlgoliaException? last;
    for (final host in hostsFor(appId)) {
      final uri = Uri.parse('https://$host/1/indexes/*/queries');
      final http.Response response;
      try {
        response = await _http
            .post(uri, headers: headers, body: body)
            .timeout(timeout);
      } on TimeoutException {
        last = const AlgoliaException(
          AlgoliaErrorKind.unreachable,
          message: 'timed out',
        );
        continue;
      } on http.ClientException catch (error) {
        last = AlgoliaException(
          AlgoliaErrorKind.unreachable,
          message: error.message,
        );
        continue;
      } on IOException catch (error) {
        last = AlgoliaException(
          AlgoliaErrorKind.unreachable,
          message: error.runtimeType.toString(),
        );
        continue;
      }

      final status = response.statusCode;
      if (status >= 500) {
        last = AlgoliaException(
          AlgoliaErrorKind.unreachable,
          status: status,
          message: _message(response),
        );
        continue;
      }
      if (status >= 400) {
        throw AlgoliaException(
          AlgoliaErrorKind.rejected,
          status: status,
          message: _message(response),
        );
      }

      final results = _results(response);
      if (results == null || results.length != queries.length) {
        // A captive portal or proxy page: another host may get through.
        last = AlgoliaException(
          AlgoliaErrorKind.malformed,
          status: status,
          message: 'not a multi-query response',
        );
        continue;
      }
      return results;
    }
    throw last ??
        const AlgoliaException(
          AlgoliaErrorKind.unreachable,
          message: 'no host',
        );
  }

  static List<Map<String, dynamic>>? _results(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final results = decoded is Map<String, dynamic>
          ? decoded['results']
          : null;
      if (results is! List) return null;
      return results.whereType<Map<String, dynamic>>().toList(growable: false);
    } on FormatException {
      return null;
    }
  }

  /// Algolia's error text (`{"message": …, "status": …}`), when there is one.
  static String? _message(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final message = decoded is Map<String, dynamic>
          ? decoded['message']
          : null;
      return message is String && message.trim().isNotEmpty
          ? message.trim()
          : null;
    } on FormatException {
      return null;
    }
  }
}
