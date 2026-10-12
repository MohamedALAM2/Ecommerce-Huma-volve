// ignore_for_file: use_super_parameters
// (Explicit forwarding constructors: super-parameters cannot carry the
// default messages used here.)

import 'api_exception.dart';

/// Application-level failure thrown across Domain repository contracts and
/// use cases, and caught by Presentation for user-facing messages.
///
/// Single coherent strategy (no functional/Either dependency): infrastructure
/// errors are translated once, in Data repository implementations, via
/// [AppFailure.fromApiException]. Raw `DioException`s therefore never leak
/// past the Data layer.
abstract class AppFailure implements Exception {
  final String message;
  final int? statusCode;

  const AppFailure(this.message, {this.statusCode});

  /// Central infrastructure-to-application translation.
  ///
  /// Endpoint-specific messages are chosen in the data sources (they own the
  /// context); the *type* is derived here from [ApiException.kind] and the
  /// HTTP status, so behavior depending on the error kind (e.g. session
  /// cleanup on genuinely rejected credentials) is consistent everywhere.
  factory AppFailure.fromApiException(ApiException e) {
    switch (e.kind) {
      case ApiErrorKind.timeout:
        return TimeoutFailure(e.message);
      case ApiErrorKind.network:
        return NetworkFailure(e.message);
      case ApiErrorKind.response:
        switch (e.statusCode) {
          case 400:
          case 422:
            return ValidationFailure(e.message, statusCode: e.statusCode);
          case 401:
            return UnauthorizedFailure(e.message, statusCode: e.statusCode);
          case 403:
            return ForbiddenFailure(e.message, statusCode: e.statusCode);
          case 404:
            return NotFoundFailure(e.message, statusCode: e.statusCode);
          case 429:
            return RateLimitFailure(e.message, statusCode: e.statusCode);
          default:
            if (e.statusCode != null && e.statusCode! >= 500) {
              return ServerFailure(e.message, e.statusCode);
            }
            return UnexpectedFailure(e.message, e.statusCode);
        }
      case ApiErrorKind.unknown:
        return UnexpectedFailure(e.message, e.statusCode);
    }
  }

  @override
  String toString() => '$runtimeType($statusCode): $message';
}

/// No connectivity (connection errors, socket failures).
class NetworkFailure extends AppFailure {
  const NetworkFailure([
    String message =
        'No internet connection. Please check your network and try again.',
    int? statusCode,
  ]) : super(message, statusCode: statusCode);
}

/// Connect/send/receive timeouts.
class TimeoutFailure extends AppFailure {
  const TimeoutFailure([
    String message =
        'Connection timed out. Please check your internet and try again.',
    int? statusCode,
  ]) : super(message, statusCode: statusCode);
}

/// Invalid credentials or expired/invalid tokens (HTTP 401).
class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure(super.message, {super.statusCode});
}

/// Authenticated but not allowed (HTTP 403).
class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure(super.message, {super.statusCode});
}

/// Entity not found (HTTP 404).
class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message, {super.statusCode});
}

/// Backend rejected the request payload (HTTP 400/422).
class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.statusCode});
}

/// Too many requests (HTTP 429).
class RateLimitFailure extends AppFailure {
  const RateLimitFailure(super.message, {super.statusCode});
}

/// Backend failure (HTTP 5xx).
class ServerFailure extends AppFailure {
  const ServerFailure([
    String message = 'Server error. Please try again later.',
    int? statusCode,
  ]) : super(message, statusCode: statusCode);
}

/// Malformed payloads and anything unclassifiable.
class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([
    String message = 'Something went wrong. Please try again.',
    int? statusCode,
  ]) : super(message, statusCode: statusCode);
}
