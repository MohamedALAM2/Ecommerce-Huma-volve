/// Infrastructure-level error thrown by remote data sources.
///
/// Carries the raw HTTP facts (status code, endpoint-specific message, and a
/// coarse [kind]) upward. Repository implementations translate it into a
/// typed [AppFailure] (see `app_failure.dart`), so no Dio details ever reach
/// the Domain or Presentation layers.
enum ApiErrorKind {
  /// No connectivity (connection errors, socket failures).
  network,

  /// Connect/send/receive timeouts.
  timeout,

  /// The server responded with a non-2xx status.
  response,

  /// Anything else (malformed payloads, unexpected shapes).
  unknown,
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  const ApiException(this.message, {this.statusCode, required this.kind});

  const ApiException.network(String message)
    : this(message, kind: ApiErrorKind.network);

  const ApiException.timeout(String message)
    : this(message, kind: ApiErrorKind.timeout);

  const ApiException.response(int? statusCode, String message)
    : this(message, statusCode: statusCode, kind: ApiErrorKind.response);

  const ApiException.unknown(String message)
    : this(message, kind: ApiErrorKind.unknown);

  @override
  String toString() => 'ApiException($kind, statusCode: $statusCode): $message';
}
