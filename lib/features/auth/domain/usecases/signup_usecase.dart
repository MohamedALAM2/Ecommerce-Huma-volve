import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

/// Registers a new account. Does not log the user in; Presentation navigates
/// to Login on success.
class SignUpUseCase {
  final AuthRepository _repository;

  const SignUpUseCase(this._repository);

  Future<UserEntity> call({
    required String name,
    required String email,
    required String password,
  }) {
    return _repository.signUp(name: name, email: email, password: password);
  }
}
