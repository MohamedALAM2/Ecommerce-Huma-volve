/// Authentication token pair as the application understands it.
///
/// Pure Dart: no JSON, no Dio, no Flutter.
class AuthTokensEntity {
  final String accessToken;
  final String refreshToken;

  const AuthTokensEntity({
    required this.accessToken,
    required this.refreshToken,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AuthTokensEntity &&
            other.accessToken == accessToken &&
            other.refreshToken == refreshToken);
  }

  @override
  int get hashCode => Object.hash(accessToken, refreshToken);
}
