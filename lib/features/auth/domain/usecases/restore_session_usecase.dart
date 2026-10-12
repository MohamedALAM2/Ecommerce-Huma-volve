import '../../../../core/error/app_failure.dart';
import '../entities/auth_tokens_entity.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

/// What a session-restoration attempt concluded. Lets callers (e.g. Splash)
/// tell "no session" and "rejected session" apart from a transient
/// verification failure, where stored credentials still exist and a retry
/// makes sense.
enum RestoreOutcome {
  /// A valid session was restored (user authenticated).
  authenticated,

  /// No stored credentials exist (fresh install or logged out).
  noStoredSession,

  /// Stored credentials were rejected by the backend and cleared.
  invalidSession,

  /// Verification failed transiently (offline, timeout, server error,
  /// malformed response); stored credentials were preserved for retry.
  temporaryFailure,
}

/// Outcome of [RestoreSessionUseCase.call], pairing the [outcome] with the
/// restored identity when authentication succeeded.
class RestoreSessionResult {
  final RestoreOutcome outcome;
  final UserEntity? user;
  final AuthTokensEntity? tokens;

  const RestoreSessionResult._({required this.outcome, this.user, this.tokens});

  const RestoreSessionResult.authenticated({
    required UserEntity user,
    required AuthTokensEntity tokens,
  }) : this._(
         outcome: RestoreOutcome.authenticated,
         user: user,
         tokens: tokens,
       );

  const RestoreSessionResult.noStoredSession()
    : this._(outcome: RestoreOutcome.noStoredSession);

  const RestoreSessionResult.invalidSession()
    : this._(outcome: RestoreOutcome.invalidSession);

  const RestoreSessionResult.temporaryFailure()
    : this._(outcome: RestoreOutcome.temporaryFailure);
}

/// Restores a previous session: validates stored tokens against
/// `GET /auth/profile`, refreshing once when the access token expired.
///
/// Never throws. Reliability contract: stored credentials are cleared ONLY
/// when the server genuinely rejects them (invalid/expired refresh token).
/// Recoverable problems — offline, timeouts, 5xx, malformed responses —
/// preserve the stored tokens for the next launch instead of deleting valid
/// credentials.
class RestoreSessionUseCase {
  final AuthRepository _repository;

  const RestoreSessionUseCase(this._repository);

  Future<RestoreSessionResult> call() async {
    final storedAccess = await _repository.readAccessToken();
    final storedRefresh = await _repository.readRefreshToken();
    if (storedAccess == null ||
        storedAccess.isEmpty ||
        storedRefresh == null ||
        storedRefresh.isEmpty) {
      return const RestoreSessionResult.noStoredSession();
    }
    try {
      final user = await _repository.getProfile(storedAccess);
      return RestoreSessionResult.authenticated(
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
      return const RestoreSessionResult.temporaryFailure();
    }
    try {
      final fresh = await _repository.refreshToken(storedRefresh);
      final user = await _repository.getProfile(fresh.accessToken);
      await _repository.saveSession(
        accessToken: fresh.accessToken,
        refreshToken: fresh.refreshToken,
      );
      return RestoreSessionResult.authenticated(user: user, tokens: fresh);
    } on AppFailure catch (e) {
      if (e is UnauthorizedFailure ||
          e is ForbiddenFailure ||
          e is ValidationFailure) {
        // The server genuinely rejected the refresh credentials.
        await _repository.clearSession();
        return const RestoreSessionResult.invalidSession();
      }
      // Otherwise preserve the stored tokens for a later retry.
      return const RestoreSessionResult.temporaryFailure();
    }
  }
}
