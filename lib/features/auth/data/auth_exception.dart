/// User-facing authentication error. Carries a message safe to display and
/// an optional HTTP status code for branching (e.g. 401 handling).
class AuthException implements Exception {
  final String message;
  final int? statusCode;

  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException($statusCode): $message';
}
