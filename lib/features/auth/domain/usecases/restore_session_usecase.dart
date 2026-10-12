import '../../../../core/error/app_failure.dart';
import '../entities/auth_tokens_entity.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

/// Restored identity together with its valid token pair.
typedef RestoredSession = ({UserEntity user, AuthTokensEntity tokens});

/// Restores a previous session: validates stored tokens against
/// `GET /auth/profile`, refreshing once when the access token expired.
///
/// Returns the session on success, `null` otherwise. Never throws.
///
/// Reliability contract: stored credentials are cleared ONLY when the server
/// genuinely rejects them (invalid/expired refresh token). Recoverable
/// problems — offline, timeouts, 5xx, malformed responses — preserve the
/// stored tokens for the next launch instead of deleting valid credentials.
class RestoreSessionUseCase {
  final AuthRepository _repository;

  const RestoreSessionUseCase(this._repository);

  Future<RestoredSession?> call() async {
    final storedAccess = await _repository.readAccessToken();
    final storedRefresh = await _repository.readRefreshToken();
    if (storedAccess == null ||
        storedAccess.isEmpty ||
        storedRefresh == null ||
        storedRefresh.isEmpty) {
      return null;
    }
    try {
      final user = await _repository.getProfile(storedAccess);
      return (
        user: user,
        tokens: AuthTokensEntity(
          accessToken: storedAccess,
          refreshToken: storedRefresh,
        ),
      );
    } on UnauthorizedFailure {
      // Access token expired/invalid — try the refresh token once below.
    } on AppFailure {
      // Recoverable (offline, timeout, server error): keep stored tokens.
      return null;
    }
    try {
      final fresh = await _repository.refreshToken(storedRefresh);
      final user = await _repository.getProfile(fresh.accessToken);
      await _repository.saveSession(
        accessToken: fresh.accessToken,
        refreshToken: fresh.refreshToken,
      );
      return (user: user, tokens: fresh);
    } on AppFailure catch (e) {
      if (e is UnauthorizedFailure ||
          e is ForbiddenFailure ||
          e is ValidationFailure) {
        // The server genuinely rejected the refresh credentials.
        await _repository.clearSession();
      }
      // Otherwise preserve the stored tokens for a later retry.
      return null;
    }
  }
}
