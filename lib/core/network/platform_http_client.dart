import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The HTTP client for the app's plain REST calls, chosen as the GraphQL
/// client's is (`graphql_client.dart`): on iOS/macOS `NSURLSession`, which
/// honours the system proxy/VPN and gets the stable [userAgent] pinned on the
/// session so the storefront's WAF lets it through; elsewhere `dart:io`.
///
/// Unlike the GraphQL client this leaves `Accept-Encoding` alone, so
/// responses arrive compressed and are decompressed by the platform.
http.Client platformHttpClient(String userAgent) {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    final configuration = URLSessionConfiguration.defaultSessionConfiguration()
      ..httpAdditionalHeaders = {'User-Agent': userAgent};
    return CupertinoClient.fromSessionConfiguration(configuration);
  }
  return http.Client();
}
