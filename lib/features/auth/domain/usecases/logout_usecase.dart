import '../repositories/auth_repository.dart';

/// Clears locally stored authentication credentials.
class LogoutUseCase {
  final AuthRepository _repository;

  const LogoutUseCase(this._repository);

  Future<void> call() => _repository.clearSession();
}
