import '../entities/auth_tokens_entity.dart';
import '../entities/user_entity.dart';

/// What the application needs from authentication, expressed without any
/// HTTP, DTO, or storage-plugin details.
///
/// Implemented in Data; consumed by use cases (and therefore, indirectly, by
/// Presentation). All methods throw an [AppFailure] (see `core/error`) on
/// failure instead of returning error codes.
abstract class AuthRepository {
  /// Creates a new account (`POST /users`). Does not log the user in.
  Future<UserEntity> signUp({
    required String name,
    required String email,
    required String password,
  });

  /// Authenticates (`POST /auth/login`) and returns the token pair.
  Future<AuthTokensEntity> login({
    required String email,
    required String password,
  });

  /// Retrieves the profile for a valid access token (`GET /auth/profile`).
  Future<UserEntity> getProfile(String accessToken);

  /// Exchanges a refresh token for a new pair (`POST /auth/refresh-token`).
  Future<AuthTokensEntity> refreshToken(String refreshToken);

  /// Checks email availability (`POST /users/is-available`).
  Future<bool> isEmailAvailable(String email);

  /// Securely persists the token pair. Never stores passwords.
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  });

  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  /// Clears locally stored credentials (logout / revoked session).
  Future<void> clearSession();
}
