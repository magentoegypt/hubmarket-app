/// Categories of failure surfaced to the UI. The presentation layer maps each
/// kind to a localized, user-friendly message (see `failure_message.dart`).
enum FailureKind {
  /// Connectivity / transport problem.
  network,

  /// Edge returned a non-JSON/HTML response (WAF / CloudFront / maintenance).
  service,

  /// Token invalid or expired (`graphql-authorization` / 401).
  auth,

  /// Backend returned GraphQL errors.
  server,

  /// Anything we didn't classify.
  unknown,
}

/// Errors are values. The data layer maps exceptions to a [Failure]; the UI
/// never sees a raw GraphQL/transport exception.
class Failure implements Exception {
  const Failure(this.kind, {this.detail});

  final FailureKind kind;

  /// Optional non-localized technical detail (logging / server message).
  final String? detail;

  @override
  String toString() =>
      'Failure(${kind.name}${detail != null ? ': $detail' : ''})';
}
