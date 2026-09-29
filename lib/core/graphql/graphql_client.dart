import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;

import '../../features/auth/presentation/auth_controller.dart';
import '../config/app_config.dart';
import '../storage/secure_token_store.dart';
import '../store/store_controller.dart';
import 'resilience_link.dart';
import 'store_link.dart';

/// On iOS/macOS, route HTTP through `NSURLSession` (the same stack Safari uses)
/// instead of `dart:io`'s `HttpClient`. `dart:io` ignores the system proxy/VPN
/// and can hit TLS/connection edge cases that NSURLSession handles — which
/// presented as "all GraphQL failing on iOS while Safari + Android work".
/// Android keeps `dart:io` (it works and avoids an unnecessary native client).
///
/// The stable [userAgent] is pinned at the session-configuration level
/// (`httpAdditionalHeaders`) so the allow-listed UA reaches AWS WAF on *every*
/// request — otherwise NSURLSession sends its default `app/version CFNetwork/…
/// Darwin/…` UA, which the WAF blocks (returns an HTML page → `service` error).
http.Client _platformHttpClient(String userAgent) {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    final configuration =
        URLSessionConfiguration.defaultSessionConfiguration()
          ..httpAdditionalHeaders = {
            'User-Agent': userAgent,
            // Force uncompressed responses on iOS. Once the app sets
            // Accept-Encoding, NSURLSession stops auto-decompressing — so we
            // ask the edge for `identity` (CloudFront honours it) and get plain
            // JSON. This sidesteps a compressed body that gql_http_link's
            // utf8→json decoder can't parse (it surfaced as a `service`
            // failure on the larger storeConfig response while a tiny probe
            // response — uncompressed — succeeded).
            'Accept-Encoding': 'identity',
          };
    return CupertinoClient.fromSessionConfiguration(configuration);
  }
  return http.Client();
}

/// Diagnostic probe: hits the GraphQL endpoint with the **platform** HTTP client
/// (NSURLSession on iOS) and the app's real headers, returning the raw status,
/// content-type and a body snippet. Bypasses graphql_flutter so we can see
/// exactly what the edge returns on the actual iOS transport — JSON vs a
/// WAF/CloudFront HTML page. Surfaced on the diagnostics screen.
Future<
  ({
    int status,
    String contentType,
    String contentEncoding,
    int bytes,
    String body,
  })
>
rawTransportProbe(AppConfig config, String storeCode) async {
  final client = _platformHttpClient(config.userAgent);
  try {
    // Use the *full* storeConfig query (all fields) so the probe exercises the
    // same larger response that fails through the GraphQL link chain — not a
    // tiny one-field response that always parses.
    const query =
        '{"query":"query{storeConfig{store_code store_name locale '
        'base_currency_code default_display_currency_code base_url '
        'secure_base_url base_media_url}}"}';
    final response = await client.post(
      Uri.parse(config.graphqlEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': config.userAgent,
        'Store': storeCode,
      },
      body: query,
    );
    final body = response.body;
    return (
      status: response.statusCode,
      contentType: response.headers['content-type'] ?? '—',
      contentEncoding: response.headers['content-encoding'] ?? 'identity',
      bytes: response.bodyBytes.length,
      body: body.length > 500 ? '${body.substring(0, 500)}…' : body,
    );
  } finally {
    client.close();
  }
}

