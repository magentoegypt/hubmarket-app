import 'package:graphql_flutter/graphql_flutter.dart';

/// Injects the dynamic Magento `Store` header (active store view) plus a stable
/// `User-Agent` (and optional `Content-Currency`) on every request.
///
/// The store code is read lazily per request so a language/store switch is
/// reflected immediately without rebuilding the link.
class StoreHeaderLink extends Link {
  StoreHeaderLink({
    required this.storeCode,
    required this.userAgent,
    this.currency,
  });

  final String Function() storeCode;
  final String userAgent;
  final String? currency;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final updated = request.updateContextEntry<HttpLinkHeaders>(
      (headers) => HttpLinkHeaders(
        headers: <String, String>{
          ...?headers?.headers,
          'Store': storeCode(),
          'User-Agent': userAgent,
          if (currency != null) 'Content-Currency': currency!,
        },
      ),
    );
    return forward!(updated);
  }
}
