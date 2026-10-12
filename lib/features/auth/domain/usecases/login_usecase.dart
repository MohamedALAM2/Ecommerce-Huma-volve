import '../entities/auth_tokens_entity.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

/// Authenticated identity together with its token pair.
typedef LoginResult = ({UserEntity user, AuthTokensEntity tokens});

/// Full login flow: authenticate, fetch the profile, persist the token pair.
/// Returns the authenticated user plus tokens. Throws an [AppFailure] on
/// failure.
class LoginUseCase {
  final AuthRepository _repository;

  const LoginUseCase(this._repository);

  Future<LoginResult> call({
    required String email,
    required String password,
  }) async {
    final tokens = await _repository.login(email: email, password: password);
    final user = await _repository.getProfile(tokens.accessToken);
    await _repository.saveSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    return (user: user, tokens: tokens);
  }
}