/// Builds a GraphQL client with the link chain:
///   AuthLink (bearer, only when [token] is given) → StoreHeaderLink (dynamic
///   `Store` header) → ResilienceLink (retry transient queries + mid-session
///   logout) → HttpLink (terminating).
///
/// Without [token] no `Authorization` header can ever be sent — the guest and
/// public clients. [getForQueries] sends queries as HTTP GET (mutations stay
/// POST) with a compacted document, so Magento's full-page cache / Varnish can
/// serve public reads — see [publicGraphqlClientProvider].
///
/// Exception → [Failure] mapping happens at the repository layer
/// (see `graphql_failure_mapper.dart`). A plain function (the providers below
/// wire it) so tests can drive the real link chain over a fake [httpClient].
GraphQLClient buildGraphQLClient({
  required AppConfig config,
  required String Function() storeCode,
  Future<String?> Function()? token,
  void Function()? onAuthError,
  bool getForQueries = false,
  http.Client? httpClient,
}) {
  // Set the stable User-Agent at the transport level too (not only via
  // StoreHeaderLink) so it is guaranteed on every request — without it, the
  // default `Dart/<ver> (dart:io)` UA goes out, which AWS WAF/bot rules are
  // likely to block (CLAUDE.md §7). The Store header stays dynamic in the link.
  final httpLink = HttpLink(
    config.graphqlEndpoint,
    // Pin Accept to application/json (gql_http_link defaults to `*/*`, which
    // lets the edge content-negotiate a different/compressed payload) — match
    // the raw-probe request that succeeds on iOS.
    defaultHeaders: {
      'User-Agent': config.userAgent,
      'Accept': 'application/json',
    },
    httpClient: httpClient ?? _platformHttpClient(config.userAgent),
    useGETForQueries: getForQueries,
    serializer: getForQueries
        ? const CompactRequestSerializer()
        : const RequestSerializer(),
  );

  final link = Link.from(<Link>[
    if (token != null)
      AuthLink(
        getToken: () async {
          final value = await token();
          return value == null ? null : 'Bearer $value';
        },
      ),
    StoreHeaderLink(storeCode: storeCode, userAgent: config.userAgent),
    ResilienceLink(onAuthError: onAuthError ?? () {}),
    httpLink,
  ]);

  return GraphQLClient(
    link: link,
    cache: GraphQLCache(store: InMemoryStore()),
    // Disable graphql's built-in request timeout: its 5s default times out
    // mutations against the CloudFront/WAF-fronted endpoint, and its timeout
    // path double-completes the response completer when ResilienceLink retries
    // ("Bad state: Future already completed", graphql 5.2.4). ResilienceLink
    // owns the timeout instead (consumed via `await for`, so no double-complete).
    queryRequestTimeout: null,
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.networkOnly),
    ),
  );
}

/// The client for everything that may carry the customer's bearer. Invalidate
/// it on a language/store switch to reset the cache and refetch with the new
/// header.
final graphqlClientProvider = Provider<GraphQLClient>((ref) {
  final tokenStore = ref.watch(secureTokenStoreProvider);
  return buildGraphQLClient(
    config: ref.watch(appConfigProvider),
    storeCode: () => ref.read(storeControllerProvider).activeStoreCode,
    token: tokenStore.read,
    // Defer to a microtask so logout (which invalidates this very provider)
    // runs after the current response stream settles, never mid-emit.
    onAuthError: () => Future.microtask(
      () => ref.read(authControllerProvider.notifier).handleSessionExpired(),
    ),
  );
});

/// A **token-less** twin of [graphqlClientProvider]: same endpoint, transport
/// (POST), `Store` header and retry behaviour, but no `Authorization` header.
///
/// Exists so the app can answer *"is the stored bearer the reason this request
/// failed?"* **without destroying the token to find out**. Browsing GraphQL
/// needs no token, so a guest retry that succeeds where the authenticated one
/// failed is proof the token is at fault — see `StoreController._load()`.
/// Deliberately POST like the authenticated client: a GET could be answered
/// from the full-page cache while the edge is refusing requests, which would
/// look like proof against a perfectly good token.
///
/// The guest client sends no bearer, so an auth error there says nothing about
/// the customer's session — it never drops them to guest.
final guestGraphqlClientProvider = Provider<GraphQLClient>(
  (ref) => buildGraphQLClient(
    config: ref.watch(appConfigProvider),
    storeCode: () => ref.read(storeControllerProvider).activeStoreCode,
  ),
);

/// The token-less client for **public reads**, with queries sent as HTTP GET
/// so Magento's GraphQL full-page cache (Varnish / built-in FPC — it caches
/// GET only) can answer them: `hmAppConfig`, `hmAppHome`, `hmDeals`,
/// `hmBestSellers`, `hmBundleDeals`, `hmBrands`, `hmStores`, `hmStore` and the
/// catalogue `products` lists they lead to.
///
/// * Keeps the `Store` header (the cache varies on it) and never sends an
///   `Authorization` header — a bearer would make the response private and
///   uncacheable, and none of these reads needs one.
/// * The document travels in the URL, compacted by
///   [CompactRequestSerializer]; keep public documents under ~6 KB (nginx's
///   default request-line limit is 8 KB).
/// * Mutations sent through it still go as POST, but nothing that needs the
///   customer belongs here.
final publicGraphqlClientProvider = Provider<GraphQLClient>(
  (ref) => buildGraphQLClient(
    config: ref.watch(appConfigProvider),
    storeCode: () => ref.read(storeControllerProvider).activeStoreCode,
    getForQueries: true,
  ),
);

/// Serializes requests for a GET transport: the query printed without
/// insignificant whitespace (it becomes part of the URL), the operation name
/// (taken from the document when the caller gave none), and no empty
/// `variables`.
///
/// gql_http_link JSON-encodes every non-string value into its query
/// parameter, so a null operation name would travel as the literal `null` —
/// which Magento reads as an operation called "null".
class CompactRequestSerializer extends RequestSerializer {
  const CompactRequestSerializer();

  @override
  Map<String, dynamic> serializeRequest(Request request) {
    final body = super.serializeRequest(request);
    final query = body['query'];
    if (query is String) body['query'] = compactGraphQLDocument(query);
    final name =
        request.operation.operationName ??
        request.operation.document.definitions
            .whereType<OperationDefinitionNode>()
            .firstOrNull
            ?.name
            ?.value;
    if (name == null || name.isEmpty) {
      body.remove('operationName');
    } else {
      body['operationName'] = name;
    }
    final variables = body['variables'];
    if (variables == null || (variables is Map && variables.isEmpty)) {
      body.remove('variables');
    }
    return body;
  }
}

/// [document] with comments dropped and whitespace (commas included) kept
/// only where two names or numbers would otherwise run together; string
/// literals are copied verbatim.
String compactGraphQLDocument(String document) {
  final out = StringBuffer();
  var i = 0;
  var pendingSpace = false;
  var previous = -1;
  bool isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5a) || // A-Z
      (c >= 0x61 && c <= 0x7a) || // a-z
      c == 0x5f; // _

  void write(String s) {
    // Two words (`query Home`, `on Product`, `10 after`) need their separator,
    // and so do two strings (`"" ""` must not read as a `"""` block string);
    // everything else in GraphQL is delimited by punctuation.
    final next = s.codeUnitAt(0);
    if (pendingSpace &&
        ((isWordChar(previous) && isWordChar(next)) ||
            (previous == 0x22 && next == 0x22))) {
      out.write(' ');
    }
    pendingSpace = false;
    out.write(s);
    previous = s.codeUnitAt(s.length - 1);
  }

  while (i < document.length) {
    final c = document[i];
    if (c == '#') {
      while (i < document.length && document[i] != '\n') {
        i++;
      }
      pendingSpace = true;
      continue;
    }
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ',' ||
        c == '﻿') {
      pendingSpace = true;
      i++;
      continue;
    }
    if (c == '"') {
      final block = document.startsWith('"""', i);
      final start = i;
      if (block) {
        i += 3;
        while (i < document.length && !document.startsWith('"""', i)) {
          i += document[i] == r'\' ? 2 : 1;
        }
        i = (i + 3).clamp(0, document.length);
      } else {
        i++;
        while (i < document.length && document[i] != '"') {
          i += document[i] == r'\' ? 2 : 1;
        }
        i = (i + 1).clamp(0, document.length);
      }
      write(document.substring(start, i));
      continue;
    }
    write(c);
    i++;
  }
  return out.toString();
}
